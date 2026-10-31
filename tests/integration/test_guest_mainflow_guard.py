#!/usr/bin/env python3
"""Offline regression for host-side clone file writes and explicit opt-in."""
import ast
import importlib.util
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

DRIVER=Path(__file__).with_name('test_guest_mainflow.py')


class GuestGuardTests(unittest.TestCase):
    def test_installed_cli_runtime_rejects_changed_bytes_and_symlinks(self):
        from guest_release_cases import verify_runtime
        with tempfile.TemporaryDirectory(prefix='pnm-cli-delivery.') as directory:
            root=Path(directory)
            runtime=root/'runtime';runtime.mkdir()
            (runtime/'VERSION').write_text('fixture')
            wrapper=root/'pnm';wrapper.write_text('wrapper');wrapper.chmod(0o755)
            manifest=root/'hashes.json'
            manifest.write_text(json.dumps({'install.sh':'installer',
                'VERSION':hashlib.sha256(b'fixture').hexdigest()}))
            verify_runtime(runtime,manifest,wrapper)
            (runtime/'VERSION').write_text('wrong')
            with self.assertRaisesRegex(RuntimeError,'differs'):
                verify_runtime(runtime,manifest,wrapper)
            (runtime/'VERSION').unlink();(runtime/'VERSION').symlink_to(wrapper)
            with self.assertRaisesRegex(RuntimeError,'symlink'):
                verify_runtime(runtime,manifest,wrapper)

    def test_native_release_checks_require_both_complete_suite_summaries(self):
        import guest_release_cases as cases
        from unittest.mock import patch
        def check(condition,label):
            if not condition: raise RuntimeError(label)
        def result(label, *_args):
            count=8 if label=='native-systemd' else 10
            return subprocess.CompletedProcess([],0,('# passed='+str(count)+' failed=0').encode(),b'')
        passed=[]
        with patch.object(cases,'run_private',side_effect=result):
            cases.native_integrations({},Path('/unused'),check,passed)
        self.assertEqual(len(passed),2)
        with patch.object(cases,'run_private',return_value=subprocess.CompletedProcess([],0,b'# passed=7 failed=0',b'')):
            from guest_vm_boot import GuestAcceptanceFailure
            with patch.object(cases.Path,'read_text',return_value="run_test 'fixture' test_fixture\n"), self.assertRaises(GuestAcceptanceFailure) as caught:
                cases.native_integrations({},Path('/unused'),check,[])
            self.assertEqual(caught.exception.summary,{'stage':'native-systemd',
                'reason':'native-systemd incomplete checks','completed_suites':0,
                'error_categories':[],'failed_cases':[]})

    def test_recovery_fingerprint_supports_python310_hashlib(self):
        import guest_recovery_cases as cases
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory(prefix='pnm-recovery-hash.') as directory:
            path=Path(directory)/'fixture'
            data=b'fixture'*(1048576//7+1)
            path.write_bytes(data)
            with patch.object(cases,'hashlib',SimpleNamespace(sha256=hashlib.sha256)):
                result=cases.fingerprint(path)
            self.assertEqual(result[0],hashlib.sha256(data).hexdigest())
            self.assertEqual(result[1],path.stat().st_mode)

    def test_vm_serial_frames_start_on_a_new_line_and_drain_before_power_action(self):
        import select,termios
        from unittest.mock import Mock
        tree=ast.parse(DRIVER.with_name('guest_vm_boot.py').read_text())
        function=next(n for n in ast.walk(tree) if isinstance(n,ast.FunctionDef) and n.name=='emit')
        master,slave=os.openpty()
        try:
            drain=Mock(wraps=termios.tcdrain)
            namespace=dict(os=os,json=json,time=time,select=select,descriptor=slave,
                           termios=type('Serial',(),{'tcdrain':staticmethod(drain)}))
            exec(compile(ast.Module(body=[function],type_ignores=[]),'<VM serial emit>','exec'),namespace)
            namespace['emit']({'kind':'boot-result','passed':True})
            self.assertTrue(select.select([master],[],[],1)[0])
            frame=os.read(master,4096).replace(b'\r\n',b'\n')
            self.assertTrue(frame.startswith(b'\nPNM_VM '))
            self.assertEqual(json.loads(frame.split(b'PNM_VM ',1)[1]),{'kind':'boot-result','passed':True})
            drain.assert_called_once_with(slave)
        finally:
            os.close(master);os.close(slave)

    def test_vm_mainflow_summary_reports_stage_and_exit_without_private_data(self):
        from guest_vm_lifecycle import mainflow_failure_summary
        self.assertEqual(mainflow_failure_summary({'stage':'protected backup and verified restore',
            'reason':'restore exit=78','checks':['done']*18}),
            {'stage':'protected backup and verified restore','reason':'restore exit=78','completed_checks':18})
        summary=mainflow_failure_summary({'stage':'secret-node-password','reason':'vless://private-client-link',
                                        'checks':'private-key-bytes'})
        self.assertEqual(summary,{'stage':'other','reason':'assertion','completed_checks':0})

    def test_vm_clone_removes_only_regular_owned_container_markers(self):
        spec=importlib.util.spec_from_file_location('pnm_vm_marker_host',DRIVER.with_name('host_vm_reboot.py'))
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix='pnm-vm-markers.') as directory:
            root=Path(directory)/'root'
            (root/'run/systemd').mkdir(parents=True)
            for name in ('.dockerenv','run/.containerenv','run/systemd/container'):
                (root/name).write_text('container metadata')
            sentinel=root/'sentinel'
            sentinel.write_text('keep')
            self.assertEqual(len(module.remove_container_markers(root)),3)
            self.assertEqual(module.remove_container_markers(root),[])
            marker=root/'.dockerenv'
            marker.symlink_to(sentinel)
            with self.assertRaises(RuntimeError):module.remove_container_markers(root)
            self.assertTrue(marker.is_symlink())
            self.assertEqual(sentinel.read_text(),'keep')
            marker.unlink()
            os.link(sentinel,marker)
            with self.assertRaises(RuntimeError):module.remove_container_markers(root)
            self.assertEqual(sentinel.read_text(),'keep')
            marker.unlink()
            outside=Path(directory)/'outside'
            outside.mkdir()
            (outside/'container').write_text('keep outside')
            (root/'run/systemd').rmdir()
            (root/'run/systemd').symlink_to(outside,target_is_directory=True)
            with self.assertRaises(RuntimeError):module.remove_container_markers(root)
            self.assertEqual((outside/'container').read_text(),'keep outside')

    def test_vm_approval_requires_owned_identity_and_independent_second_boot(self):
        from unittest.mock import patch
        spec=importlib.util.spec_from_file_location('pnm_vm_host',DRIVER.with_name('host_vm_reboot.py'))
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        expected={'kernel_release':'fixture-kernel','root_uuid':'fixture-root','architecture':'x86_64','container_absent':True}
        first='1'*8+'-'+'1'*4+'-'+'1'*4+'-'+'1'*4+'-'+'1'*12
        second='2'*8+'-'+'2'*4+'-'+'2'*4+'-'+'2'*4+'-'+'2'*12
        ready=dict(expected,schema=1,kind='boot-ready',instance='fixture',scope='pnm-lifecycle',
                   boot_id=first,network_only_loopback=True,machine_id_differs_from_host=True,
                   pnm_absent=True,vm_detected='kvm',manager_state='running')
        approval=module.approve_ready(ready,expected,'fixture','host',None)
        self.assertEqual(approval['action'],'approve-pnm-lifecycle')
        reboot=dict(ready,scope='pnm-reboot',boot_id=second,pnm_absent=False)
        self.assertEqual(module.approve_ready(reboot,expected,'fixture','host',first)['boot_id'],second)
        for bad in (dict(ready,instance='foreign'),dict(ready,network_only_loopback=False),dict(ready,container_absent=False),
                    dict(ready,root_uuid='foreign'),dict(reboot,boot_id=first)):
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                module.approve_ready(bad,expected,'fixture','host',first if bad['scope']=='pnm-reboot' else None)
        with patch.dict(os.environ,{'PNM_RUN_VM_TESTS':'0'}), self.assertRaisesRegex(RuntimeError,'opted-in'):
            module.run_vm(Path('/not-executed'),Path('/not-executed'))

    def test_failure_summary_keeps_step_codes_and_redacts_private_data(self):
        import re
        tree=ast.parse(DRIVER.with_name('guest_mainflow_cases.py').read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='sanitized_failure')
        namespace={'Path':Path,'re':re}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'<safe failure summary>','exec'),namespace)
        with tempfile.TemporaryDirectory(prefix='pnm-safe-failure.') as directory:
            root=Path(directory)
            tx=root/'transactions/tx-fixture';tx.mkdir(parents=True)
            (tx/'journal.tsv').write_text('time\tSTEP_BEGIN\tstage_assets\n'
                'time\tWRITE\tprivate-key-DO-NOT-PRINT\n'
                'time\tSTEP_FAILED\tstage_assets rc=78\n'
                'time\tSTEP_FAILED\tprivate-key-DO-NOT-PRINT rc=78\n'
                'time\tROLLED_BACK\tprivate-key-DO-NOT-PRINT\n')
            report=namespace['sanitized_failure'](
                b'Staged Xray version does not match the approved manifest. private-key-DO-NOT-PRINT '
                b'hysteria2 post-health failed at hysteria_tls_permissions (FAIL) Failed at step LIMITS',root)
            self.assertEqual(report['error_categories'],['xray_version_mismatch','systemd_limits'])
            self.assertIn({'event':'STEP_FAILED','step':'stage_assets','rc':78},report['transaction_events'])
            self.assertEqual(report['health_checks'],[{'core':'hysteria2','check':'hysteria_tls_permissions','status':'FAIL'}])
            self.assertNotIn('private-key-DO-NOT-PRINT',json.dumps(report))

    def test_cgroup_view_is_confined_to_owned_scope_on_both_layouts(self):
        tree=ast.parse(DRIVER.read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verify_cgroup_mounts')
        namespace={}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'<cgroup boundary>','exec'),namespace)
        verify=namespace['verify_cgroup_mounts']
        scope='pnm-fixture.scope'
        unified=['1 0 0:1 /machine.slice/'+scope+'/payload /sys/fs/cgroup rw - cgroup2 cgroup rw']
        hybrid=['1 0 0:1 / /sys/fs/cgroup ro - tmpfs tmpfs ro']+[
            '2 1 0:2 /machine.slice/'+scope+'/payload /sys/fs/cgroup/'+name+' rw - cgroup2 cgroup rw'
            for name in ('systemd','unified')]
        verify(unified,scope)
        verify(hybrid,scope)
        for mounts in ([unified[0].replace('/machine.slice/'+scope+'/payload','/')],
                       [unified[0].replace(scope,'other.scope')],unified+unified,
                       [hybrid[0],hybrid[1]]):
            with self.subTest(mounts=mounts), self.assertRaises(AssertionError):
                verify(mounts,scope)

    def test_exported_template_root_is_searchable_but_parent_stays_private(self):
        source=DRIVER.with_name('prepare_guest_baseline.sh').read_text()
        program=source.split("<<'PY'\n",1)[1].split('\nPY\n',1)[0]
        with tempfile.TemporaryDirectory(prefix='pnm-template-mode.') as directory:
            baseline=Path(directory);root=baseline/'rootfs'
            (root/'etc').mkdir(parents=True)
            root.chmod(0o700)
            (root/'etc/os-release').write_text('ID=debian\nVERSION_ID="13"\n')
            for name in ('passwd','group','shadow','gshadow'):
                (root/'etc'/name).write_text('')
            result=subprocess.run([sys.executable,'-B','-c',program,str(baseline),
                'debian','13','amd64','sha256:fixture','debian@sha256:fixture'],
                capture_output=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            self.assertEqual(stat.S_IMODE(root.stat().st_mode),0o755)
            self.assertEqual(stat.S_IMODE(baseline.stat().st_mode),0o700)
            receipt=json.loads((baseline/'template.json').read_text())
            self.assertEqual((receipt['root_mode_before'],receipt['root_mode']),('0700','0755'))

    def test_template_preparation_refuses_without_ci_opt_in(self):
        env=dict(os.environ,PNM_RUN_GUEST_PREPARE='0')
        result=subprocess.run(['bash',str(DRIVER.with_name('prepare_guest_baseline.sh'))],
                              env=env,capture_output=True,timeout=5)
        self.assertEqual(result.returncode,77)
        self.assertEqual(result.stdout,b'')

    def test_external_ca_fixture_has_trusted_san_pair_and_independent_wrong_key(self):
        tree=ast.parse(DRIVER.with_name('guest_mainflow_cases.py').read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='prepare_external_tls')
        namespace={'Path':Path,'subprocess':subprocess}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'<external TLS fixture>','exec'),namespace)
        with tempfile.TemporaryDirectory(prefix='pnm-mainflow-external-tls.') as directory:
            paths=namespace['prepare_external_tls'](Path(directory)/'inputs')
            result=subprocess.run(['openssl','verify','-CAfile',str(paths['ca']),
                '-verify_hostname','guest.invalid',str(paths['certificate'])],capture_output=True,timeout=5)
            self.assertEqual(result.returncode,0)
            for key,expected in (('key',0),('mismatched_key',1)):
                with self.subTest(key=key):
                    result=subprocess.run(['bash','-c',
                        'source "$1/lib/common.sh"; source "$1/lib/config.sh"; source "$1/lib/tls.sh"; '
                        'pnm_tls_validate_pair "$2" "$3" && pnm_tls_certificate_matches_dns_name "$2" guest.invalid',
                        '--',str(DRIVER.parents[2]),str(paths['certificate']),str(paths[key])],
                        capture_output=True,timeout=5)
                    self.assertEqual(result.returncode,expected)
                    self.assertEqual(stat.S_IMODE(paths[key].stat().st_mode),0o600)

    def test_mainflow_source_identity_detects_changed_missing_and_extra_files(self):
        tree=ast.parse(DRIVER.with_name('guest_mainflow_cases.py').read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verify_source_snapshot')
        namespace={'Path':Path,'hashlib':hashlib,'json':json}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'<source identity>','exec'),namespace)
        with tempfile.TemporaryDirectory(prefix='pnm-mainflow-source.') as directory:
            root=Path(directory)/'pnm'
            (root/'bin').mkdir(parents=True)
            cli=root/'bin/pnm'
            cli.write_text('synthetic CLI source')
            manifest=Path(directory)/'source.json'
            manifest.write_text(json.dumps({'bin/pnm':hashlib.sha256(cli.read_bytes()).hexdigest()}))
            verify=namespace['verify_source_snapshot']
            self.assertEqual(verify(root,manifest)['files'],1)
            self.assertEqual(verify(root,manifest)['manifest_sha256'],hashlib.sha256(manifest.read_bytes()).hexdigest())
            cli.write_text('different source')
            with self.assertRaisesRegex(RuntimeError,'differs'):
                verify(root,manifest)
            cli.unlink()
            with self.assertRaisesRegex(RuntimeError,'differs'):
                verify(root,manifest)
            cli.write_text('synthetic CLI source')
            extra=root/'unexpected.sh'
            extra.write_text('extra source')
            with self.assertRaisesRegex(RuntimeError,'differs'):
                verify(root,manifest)
            extra.unlink()
            extra.symlink_to(cli)
            with self.assertRaisesRegex(RuntimeError,'symlink'):
                verify(root,manifest)

    def test_vm_platform_matches_managed_platform_policy(self):
        import guest_vm_boot as fixture
        adapter=DRIVER.parents[2]/'adapters/platform-linux.sh'
        cases=(('debian','12'),('debian','13'),('ubuntu','22.04'),('ubuntu','24.04'),
               ('ubuntu','20.04'),('debian','14'),('fedora','42'),('ubuntu',''))
        with tempfile.TemporaryDirectory(prefix='pnm-guest-platform.') as directory:
            release=Path(directory)/'os-release'
            for os_id,version in cases:
                with self.subTest(os_id=os_id,version=version):
                    release.write_text(f'ID="{os_id}"\nVERSION_ID="{version}"\n')
                    result=subprocess.run(['bash','-c',
                        'source "$1"; PNM_OS_RELEASE_FILE="$2"; uname() { printf "x86_64\\n"; }; pnm_platform_supported',
                        '--',str(adapter),str(release)],capture_output=True,timeout=5)
                    with patch.object(fixture.platform,'freedesktop_os_release',
                                      return_value={'ID':os_id,'VERSION_ID':version}):
                        if result.returncode==0:
                            self.assertEqual(fixture.guest_operating_system(),(os_id,version))
                        else:
                            with self.assertRaises(fixture.GuestRefusal):
                                fixture.guest_operating_system()

    @unittest.skipUnless(sys.platform=='linux','Linux VM acquisition guard')
    def test_install_acquisition_refuses_host_before_io(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_acquisition_cases as fixture
from guest_vm_boot import GuestRefusal
def forbidden(*args,**kwargs):
    raise AssertionError('host reached acquisition fixture mutation')
fixture.subprocess.run=forbidden
fixture.Path.mkdir=forbidden
try:
    fixture.run_acquisition(None,None,None,None,[])
except GuestRefusal:
    pass
else:
    raise AssertionError('host accepted for acquisition fixture')
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux VM-only space refusal')
    def test_disk_space_fault_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_commit_fault as fixture
from guest_commit_space import SpaceFault
from guest_vm_boot import GuestRefusal
def forbidden(*args,**kwargs):
    raise AssertionError('host reached disk-space fault mutation')
fixture.subprocess.run=forbidden
fixture.os.open=forbidden
for entry in (lambda:fixture.run_commit([],None,candidate='space'),
              lambda:fixture.run_commit([],None,candidate='space-pending'),
              lambda:fixture.run_commit([],None,candidate='inode'),
              lambda:fixture.run_commit([],None,candidate='inode-pending'),
              lambda:fixture.readonly_deployment_commit(None,None,candidate='space').__enter__(),
              lambda:fixture.readonly_deployment_commit(None,None,candidate='space-pending').__enter__(),
              lambda:fixture.readonly_deployment_commit(None,None,candidate='inode').__enter__(),
              lambda:fixture.readonly_deployment_commit(None,None,candidate='inode-pending').__enter__(),
              lambda:SpaceFault(None,None)):
    try:
        entry()
    except GuestRefusal:
        pass
    else:
        raise AssertionError('host accepted for disk-space fault')
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux VM-only inode refusal')
    def test_inode_space_fault_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
from guest_commit_space import InodeFault
from guest_vm_boot import GuestRefusal
try:
    InodeFault(None,None)
except GuestRefusal:
    pass
else:
    raise AssertionError('host accepted for inode-space fault')
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux bounded storage refusal')
    def test_bounded_storage_worker_refuses_parent_before_mounts(self):
        script='''import os,sys
sys.path.insert(0,sys.argv[1])
import test_commit_storage as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('parent reached storage mutation')
fixture.subprocess.run=forbidden
fixture.tempfile.mkdtemp=forbidden
for enabled,parent_override in ((False,None),(True,None),(True,0)):
    os.environ['PNM_RUN_STORAGE_TESTS']='1' if enabled else '0'
    expected=('bounded storage requires a private mount namespace' if os.geteuid()==0
              else 'bounded storage requires Linux root') if enabled else 'explicit bounded storage opt-in required'
    try:
        fixture.run_case('create',os.stat('/proc/self/ns/mnt').st_ino if parent_override is None else parent_override)
    except RuntimeError as error:
        assert str(error)==expected
    else:
        raise AssertionError('parent accepted as storage child')
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              env={**os.environ,'PNM_RUN_STORAGE_TESTS':'1'},
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux actual mkstemp observer placement')
    def test_candidate_create_observer_arms_before_actual_mkstemp(self):
        script='''import contextlib,json,sys,tempfile,time,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import RENAME_TRACE_SOURCE
entered=[]
guard=types.ModuleType('guest_commit_signal')
guard.require_publisher_guest=lambda:None
mount=types.ModuleType('guest_io_fault')
@contextlib.contextmanager
def readonly(parent,*args,**kwargs):
    assert not list(parent.glob('.commit-*')), 'creation observer was late'
    entered.append(parent)
    yield {'private_namespace':True}
mount.readonly_bind=readonly
sys.modules['guest_commit_signal']=guard
sys.modules['guest_io_fault']=mount
with tempfile.TemporaryDirectory(prefix='pnm-candidate-create.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root),'identity':[1,2],
        'parent_namespace':3,'phase':'create'}))
    (root/'commit-uncertain.env').write_text('pending')
    sys.argv=['-','publish',str(root),'test-id','test-deploy',str(int(time.time())+60)]
    namespace={'__file__':str(root/'sitecustomize.py')}
    try:
        exec(compile(RENAME_TRACE_SOURCE,'sitecustomize.py','exec'),namespace)
        program="""import os,tempfile
directory=str(root)
temporary=None
descriptor,temporary=tempfile.mkstemp(prefix='.commit-',dir=directory)
os.close(descriptor)
assert entered==[root]
assert Path(temporary).is_file()
"""
        exec(compile(program,'<stdin>','exec'),{'root':root,'entered':entered,'Path':Path})
    finally:
        sys.settrace(None)
        namespace['finish']()
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux inode exhaustion observer')
    def test_inode_observer_records_enospc_from_real_mkstemp_frame(self):
        script='''import errno,json,os,sys,tempfile,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import RENAME_TRACE_SOURCE
phase=sys.argv[2]
class Fault:
    def __init__(self,*args): self.released=False
    def fill(self): return {'private_namespace':True,'inode_exhausted':True}
    def release(self): self.released=True
signal=types.ModuleType('guest_commit_signal')
signal.require_publisher_guest=lambda:None
mount=types.ModuleType('guest_io_fault')
mount.readonly_bind=lambda *args,**kwargs:None
space=types.ModuleType('guest_commit_space')
space.InodeFault=Fault
boot=types.ModuleType('guest_vm_boot')
boot.require_approved_vm=lambda:None
sys.modules.update({'guest_commit_signal':signal,'guest_io_fault':mount,
                    'guest_commit_space':space,'guest_vm_boot':boot})
with tempfile.TemporaryDirectory(prefix='pnm-inode-observer.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root),'identity':[1,2],
        'parent_namespace':3,'phase':phase}))
    if phase=='inode':
        (root/'commit-uncertain.env').write_text('pending')
    sys.argv=['-','publish',str(root),'test-id','test-deploy','9999999999']
    namespace={'__file__':str(root/'sitecustomize.py')}
    original_open=os.open
    original_statvfs=os.statvfs
    def no_inodes(path,flags,mode=0o777):
        name=os.fspath(path)
        if name.startswith(str(root)+'/.commit-') or name==str(root/'commit-uncertain.env'):
            raise OSError(errno.ENOSPC,'no inodes',name)
        return original_open(path,flags,mode)
    class Exhausted:
        f_favail=0
        f_bavail=1
    try:
        exec(compile(RENAME_TRACE_SOURCE,'sitecustomize.py','exec'),namespace)
        os.open=no_inodes
        os.statvfs=lambda path:Exhausted()
        try:
            # Match the publisher entry frame the VM observer watches.
            program=("pending=directory+'/commit-uncertain.env'\\nos.open(pending,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)"
                     if phase=='inode-pending' else "tempfile.mkstemp(prefix='.commit-',dir=directory)")
            exec(compile(program,'<stdin>','exec'),
                 {'tempfile':tempfile,'os':os,'directory':str(root)})
            raise AssertionError('candidate unexpectedly created')
        except OSError as error:
            assert error.errno==errno.ENOSPC
    finally:
        os.open=original_open
        os.statvfs=original_statvfs
        sys.settrace(None)
        namespace['finish']()
    assert (root/'observed-rename.json').exists()
    observed=json.loads((root/'observed-rename.json').read_text())
    event='pending_creation_inode_refused' if phase=='inode-pending' else 'candidate_create_inode_refused'
    assert observed[event] and observed['inode_exhausted']
    assert observed['inodes_recovered'] and observed['pending_retained']==(phase=='inode')
'''
        for phase in ('inode','inode-pending'):
            with self.subTest(phase=phase):
                result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent),phase],
                                      capture_output=True,timeout=15)
                self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux pending space observer')
    def test_pending_space_observer_releases_after_stream_close(self):
        script='''import errno,json,os,sys,tempfile,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import RENAME_TRACE_SOURCE
state={'closed':False}
class Fault:
    def __init__(self,*args): pass
    def fill(self): return {'private_namespace':True,'fill_errno':errno.ENOSPC}
    def release(self): assert state['closed'], 'filler released before buffered close'
signal=types.ModuleType('guest_commit_signal')
signal.require_publisher_guest=lambda:None
mount=types.ModuleType('guest_io_fault')
mount.readonly_bind=lambda *args,**kwargs:None
space=types.ModuleType('guest_commit_space')
space.SpaceFault=Fault
sys.modules.update({'guest_commit_signal':signal,'guest_io_fault':mount,'guest_commit_space':space})
class Stream:
    closed=False
    def __init__(self,descriptor): self.descriptor=descriptor
    def flush(self): raise OSError(errno.ENOSPC,'no blocks')
    def close(self):
        os.close(self.descriptor)
        self.closed=True
        state['closed']=True
with tempfile.TemporaryDirectory(prefix='pnm-pending-space-observer.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root),'identity':[1,2],
        'parent_namespace':3,'phase':'space-pending'}))
    sys.argv=['-','publish',str(root),'test-id','test-deploy','9999999999']
    namespace={'__file__':str(root/'sitecustomize.py')}
    program="pending=directory+'/commit-uncertain.env'\\ndescriptor=os.open(pending,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)\\nstream=Stream(descriptor)\\ntry:\\n stream.flush()\\nfinally:\\n stream.close()"
    try:
        exec(compile(RENAME_TRACE_SOURCE,'sitecustomize.py','exec'),namespace)
        try:
            exec(compile(program,'<stdin>','exec'),{'directory':str(root),'os':os,'Stream':Stream})
            raise AssertionError('write unexpectedly succeeded')
        except OSError as error:
            assert error.errno==errno.ENOSPC
    finally:
        sys.settrace(None)
        namespace['finish']()
    observed=json.loads((root/'observed-rename.json').read_text())
    assert observed['pending_write_space_refused'] and observed['pending_empty']
    assert observed['space_recovered'] and observed['pending_retained']
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux candidate refusal guards')
    def test_candidate_variants_refuse_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_commit_fault as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached candidate fault control')
fixture.os.open=forbidden
fixture.subprocess.run=forbidden
for candidate in ('create','write'):
    for entry in (lambda:fixture.run_commit([],None,candidate=candidate),
                  lambda:fixture.readonly_deployment_commit(None,None,candidate=candidate).__enter__()):
        try:
            entry()
            raise AssertionError('host accepted for candidate fault')
        except RuntimeError as error:
            assert str(error)=='start fault requires mapped guest root'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux root candidate FD policy')
    def test_candidate_write_observer_gets_real_efbig_and_restores_limit(self):
        script='''import errno,json,resource,sys,tempfile,time,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import RENAME_TRACE_SOURCE
