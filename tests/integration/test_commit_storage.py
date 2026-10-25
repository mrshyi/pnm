#!/usr/bin/env python3
"""Opt-in publisher ENOSPC checks in a bounded, privately mounted tmpfs."""
import errno
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


REPO=Path(__file__).resolve().parents[2]
OPT_IN='PNM_RUN_STORAGE_TESTS'


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def mount_rows() -> list[list[str]]:
    return [line.split() for line in Path('/proc/self/mountinfo').read_text().splitlines()]


# Trace only the original stdin publisher. The kernel refuses the original
# mkstemp/write; no file API, publisher text or product return code is replaced.
OBSERVER='''import atexit,errno,json,os,stat,sys,tempfile
from pathlib import Path
private=Path(__file__).parent
config=json.loads((private/'observer.json').read_text())
transaction=Path(config['transaction'])
pending=transaction/'commit-uncertain.env'
phase=config['phase']
armed=False
proof={}
def save():
    if proof:
        (private/'observed.json').write_text(json.dumps(proof))
atexit.register(save)
def exhaust():
    global armed
    if os.stat('/proc/self/ns/mnt').st_ino!=config['namespace']:
        raise RuntimeError('storage observer namespace differs')
    rows=[r.split() for r in Path('/proc/self/mountinfo').read_text().splitlines()]
    row=next(r for r in rows if r[4]==config['mount'])
    if row[0]!=config['mount_id'] or row[row.index('-')+1]!='tmpfs':
        raise RuntimeError('storage observer mount differs')
    if phase=='pending-create':
        if pending.exists():
            raise RuntimeError('pending creation observer was late')
    else:
        expected=b'' if phase=='pending-write' else b'SCHEMA_VERSION=1\\nORIGINAL_RC=70\\n'
        if pending.read_bytes()!=expected:
            raise RuntimeError('pending contents differ before exhaustion')
    fill=Path(config['mount'])/'fill'
    consumed=0
    try:
        if phase in ('create','pending-create'):
            for index in range(128):
                descriptor=os.open(fill/str(index),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                os.close(descriptor)
                consumed+=1
        else:
            with (fill/'blocks').open('xb',buffering=0) as stream:
                for index in range(128):
                    stream.write(bytes(4096))
                    consumed+=1
    except OSError as error:
        if error.errno!=errno.ENOSPC or consumed==0:
            raise
        proof.update({'fill_errno':error.errno,'bounded_consumed':consumed})
    else:
        raise RuntimeError('bounded tmpfs did not fill')
    armed=True
def exhaust_write(descriptor,path):
    info=os.fstat(descriptor)
    candidate=path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_size!=0 or info.st_nlink!=1
            or info.st_uid!=0 or stat.S_IMODE(info.st_mode)!=0o600
            or (info.st_dev,info.st_ino)!=(candidate.st_dev,candidate.st_ino)):
        raise RuntimeError('write target FD identity differs')
    exhaust()
def observe(frame,event,arg):
    if (not armed and phase=='create' and event=='call'
            and frame.f_code is tempfile.mkstemp.__code__
            and frame.f_back is not None and frame.f_back.f_code.co_filename=='<stdin>'
            and frame.f_locals.get('dir')==str(transaction)
            and frame.f_locals.get('prefix')=='.commit-'):
        exhaust()
    if frame.f_code.co_filename!='<stdin>':
        return None
    temporary=frame.f_globals.get('temporary')
    if (not armed and event=='line' and frame.f_code.co_name=='<module>'
            and frame.f_globals.get('pending')==str(pending)):
        if phase=='pending-create' and not pending.exists():
            exhaust()
        elif (phase=='pending-write' and pending.is_file()
              and not getattr(frame.f_globals.get('stream'),'closed',True)):
            exhaust_write(frame.f_globals['descriptor'],pending)
    if (not armed and phase=='write' and event=='line'
            and frame.f_code.co_name=='<module>' and isinstance(temporary,str)
            and Path(temporary).parent==transaction
            and getattr(frame.f_globals.get('stream'),'closed',False)):
        exhaust_write(frame.f_globals['descriptor'],Path(temporary))
    if armed and event=='exception':
        error=arg[1]
        if isinstance(error,OSError) and error.errno==errno.ENOSPC:
            if phase=='pending-create':
                if error.filename!=str(pending) or temporary is not None:
                    return observe
            elif phase=='pending-write':
                if temporary is not None or frame.f_globals.get('pending')!=str(pending):
                    return observe
            elif phase=='create':
                if (not isinstance(error.filename,str) or Path(error.filename).parent!=transaction
                        or not Path(error.filename).name.startswith('.commit-') or temporary is not None):
                    return observe
            elif not isinstance(temporary,str) or Path(temporary).parent!=transaction:
                return observe
            proof['publisher_errno']=error.errno
            sys.settrace(None)
    return observe
sys.settrace(observe)
'''


