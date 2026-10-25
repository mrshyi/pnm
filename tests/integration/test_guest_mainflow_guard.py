#!/usr/bin/env python3
"""Offline regression for host-side clone file writes and explicit opt-in."""
import ast
import importlib.util
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

DRIVER=Path(__file__).with_name('test_guest_mainflow.py')


class GuestGuardTests(unittest.TestCase):
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
                       'logs':Path(directory),'env':dict(os.environ),'check':check}
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