guard=types.ModuleType('guest_commit_signal')
guard.require_publisher_guest=lambda:None
mount=types.ModuleType('guest_io_fault')
def forbidden(*args,**kwargs):
    raise AssertionError('write fixture unexpectedly entered a bind')
mount.readonly_bind=forbidden
sys.modules['guest_commit_signal']=guard
sys.modules['guest_io_fault']=mount
original=resource.getrlimit(resource.RLIMIT_FSIZE)
with tempfile.TemporaryDirectory(prefix='pnm-candidate-write.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root),'identity':[1,2],
        'parent_namespace':3,'phase':'write'}))
    sys.argv=['-','publish',str(root),'test-id','test-deploy',str(int(time.time())+60)]
    namespace={'__file__':str(root/'sitecustomize.py')}
    try:
        exec(compile(RENAME_TRACE_SOURCE,'sitecustomize.py','exec'),namespace)
        program="""import os,tempfile
directory=str(root)
temporary=None
with (root/'commit-uncertain.env').open('w') as stream:
    stream.write('pending')
descriptor,temporary=tempfile.mkstemp(prefix='.commit-',dir=directory)
try:
    with os.fdopen(descriptor,'wb') as stream:
        stream.write(b'marker candidate')
        stream.flush()
        os.fsync(stream.fileno())
except OSError as error:
    assert error.errno==errno.EFBIG
else:
    raise AssertionError('actual candidate write was not refused')
finally:
    os.unlink(temporary)
"""
        exec(compile(program,'<stdin>','exec'),{'root':root,'errno':errno})
    finally:
        sys.settrace(None)
        namespace['finish']()
        assert resource.getrlimit(resource.RLIMIT_FSIZE)==original
    proof=json.loads((root/'observed-rename.json').read_text())
    assert proof['actual_errno']==errno.EFBIG and proof['candidate_write_refused']
    assert proof['file_size_limit_restored'] and proof['pending_retained']
    assert (root/'commit-uncertain.env').read_text()=='pending'
    assert not (root/'commit.env').exists()
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux marker candidate observer timing')
    def test_rename_observer_waits_for_written_closed_candidate(self):
        script='''import contextlib,json,sys,tempfile,time,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import RENAME_TRACE_SOURCE
entered=[]
guard=types.ModuleType('guest_commit_signal')
guard.require_publisher_guest=lambda:None
mount=types.ModuleType('guest_io_fault')
@contextlib.contextmanager
def readonly(*args,**kwargs):
    entered.append(args[0])
    yield {'private_namespace':True}
mount.readonly_bind=readonly
sys.modules['guest_commit_signal']=guard
sys.modules['guest_io_fault']=mount
with tempfile.TemporaryDirectory(prefix='pnm-rename-observer.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root),'identity':[1,2],'parent_namespace':3}))
    sys.argv=['-','publish',str(root),'test-id','test-deploy',str(int(time.time())+60)]
    namespace={'__file__':str(root/'sitecustomize.py')}
    try:
        exec(compile(RENAME_TRACE_SOURCE,'sitecustomize.py','exec'),namespace)
        program="""import os,tempfile
directory=str(root)
temporary=None
with (root/'commit-uncertain.env').open('w') as stream:
    stream.write('pending')
descriptor,temporary=tempfile.mkstemp(prefix='.commit-',dir=directory)
assert not entered
with os.fdopen(descriptor,'wb') as stream:
    stream.write(b'closed candidate')
    stream.flush()
    os.fsync(stream.fileno())
    assert not entered
assert entered==[root]
"""
        exec(compile(program,'<stdin>','exec'),{'root':root,'entered':entered})
    finally:
        sys.settrace(None)
        namespace['finish']()
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux marker rename refusal guard')
    def test_marker_rename_variant_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_commit_fault as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached rename fault control')
fixture.os.open=forbidden
fixture.subprocess.run=forbidden
for entry in (lambda:fixture.run_commit([],None,rename=True),
              lambda:fixture.readonly_deployment_commit(None,None,rename=True).__enter__()):
    try:
        entry()
        raise AssertionError('host accepted for rename fault')
    except RuntimeError as error:
        assert str(error)=='start fault requires mapped guest root'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux actual directory fsync observer')
    def test_progress_observer_waits_for_final_fsync_return(self):
        script='''import json,sys,tempfile,types
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_progress import TRACE_SOURCE
observed=[]
fake=types.ModuleType('guest_commit_progress')
fake.seal_progress=lambda control,transaction:observed.append(transaction)
sys.modules['guest_commit_progress']=fake
with tempfile.TemporaryDirectory(prefix='pnm-progress-observer.') as directory:
    root=Path(directory)
    (root/'config.json').write_text(json.dumps({'transaction':str(root)}))
    try:
        exec(compile(TRACE_SOURCE,'sitecustomize.py','exec'),{'__file__':str(root/'sitecustomize.py')})
        program="""import os
temporary=None
def sync_directory(path):
    descriptor=os.open(path,os.O_RDONLY|os.O_DIRECTORY)
    try: os.fsync(descriptor)
    finally: os.close(descriptor)
sync_directory(str(root))
assert not observed
(root/'commit.env').write_text('test marker')
(root/'commit-uncertain.env').write_text('pending')
sync_directory(str(root))
assert not observed
(root/'commit-uncertain.env').unlink()
sync_directory(str(root))
"""
        exec(compile(program,'<stdin>','exec'),{'root':root,'observed':observed})
    finally:
        sys.settrace(None)
    assert observed==[root], 'final fsync return was not observed exactly once'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux committed progress refusal guard')
    def test_committed_progress_fault_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_commit_progress as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached committed-progress control')