def run_case(phase: str, parent_namespace: int) -> dict:
    require(os.environ.get(OPT_IN)=='1','explicit bounded storage opt-in required')
    require(sys.platform=='linux' and os.geteuid()==0,'bounded storage requires Linux root')
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    observed_parent=os.stat('/proc/'+str(os.getppid())+'/ns/mnt').st_ino
    require(parent_namespace==observed_parent and namespace!=observed_parent,
            'bounded storage requires a private mount namespace')
    require(phase in ('create','write','pending-create','pending-write'),'unknown bounded storage phase')
    for row in mount_rows():
        require(not any(x.startswith(('shared:','master:')) for x in row[6:row.index('-')]),
                'bounded storage requires private propagation')
    os.umask(0o077)
    private=Path(tempfile.mkdtemp(prefix='pnm-commit-storage.',dir='/var/tmp'))
    private.chmod(0o700)
    mount=private/'fs'
    mount.mkdir(mode=0o700)
    mount_id=None
    report={'passed':False,'phase':phase,'evidence':str(private)}
    try:
        subprocess.run(['mount','-t','tmpfs','-o',
                        'size=64k,nr_inodes=64,mode=0700,nodev,nosuid,noexec',
                        'pnm-bounded-test',str(mount)],check=True,capture_output=True,timeout=10)
        rows=[r for r in mount_rows() if r[4]==str(mount)]
        require(len(rows)==1 and rows[0][rows[0].index('-')+1]=='tmpfs','owned tmpfs not confirmed')
        mount_id=rows[0][0]
        space=os.statvfs(mount)
        require(space.f_blocks*space.f_frsize<=65536 and space.f_files<=64,'tmpfs bounds differ')
        require({'nodev','nosuid','noexec'}<=set(rows[0][5].split(',')),'tmpfs protection differs')
        transaction=mount/'transaction'
        transaction.mkdir(mode=0o700)
        (mount/'fill').mkdir(mode=0o700)
        for name,data in {'metadata.env':b'SCHEMA_VERSION=2\n','changes.tsv':b'',
                          'directories.tsv':b'','deployment.env':b'APPLY_ID=none\n'}.items():
            path=transaction/name
            path.write_bytes(data)
            path.chmod(0o600)
        baseline={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in transaction.iterdir()}
        (private/'observer.json').write_text(json.dumps({'transaction':str(transaction),
            'mount':str(mount),'mount_id':mount_id,'namespace':namespace,'phase':phase}))
        (private/'sitecustomize.py').write_text(OBSERVER)
        command='source "$1/lib/deployment-state.sh"; pnm_tx_deployment_marker publish "$2" tx-storage deploy-storage 0'
        result=subprocess.run(['bash','-c',command,'pnm-storage-test',str(REPO),str(transaction)],
            env={**os.environ,'PYTHONPATH':str(private),'PYTHONDONTWRITEBYTECODE':'1'},
            capture_output=True,timeout=20)
        (private/'publisher.stderr').write_bytes(result.stderr)
        proof=json.loads((private/'observed.json').read_text())
        require(result.returncode==73 and not result.stdout and proof.get('publisher_errno')==errno.ENOSPC
                and proof.get('fill_errno')==errno.ENOSPC,'actual publisher ENOSPC73 not observed')
        require(not (transaction/'commit.env').exists() and not list(transaction.glob('.commit-*')),
                'storage refusal left a commit marker or candidate')
        pending=transaction/'commit-uncertain.env'
        pending_state='absent' if phase=='pending-create' else ('empty' if phase=='pending-write' else 'complete')
        if pending_state=='absent':
            require(not pending.exists() and not pending.is_symlink(),'failed pending creation left a record')
        else:
            expected=b'' if pending_state=='empty' else b'SCHEMA_VERSION=1\nORIGINAL_RC=70\n'
            require(pending.read_bytes()==expected,'pending state differs after refusal')
        require(all(hashlib.sha256((transaction/name).read_bytes()).hexdigest()==digest
                    for name,digest in baseline.items()),'storage refusal changed original records')
        report.update({'passed':True,'publisher_rc':73,'actual_errno':errno.ENOSPC,
                       'pending_preserved':pending_state=='complete','pending_state':pending_state,
                       'original_records_preserved':True,
                       'marker_absent':True,'candidate_absent':True,'bounded_consumed':proof['bounded_consumed']})
    except Exception as error:
        report.update({'passed':False,'error_class':type(error).__name__})
        if isinstance(error,RuntimeError):
            report['reason']=str(error)
    finally:
        if mount_id is not None:
            rows=[r for r in mount_rows() if r[4]==str(mount)]
            require(len(rows)==1 and rows[0][0]==mount_id,'owned tmpfs identity changed before retirement')
            subprocess.run(['umount','--',str(mount)],check=True,capture_output=True,timeout=10)
        report['mount_removed']=not any(r[4]==str(mount) for r in mount_rows())
        report['passed']=report['passed'] and report['mount_removed']
        (private/'result.json').write_text(json.dumps(report))
    return report


