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
                result=subprocess.run([sys.executable,'-B',str(DRIVER),
                    '--baseline',str(root/'missing-baseline'),'--nspawn',str(root/'missing-nspawn'),
                    '--asset-cache',str(root/'missing-assets'),'--work-dir',str(candidate)],
                    env={**os.environ,'PNM_RUN_GUEST_TESTS':'1'},capture_output=True,timeout=10)
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
def forbidden(*args,**kwargs):
    raise AssertionError('fixture acted before its namespace guard')
fixture.socket.socket=forbidden
fixture.subprocess.run=forbidden
for name in ('open','mkdir','unlink','rmdir'):
    setattr(fixture.os,name,forbidden)
for mode in ('reject-once','reject-twice','delay'):
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
    lambda: interruption.signal_owned_command_on_start({},15).__enter__(),
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
for delay in (0,16,'3',True,3.0,None):
    try:
        with fixture.start_fault('xray',mode='delay',delay_seconds=delay):
            raise AssertionError('invalid delay entered fault fixture')
    except RuntimeError as error:
        assert str(error)=='bounded integer startup delay required'
'''
        result=subprocess.run([sys.executable,'-B','-c',script,str(DRIVER.parent)],
                              capture_output=True,timeout=10)
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