fixture.os.open=forbidden
fixture.subprocess.run=forbidden
for entry in (lambda:fixture.run_publisher([],None),
              lambda:fixture.readonly_committed_progress(None,None).__enter__()):
    try:
        entry()
        raise AssertionError('host accepted for committed progress fault')
    except RuntimeError as error:
        assert str(error)=='start fault requires mapped guest root'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux previous executable fixture')
    def test_vm_previous_pair_checks_actual_binary_version(self):
        script='''import sys,tempfile
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import guest_vm_lifecycle as fixture
with tempfile.TemporaryDirectory(prefix='pnm-previous-pair.') as directory:
    root=Path(directory)
    fixture.Path=lambda unused:root
    for core,output in (('xray','Xray 1.2.3'),('hysteria2','Version: v1.2.3')):
        folder=root/core
        folder.mkdir()
        binary=folder/'previous'
        binary.write_text('#!'+sys.executable+'\\nprint('+repr(output)+')\\n')
        binary.chmod(0o700)
        metadata=folder/'previous.env'
        metadata.write_text('SCHEMA_VERSION=1\\nCORE='+core+'\\nVERSION=1.2.3\\n')
        fixture.previous_pair(core)
        wrong='SCHEMA_VERSION=1\\nCORE='+core+'\\nVERSION=9.9.9\\n'
        metadata.write_text(wrong)
        try:
            fixture.previous_pair(core)
            raise AssertionError('mismatched previous metadata accepted')
        except RuntimeError as error:
            assert str(error)=='reboot previous binary and metadata version differ'
        assert metadata.read_text()==wrong
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    def test_abrupt_vm_journal_observation_retains_torn_bytes(self):
        script='''import sys,tempfile
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_vm_abrupt import journal_observation
with tempfile.TemporaryDirectory(prefix='pnm-torn-journal.') as directory:
    path=Path(directory)/'journal.tsv'
    original=b'time\\tBEGIN\\toperation=deployment\\n'+bytes([0])*64
    path.write_bytes(original)
    report=journal_observation(path)
    assert report['malformed_rows']==1 and report['row_count']==2
    assert not report['commit_intent_present'] and not report['terminal_present']
    assert path.read_bytes()==original
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux abrupt VM worker refusal')
    def test_abrupt_vm_worker_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_vm_abrupt as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached abrupt VM control')