@unittest.skipUnless(sys.platform=='linux' and os.geteuid()==0 and os.environ.get(OPT_IN)=='1',
                     'explicit Linux root bounded-storage opt-in required')
class StorageTests(unittest.TestCase):
    def check_phase(self, phase: str) -> None:
        namespace=os.stat('/proc/self/ns/mnt').st_ino
        mounts=Path('/proc/self/mountinfo').read_bytes()
        databases=[Path('/etc')/name for name in ('passwd','group','shadow','gshadow')]
        databases.append(Path('/var/lib/dpkg/status'))
        baseline={p:hashlib.sha256(p.read_bytes()).digest() for p in databases}
        result=subprocess.run(['unshare','--mount','--propagation','private',sys.executable,'-B',
            str(Path(__file__).resolve()),'--worker',phase,str(namespace)],capture_output=True,timeout=45)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        report=json.loads(result.stdout)
        self.assertTrue(report['passed'],report)
        self.assertEqual(os.stat('/proc/self/ns/mnt').st_ino,namespace)
        self.assertEqual(Path('/proc/self/mountinfo').read_bytes(),mounts)
        self.assertTrue(all(hashlib.sha256(p.read_bytes()).digest()==digest for p,digest in baseline.items()))
        print(json.dumps(report),flush=True)

    def test_candidate_creation_inode_enospc(self) -> None:
        self.check_phase('create')

    def test_candidate_write_block_enospc(self) -> None:
        self.check_phase('write')

    def test_pending_creation_inode_enospc(self) -> None:
        self.check_phase('pending-create')

    def test_pending_write_block_enospc(self) -> None:
        self.check_phase('pending-write')


if __name__=='__main__':
    if os.environ.get(OPT_IN)=='1' and (sys.platform!='linux' or os.geteuid()!=0 or sys.flags.optimize):
        raise SystemExit('bounded storage requires Linux root and enabled assertions')
    if sys.argv[1:2]==['--worker']:
        try:
            outcome=run_case(sys.argv[2],int(sys.argv[3]))
        except (RuntimeError,ValueError,IndexError) as error:
            print(type(error).__name__,file=sys.stderr)
            raise SystemExit(77) from None
        print(json.dumps(outcome),flush=True)
        raise SystemExit(0 if outcome['passed'] else 1)
    unittest.main()
