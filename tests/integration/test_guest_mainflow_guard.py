#!/usr/bin/env python3
"""Offline regression for host-side clone file writes and explicit opt-in."""
import ast
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
                def communicate(self, input=None, timeout=None):
                    return super().communicate(input,timeout=min(timeout or 1,0.5))
            class Commands:
                Popen=FixturePopen
                DEVNULL=subprocess.DEVNULL
                PIPE=subprocess.PIPE
                TimeoutExpired=subprocess.TimeoutExpired
                CompletedProcess=subprocess.CompletedProcess
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