fixture.os.open=forbidden
fixture.subprocess.Popen=forbidden
fixture.subprocess.run=forbidden
try:
    fixture.main()
    raise AssertionError('host accepted for abrupt VM test')
except fixture.GuestRefusal:
    pass
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    def test_vm_reboot_cli_preserves_plain_and_json_output_contracts(self):
        tree=ast.parse(DRIVER.with_name('guest_vm_lifecycle.py').read_text())
        outer=next(node for node in tree.body if isinstance(node,ast.FunctionDef)
                   and node.name=='reboot_acceptance')
        function=next(node for node in outer.body if isinstance(node,ast.FunctionDef)
                      and node.name=='call')
        from unittest.mock import Mock
        runner=Mock()
        with tempfile.TemporaryDirectory(prefix='pnm-vm-output-contract.') as directory:
            namespace={'subprocess':runner,'logs':Path(directory),'json':json,
                       'need':lambda condition,label:self.assertTrue(condition,label)}
            exec(compile(ast.Module(body=[function],type_ignores=[]),'<actual-vm-cli-call>','exec'),namespace)
            runner.run.return_value=subprocess.CompletedProcess([],0,b'Core restart complete.\n',b'')
            self.assertEqual(namespace['call']('restart',['restart','xray']),{})
            runner.run.return_value=subprocess.CompletedProcess([],78,b'{"safe":true}\n',b'')
            self.assertEqual(namespace['call']('show',['--json','node','show'],(78,)),{'safe':True})

    @unittest.skipUnless(sys.platform=='linux','Linux VM worker refusal')
    def test_independent_vm_worker_refuses_host_before_controls(self):
        if Path('/sys/firmware/qemu_fw_cfg/by_name/opt/pnm/instance/raw').exists():
            self.skipTest('actual explicitly prepared VM environment')
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_vm_boot as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached VM control operation')
fixture.os.open=forbidden
fixture.os.system=forbidden
fixture.os.kill=forbidden
fixture.os.killpg=forbidden
fixture.subprocess.run=forbidden
fixture.subprocess.Popen=forbidden
for entry in (fixture.require_vm,fixture.require_approved_vm,fixture.main):
    try:
        entry()
        raise AssertionError('host accepted as independent VM')
    except fixture.GuestRefusal as error:
        assert str(error)=='VM worker requires the approved independent guest'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux VM lifecycle worker refusal')
    def test_independent_vm_lifecycle_refuses_host_before_controls(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_vm_lifecycle as fixture
def forbidden(*args,**kwargs):
    raise AssertionError('host reached lifecycle control operation')
fixture.os.open=forbidden
fixture.subprocess.run=forbidden
try:
    fixture.main()
    raise AssertionError('host accepted as lifecycle VM')
except fixture.GuestRefusal:
    pass
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux VM approval policy')
    def test_vm_mutation_rejects_stale_boot_approval(self):
        script='''import json,os,sys,tempfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,sys.argv[1])
import guest_vm_boot as fixture
identity=fixture.VmIdentity('a'*32,'current-boot','root','kernel','b'*64)
with tempfile.TemporaryDirectory(prefix='pnm-stale-vm-approval.') as directory:
    proof=Path(directory)/'approval'
    proof.write_text(json.dumps({'schema':1,'instance':identity.instance,
        'boot_id':'previous-boot','scope':'pnm-lifecycle'}))
    proof.chmod(0o600)
    with patch.object(fixture,'require_vm',return_value=identity),patch.object(fixture,'Path',return_value=proof):
        try:
            fixture.require_approved_vm()
            raise AssertionError('stale VM approval accepted')
        except fixture.GuestRefusal:
            pass
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux actual cases host refusal')
    def test_actual_mainflow_cases_refuse_host_before_writes(self):
        script='''import runpy,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
def forbidden(*args,**kwargs):
    raise AssertionError('host reached actual case write')
Path.mkdir=forbidden
try:
    runpy.run_path(str(Path(sys.argv[1])/'guest_mainflow_cases.py'),run_name='__main__')
    raise AssertionError('host accepted for actual cases')
except SystemExit as error:
    assert error.code==77
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux work-directory policy')
    def test_custom_work_directory_rejects_unsafe_paths_before_fixture_access(self):
        with tempfile.TemporaryDirectory(prefix='pnm-workdir-guard.') as directory:
            root=Path(directory)
            public=root/'public'
            public.mkdir()
            public.chmod(0o777)
            link=root/'link'
            link.symlink_to(root,target_is_directory=True)
            regular=root/'regular'
            regular.write_text('sentinel')
            foreign=root/'foreign'
            foreign.mkdir(mode=0o700)
            os.chown(foreign,65534,65534)
            for candidate in (public,link,regular,foreign):
                for scenario in ('lifecycle','restore-publication'):
                    result=subprocess.run([sys.executable,'-B',str(DRIVER),
                        '--baseline',str(root/'missing-baseline'),'--nspawn',str(root/'missing-nspawn'),
                        '--asset-cache',str(root/'missing-assets'),'--work-dir',str(candidate),
                        '--scenario',scenario],env={**os.environ,'PNM_RUN_GUEST_TESTS':'1'},
                        capture_output=True,timeout=10)
                    self.assertNotEqual(result.returncode,0)
                    self.assertIn(b'work directory required',result.stderr)
                    self.assertEqual(result.stdout,b'')
            self.assertEqual(regular.read_text(),'sentinel')

    @unittest.skipUnless(sys.platform=='linux','Linux namespace guard')
    def test_start_fault_refuses_host_before_mutation_or_network(self):
        script='''import sys
sys.path.insert(0,sys.argv[1])
import guest_start_fault as fixture
import guest_recovery_cases as recovery
import guest_tls_access as tls
import guest_account_cases as accounts
import guest_signal_cases as interruption
import guest_readiness_cases as readiness
import guest_preflight_cases as preflight
import guest_deployment_cases as deployment
import guest_update_cases as updates
import guest_io_fault as io_fault
import guest_commit_fault as commit_fault
def forbidden(*args,**kwargs):
    raise AssertionError('fixture acted before its namespace guard')
fixture.socket.socket=forbidden
fixture.subprocess.run=forbidden
for name in ('open','mkdir','unlink','rmdir'):
    setattr(fixture.os,name,forbidden)
for mode in ('reject-once','reject-twice','delay','delay-pre'):
    try:
        with fixture.start_fault('xray',mode=mode):
            raise AssertionError('host entered guest fixture')
    except RuntimeError as error:
        assert str(error)=='start fault requires mapped guest root'
for entry in (
    lambda: recovery.run_core_recovery_failure(forbidden,forbidden,'xray',[]),
    lambda: recovery.run_restore_recovery_failure(None,forbidden,forbidden,forbidden,(),None,[]),
    lambda: recovery.require_commands_blocked(forbidden,forbidden,'xray',[]),
    lambda: tls.run_tls_access(None,None,forbidden,forbidden,forbidden,forbidden,[]),
    lambda: accounts.prepare_accounts(),
    lambda: accounts.require_preserved({}),
    lambda: interruption.run_interruptions(None,forbidden,forbidden,forbidden,forbidden,[]),
    lambda: interruption.run_restore_interruptions(None,forbidden,forbidden,forbidden,forbidden,(),None,{},[]),
    lambda: interruption.signal_owned_command_on_start({},15).__enter__(),
    lambda: io_fault.readonly_publication(None,None,'/var/lib/pnm/cores/xray/previous').__enter__(),
    lambda: io_fault.run_move([],None),
    lambda: io_fault.run_move([],None,isolated=True),
    lambda: io_fault.unmount_owned(None,None,None),
    lambda: io_fault.readonly_bind(None,None,None,None).__enter__(),
    lambda: commit_fault.readonly_deployment_commit(None,None).__enter__(),
    lambda: commit_fault.run_commit([],None),
    lambda: __import__('guest_commit_signal').late_deployment_commit(None,None).__enter__(),
    lambda: __import__('guest_commit_signal').run_late_commit([],None),
    lambda: __import__('guest_commit_signal').run_late_interruption(None,None,forbidden,[]),
    lambda: __import__('guest_account_fault').readonly_account_creation(None,None,'groupadd').__enter__(),
    lambda: __import__('guest_account_fault').run_account_tool([],None),
    lambda: __import__('guest_account_fault').run_account_tool([],None,isolated=True),
    lambda: accounts.run_creation_failures(None,None,forbidden,forbidden,[]),
    lambda: __import__('guest_account_fault').readonly_account_tool(None,None,'userdel').__enter__(),
    lambda: accounts.run_deletion_failure(None,None,forbidden,[],program='userdel'),
    lambda: readiness.run_restart_readiness(None,forbidden,forbidden,forbidden,forbidden,[]),
    lambda: preflight.run_dependencies(None,None,forbidden,forbidden,[]),
    lambda: deployment.run_startup_failures(None,forbidden,forbidden,[]),
    lambda: deployment.require_pending_deployment(forbidden,forbidden,[]),
):
    try:
        entry()
        raise AssertionError('host entered recovery fixture')
    except RuntimeError as error:
        assert str(error)=='start fault requires mapped guest root'
try:
    updates.run_updates(None,None,forbidden,forbidden,forbidden,forbidden,[],interruption='term')
    raise AssertionError('host entered update interruption fixture')
except RuntimeError as error:
    assert str(error)=='updates require isolated mapped guest root'
fixture.require_guest=lambda: None
io_fault.require_guest=lambda: None
for target in ('/','/etc/passwd','/var/lib/pnm/cores/xray/../hysteria2/previous',None):
    try:
        with io_fault.readonly_publication(None,None,target):
            raise AssertionError('unsafe publication target accepted')
    except RuntimeError as error:
        assert str(error)=='unexpected publication target'
for fault_mode in ('delay','delay-pre'):
    for delay in (0,16,'3',True,3.0,None):
        try:
            with fixture.start_fault('xray',mode=fault_mode,delay_seconds=delay):
                raise AssertionError('invalid delay entered fault fixture')
        except RuntimeError as error:
            assert str(error)=='bounded integer startup delay required'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Python late publisher observer')
    def test_late_commit_observer_filters_real_publication_window(self):
        script='''import sys,json,tempfile,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_signal import TRACE_SOURCE
with tempfile.TemporaryDirectory(prefix='pnm-late-observer.') as directory:
    private=Path(directory)
    transaction=private/'tx'
    transaction.mkdir()
    (private/'config.json').write_text(json.dumps({'transaction':str(transaction)}))
    namespace={'__file__':str(private/'sitecustomize.py')}
    pauses=[]
    original=time.sleep
    time.sleep=pauses.append
    try:
        exec(compile(TRACE_SOURCE,str(private/'sitecustomize.py'),'exec'),namespace)
        program='temporary=None\\ndef sync_directory(path):\\n    pass\\nsync_directory(directory)\\n'
        values={'directory':str(transaction),'temporary':None}
        exec(compile(program,'<stdin>','exec'),values)
        assert not (private/'ready.json').exists() and not pauses
        (transaction/'commit.env').write_text('fixture marker')
        exec(compile(program,'<stdin>','exec'),values)
        assert not (private/'ready.json').exists() and not pauses
        (transaction/'commit-uncertain.env').write_text('fixture uncertainty')
        exec(compile(program,'other.py','exec'),values)
        assert not (private/'ready.json').exists() and not pauses
        exec(compile(program,'<stdin>','exec'),values)
        assert json.loads((private/'ready.json').read_text())=={
            'marker_present':True,'uncertainty_present':True,'before_directory_sync':True}
        assert pauses==[30] and sys.gettrace() is None
        print('flow-preserved')
    finally:
        time.sleep=original
        sys.settrace(None)
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        self.assertEqual(result.stdout,b'flow-preserved\n')

    @unittest.skipUnless(sys.platform=='linux','Python publisher observer')
    def test_commit_observer_preserves_flow_and_filters_exception_path(self):
        script='''import sys,json,os,subprocess,tempfile
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from guest_commit_fault import TRACE_SOURCE
with tempfile.TemporaryDirectory(prefix='pnm-trace-guard.') as directory:
    private=Path(directory)
    (private/'sitecustomize.py').write_text(TRACE_SOURCE)
    (private/'config.json').write_text(json.dumps({'transaction':str(private/'tx')}))
    program='\\n'.join([
        'import errno,sys',
        'from pathlib import Path',
        'receipt=Path(sys.argv[2])',
        'for number,path in ((errno.EROFS,sys.argv[1]+".other"),(errno.EACCES,sys.argv[1])):',
        '    try: raise OSError(number,"observer fixture",path)',
        '    except OSError: pass',
        'assert not receipt.exists()',
        'try: raise OSError(errno.EROFS,"observer fixture",sys.argv[1])',
        'except OSError: pass',
        'print("flow-preserved")'])
    result=subprocess.run([sys.executable,'-B','-',str(private/'tx/commit-uncertain.env'),
        str(private/'observed-exception.json')],input=program.encode(),capture_output=True,
        env={**os.environ,'PYTHONPATH':str(private)},timeout=10)
    assert result.returncode==0 and result.stdout==b'flow-preserved\\n' and not result.stderr
    assert json.loads((private/'observed-exception.json').read_text())=={
        'actual_errno':30,'pending_creation_refused':True}
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'private Linux curl transport')
    def test_asset_transport_refusals_use_real_curl_and_retire_connections(self):
        script='''import os,ssl,subprocess,sys,tempfile,threading
from pathlib import Path
assert os.stat('/proc/self/ns/net').st_ino!=int(sys.argv[2])
subprocess.run(['ip','link','set','lo','up'],check=True,capture_output=True)
sys.path.insert(0,sys.argv[1])
from guest_update_cases import AssetServer
with tempfile.TemporaryDirectory(prefix='pnm-curl-refusal.') as directory:
    root=Path(directory)
    cert=root/'fixture.crt'
    key=root/'fixture.key'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
        '-subj','/CN=github.com','-addext','subjectAltName=DNS:github.com',
        '-keyout',str(key),'-out',str(cert)],check=True,capture_output=True,timeout=10)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(cert),str(key))
    server=AssetServer({'/expected':b'fixture'},context)
    worker=threading.Thread(target=server.serve_forever)
    worker.start()
    def curl(trust):
        return subprocess.run(['curl','--silent','--show-error','--fail','--location',
            '--proto','=https','--tlsv1.2','--max-time','10','--noproxy','',
            '--proxy','http://127.0.0.1:'+str(server.server_address[1]),
            '--cacert',str(trust),'https://github.com/expected','--output',str(root/'output')],
            capture_output=True,timeout=15)
    try:
        assert curl(cert).returncode==0
        assert (root/'output').read_bytes()==b'fixture'
        server.partial_paths.add('/expected')
        result=curl(cert)
        assert result.returncode==18 and b'curl: (18)' in result.stderr
        assert 0<(root/'output').stat().st_size<7
        server.partial_paths.clear()
        server.tls_refusal_budget=1
        result=curl('/etc/ssl/certs/ca-certificates.crt')
        assert result.returncode==60 and b'curl: (60)' in result.stderr
        assert server.tls_refusals==1 and server.tls_refusal_budget==0
        assert server.requests==['/expected','/expected']
        assert server.partial_requests==['/expected'] and not server.errors
        assert curl(cert).returncode==0 and (root/'output').read_bytes()==b'fixture'
    finally:
        server.shutdown();server.server_close();worker.join(timeout=2)
    assert not worker.is_alive() and not server.connections
    assert not any(t.is_alive() for t in server.request_threads)
'''
        result=subprocess.run(['unshare','--net',sys.executable,'-B','-c',script,
                               str(DRIVER.parent),str(os.stat('/proc/self/ns/net').st_ino)],
                              capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    def test_asset_headers_have_line_count_and_total_bounds(self):
        spec=importlib.util.spec_from_file_location('pnm_asset_guard',DRIVER.with_name('guest_update_cases.py'))
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        request=module.AssetRequest.__new__(module.AssetRequest)
        self.assertEqual(request.headers(io.BytesIO(b'GET /expected HTTP/1.1\r\nHost: github.com\r\n\r\n')),
                         b'GET /expected HTTP/1.1')
        for malformed in (b'x'*8193+b'\r\n\r\n',
                          b'GET / HTTP/1.1\r\n'+b'X: 1\r\n'*101+b'\r\n',
                          b'GET / HTTP/1.1\r\n'+(b'X: '+b'x'*8000+b'\r\n')*9+b'\r\n',
                          b'GET / HTTP/1.1\r\nHost: incomplete'):
            with self.assertRaises(RuntimeError):
                request.headers(io.BytesIO(malformed))

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'private Linux network namespace')
    def test_asset_fixture_rejects_unexpected_requests_and_retires_incomplete_io(self):
        # The child proves its network namespace differs before raising lo.
        # No socket or interface is created/changed in the host namespace.
        script='''import os,socket,ssl,subprocess,sys,tempfile,threading,time
from pathlib import Path
assert os.stat('/proc/self/ns/net').st_ino!=int(sys.argv[2])
subprocess.run(['ip','link','set','lo','up'],check=True,capture_output=True)
sys.path.insert(0,sys.argv[1])
from guest_update_cases import AssetServer
with tempfile.TemporaryDirectory(prefix='pnm-asset-guard.') as directory:
    cert=Path(directory)/'fixture.crt'
    key=Path(directory)/'fixture.key'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
        '-subj','/CN=github.com','-addext','subjectAltName=DNS:github.com',
        '-keyout',str(key),'-out',str(cert)],check=True,capture_output=True,timeout=10)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(cert),str(key))
    client_context=ssl.create_default_context(cafile=str(cert))
    for kind in ('incomplete-connect','incomplete-tls','wrong-connect','wrong-path','positive'):
        server=AssetServer({'/expected':b'fixture'},context)
        worker=threading.Thread(target=server.serve_forever)
        worker.start()
        client=socket.create_connection(server.server_address,timeout=2)
        try:
            if kind=='incomplete-connect':
                client.sendall(b'CONNECT github.com:443 HTTP/1.1\\r\\nHost:')
            elif kind=='wrong-connect':
                client.sendall(b'CONNECT example.invalid:443 HTTP/1.1\\r\\n\\r\\n')
                try: client.recv(1024)
                except ConnectionResetError: pass
            else:
                client.sendall(b'CONNECT github.com:443 HTTP/1.1\\r\\n\\r\\n')
                assert b'200 Connection Established' in client.recv(1024)
                if kind in ('wrong-path','positive'):
                    client=client_context.wrap_socket(client,server_hostname='github.com')
                    path=b'/expected' if kind=='positive' else b'/forbidden'
                    client.sendall(b'GET '+path+b' HTTP/1.1\\r\\nHost: github.com\\r\\n\\r\\n')
                    response=b''
                    while True:
                        chunk=client.recv(1024)
                        if not chunk: break
                        response+=chunk
                        assert len(response)<2048
                    if kind=='positive': assert response.endswith(b'fixture') and b'Content-Length: 7' in response
                    else: assert response==b''
            deadline=time.monotonic()+2
            while not server.request_threads and time.monotonic()<deadline: time.sleep(0.01)
            assert server.request_threads
        finally:
            start=time.monotonic()
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)
            client.close()
            assert time.monotonic()-start<4
        assert not worker.is_alive() and not any(t.is_alive() for t in server.request_threads)
        assert not server.connections
        if kind=='positive': assert server.requests==['/expected'] and not server.errors
        else: assert not server.requests and server.errors
'''
        result=subprocess.run(['unshare','--net',sys.executable,'-B','-c',script,
                               str(DRIVER.parent),str(os.stat('/proc/self/ns/net').st_ino)],
                              capture_output=True,timeout=25)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))

    @unittest.skipUnless(sys.platform=='linux','Linux process groups')
    def test_cli_timeout_retires_pipe_holding_descendant(self):
        tree=ast.parse(DRIVER.with_name('guest_mainflow_cases.py').read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='call')
        with tempfile.TemporaryDirectory(prefix='pnm-guest-command.') as directory:
            marker=Path(directory)/'child.pid'
            # Parent exits successfully while its child retains both PIPEs.
            # Shorten only the waits; exercise the real command-group cleanup.
            fixture="import pathlib,subprocess,sys; child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); pathlib.Path(sys.argv[1]).write_text(str(child.pid))"
            owned=[]
            class FixturePopen(subprocess.Popen):
                def __init__(self, _command, **kwargs):
                    super().__init__([sys.executable,'-c',fixture,str(marker)],**kwargs)
                    owned.append(self.pid)
                    # Start the short PIPE timeout only after the fixture has
                    # actually spawned its descendant; process startup can take
                    # more than 0.5s under concurrent integration-test load.
                    deadline=time.monotonic()+10
                    while time.monotonic()<deadline:
                        if marker.exists() and marker.read_text().isdigit():
                            break
                        time.sleep(0.02)
                    else:
                        raise RuntimeError('fixture descendant did not become ready')
                def communicate(self, input=None, timeout=None):
                    return super().communicate(input,timeout=min(timeout or 1,0.5))
            class Commands:
                Popen=FixturePopen
                DEVNULL=subprocess.DEVNULL
                PIPE=subprocess.PIPE
                TimeoutExpired=subprocess.TimeoutExpired
                CompletedProcess=subprocess.CompletedProcess
                @staticmethod
                def run(*_args, **_kwargs):
                    # No host journal access. Diagnostic failure must preserve
                    # the original timeout and still retire the command group.
                    raise OSError('fixture journal unavailable')
            def check(condition,label):
                if not condition:
                    raise RuntimeError(label)
            namespace={'os':os,'json':json,'signal':signal,'subprocess':Commands,
                       'sanitized_failure':lambda _: {},
                       'logs':Path(directory),'env':dict(os.environ),'check':check,
                       'scenario':'lifecycle','cli':['bash','/opt/pnm/bin/pnm']}
            exec(compile(ast.Module(body=[function],type_ignores=[]),str(DRIVER),'exec'),namespace)
            try:
                with self.assertRaisesRegex(RuntimeError,'command timed out'):
                    namespace['call']('fixture',[])
                pid=marker.read_text()
                deadline=time.monotonic()+2
                while time.monotonic()<deadline:
                    status=Path('/proc')/pid/'status'
                    if not status.exists() or 'State:\tZ' in status.read_text():
                        break
                    time.sleep(0.05)
                else:
                    self.fail('owned pipe-holding descendant still runs')
                self.assertEqual(json.loads((Path(directory)/'operation.json').read_text())['state'],'timeout')
            finally:
                for pid in owned:
                    try:
                        os.killpg(pid,signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux FIFO guard')
    def test_fifo_clone_leaf_is_rejected_without_waiting(self):
        with tempfile.TemporaryDirectory(prefix='pnm-guest-fifo.') as directory:
            fifo=Path(directory)/'leaf'
            os.mkfifo(fifo,0o600)
            script='''import ast,os,stat,sys
from pathlib import Path
tree=ast.parse(Path(sys.argv[1]).read_text())
function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='write_clone_file')
namespace={'os':os,'stat':stat,'Path':Path}
exec(compile(ast.Module(body=[function],type_ignores=[]),sys.argv[1],'exec'),namespace)
try:
    namespace['write_clone_file'](Path(sys.argv[2]),'fixture')
except OSError:
    raise SystemExit(0)
raise SystemExit(1)
'''
            result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER),str(fifo)],
                                  capture_output=True,timeout=3)
            self.assertEqual(result.returncode,0)
            self.assertTrue(stat.S_ISFIFO(fifo.stat().st_mode))

    def test_missing_opt_in_refuses_before_preparation(self):
        env={k:v for k,v in os.environ.items() if k!='PNM_RUN_GUEST_TESTS'}
        result=subprocess.run([sys.executable,'-B',str(DRIVER)],env=env,
                              capture_output=True,timeout=10)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b'Explicit PNM_RUN_GUEST_TESTS=1',result.stderr)

    def test_optimized_assertions_refuse_before_preparation(self):
        result=subprocess.run([sys.executable,'-O','-B',str(DRIVER)],
                              env={**os.environ,'PNM_RUN_GUEST_TESTS':'1'},
                              capture_output=True,timeout=10)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b'enabled assertions required',result.stderr)

    @unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0,'Linux root writer policy')
    def test_clone_writer_rejects_links_without_modifying_targets(self):
        # Load just the real write helper; never import/execute the boot driver.
        tree=ast.parse(DRIVER.read_text())
        function=next(node for node in tree.body
                      if isinstance(node,ast.FunctionDef) and node.name=='write_clone_file')
        namespace={'os':os,'stat':stat,'Path':Path}
        exec(compile(ast.Module(body=[function],type_ignores=[]),str(DRIVER),'exec'),namespace)
        write=namespace['write_clone_file']
        with tempfile.TemporaryDirectory(prefix='pnm-guest-write.') as directory:
            root=Path(directory)
            target=root/'target'
            target.write_text('preserve')
            target.chmod(0o644)
            symlink=root/'symlink'
            symlink.symlink_to(target)
            with self.assertRaises(OSError):
                write(symlink,'replace')
            self.assertEqual(target.read_text(),'preserve')
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o644)
            hardlink=root/'hardlink'
            os.link(target,hardlink)
            with self.assertRaises(AssertionError):
                write(hardlink,'replace')
            self.assertEqual(target.read_text(),'preserve')
            hardlink.unlink()
            write(target,'replace')
            self.assertEqual(target.read_text(),'replace')
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o600)


if __name__=='__main__':
    unittest.main()
