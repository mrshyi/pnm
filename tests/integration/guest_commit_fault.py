"""Observe actual deployment publisher refusals in a private child namespace."""
from contextlib import contextmanager
import errno
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

from guest_start_fault import require, require_guest
from guest_io_fault import mounts, parent_identity, readonly_bind


# Observe rather than replace file APIs: the product keeps its generic diagnostic.
# Do not retain exception text, locals or configuration values in this receipt.
TRACE_SOURCE='''import errno,json,sys
from pathlib import Path
private=Path(__file__).parent
expected=json.loads((private/'config.json').read_text())['transaction']+'/commit-uncertain.env'
def observe(frame,event,arg):
    if frame.f_code.co_filename!='<stdin>':
        return None
    if event=='exception':
        error=arg[1]
        if isinstance(error,OSError) and error.errno==errno.EROFS and error.filename==expected:
            try:
                (private/'observed-exception.json').write_text(json.dumps({
                    'actual_errno':error.errno,'pending_creation_refused':True}))
            except OSError:
                pass
            sys.settrace(None)
            return None
    return observe
sys.settrace(observe)
'''


RENAME_TRACE_SOURCE='''import atexit,errno,json,os,resource,signal,stat,sys,tempfile,time
from pathlib import Path
from guest_commit_signal import require_publisher_guest
from guest_io_fault import readonly_bind
private=Path(__file__).parent
config=json.loads((private/'config.json').read_text())
transaction=Path(config['transaction'])
context=None
observation=None
actual=None
phase=config.get('phase','rename')
armed=False
original_limit=None
candidate_identity=None
space_fault=None
inode_fault=None
finished=False
def finish():
    global finished
    if finished:
        return
    if space_fault is not None:
        space_fault.release()
        if observation is not None:
            observation['space_recovered']=True
    if inode_fault is not None:
        inode_fault.release()
        if observation is not None:
            observation['inodes_recovered']=True
    if original_limit is not None:
        resource.setrlimit(resource.RLIMIT_FSIZE,original_limit)
        if resource.getrlimit(resource.RLIMIT_FSIZE)!=original_limit:
            raise RuntimeError('publisher file-size limit did not restore')
        observation['file_size_limit_restored']=True
    if context is not None:
        context.__exit__(None,None,None)
    if observation is not None and actual is not None:
        observation.update(actual)
        (private/'observed-rename.json').write_text(json.dumps(observation))
    finished=True
atexit.register(finish)
def arm():
    global context,observation,armed
    require_publisher_guest()
    if not (transaction/'commit-uncertain.env').is_file() or (transaction/'commit.env').exists():
        raise RuntimeError('candidate observer has no pending uncommitted publisher')
    context=readonly_bind(transaction,private,config['identity'],config['parent_namespace'],
                          guard=require_publisher_guest)
    observation=context.__enter__()
    armed=True
def observe(frame,event,arg):
    global context,observation,actual,armed,original_limit,candidate_identity,space_fault,inode_fault
    if (phase=='inode-pending' and not armed and event=='line'
            and frame.f_code.co_filename=='<stdin>' and frame.f_code.co_name=='<module>'
            and frame.f_globals.get('directory')==str(transaction)
            and frame.f_globals.get('pending')==str(transaction/'commit-uncertain.env')
            and not (transaction/'commit-uncertain.env').exists()
            and not (transaction/'commit.env').exists() and time.time()<=int(sys.argv[5])):
        from guest_commit_space import InodeFault
        inode_fault=InodeFault(transaction,private,config['parent_namespace'])
        observation=inode_fault.fill()
        armed=True
    if (phase=='inode-pending' and inode_fault is not None and event=='exception'
            and frame.f_code.co_filename=='<stdin>' and frame.f_code.co_name=='<module>'):
        error=arg[1]
        if (isinstance(error,OSError) and error.errno==errno.ENOSPC
                and error.filename==str(transaction/'commit-uncertain.env')
                and observation.get('inode_exhausted') is True):
            inode_fault.release()
            inode_fault=None
            actual={'actual_errno':error.errno,'pending_creation_inode_refused':True,
                    'pending_retained':(transaction/'commit-uncertain.env').exists(),
                    'inode_exhausted':True,'inodes_recovered':True}
            sys.settrace(None)
            return None
    if (phase=='create' and not armed and event=='call'
            and frame.f_code is tempfile.mkstemp.__code__
            and frame.f_back is not None and frame.f_back.f_code.co_filename=='<stdin>'
            and frame.f_locals.get('dir')==str(transaction)
            and frame.f_locals.get('prefix')=='.commit-' and time.time()<=int(sys.argv[5])):
        arm()
    if (phase=='inode' and not armed and event=='call'
            and frame.f_code is tempfile.mkstemp.__code__
            and frame.f_back is not None and frame.f_back.f_code.co_filename=='<stdin>'
            and frame.f_locals.get('dir')==str(transaction)
            and frame.f_locals.get('prefix')=='.commit-' and time.time()<=int(sys.argv[5])):
        from guest_commit_space import InodeFault
        inode_fault=InodeFault(transaction,private,config['parent_namespace'])
        observation=inode_fault.fill()
        armed=True
    if phase=='inode' and frame.f_code is tempfile._mkstemp_inner.__code__:
        if event=='exception':
            error=arg[1]
            candidate=frame.f_locals.get('file')
            if (isinstance(error,OSError) and error.errno==errno.ENOSPC
                    and frame.f_locals.get('dir')==str(transaction)
                    and frame.f_locals.get('pre')=='.commit-'
                    and isinstance(candidate,str) and Path(candidate).parent==transaction
                    and Path(candidate).name.startswith('.commit-')
                    and inode_fault is not None
                    and observation.get('inode_exhausted') is True):
                inode_fault.release()
                actual={'actual_errno':error.errno,'candidate_create_inode_refused':True,
                        'pending_retained':(transaction/'commit-uncertain.env').is_file(),
                        'inode_exhausted':True,'inodes_recovered':True}
                inode_fault=None
                sys.settrace(None)
                return None
        return observe
    if frame.f_code.co_filename!='<stdin>':
        return None
    temporary=frame.f_globals.get('temporary')
    stream=frame.f_globals.get('stream')
    if (event=='line' and frame.f_code.co_name=='<module>' and not armed
            and frame.f_globals.get('directory')==str(transaction)
            and isinstance(temporary,str) and Path(temporary).parent==transaction
            and Path(temporary).is_file() and getattr(stream,'closed',False)
            and time.time()<=int(sys.argv[5])):
        if phase=='rename' and Path(temporary).stat().st_size>0:
            arm()
        elif phase in ('write','space') and Path(temporary).stat().st_size==0:
            require_publisher_guest()
            descriptor=frame.f_globals.get('descriptor')
            info=os.fstat(descriptor)
            candidate=Path(temporary).lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or info.st_nlink!=1
                    or stat.S_IMODE(info.st_mode)!=0o600
                    or (info.st_dev,info.st_ino)!=(candidate.st_dev,candidate.st_ino)
                    or signal.getsignal(signal.SIGXFSZ)!=signal.SIG_IGN):
                raise RuntimeError('candidate FD or Python file-size signal policy differs')
            candidate_identity=(info.st_dev,info.st_ino)
            if phase=='space':
                from guest_commit_space import SpaceFault
                space_fault=SpaceFault(transaction,private,config['parent_namespace'])
                observation=space_fault.fill()
            else:
                limit=resource.getrlimit(resource.RLIMIT_FSIZE)
                if limit[0]==0:
                    raise RuntimeError('publisher already has a zero file-size limit')
                original_limit=limit
                observation={'private_namespace':True}
                resource.setrlimit(resource.RLIMIT_FSIZE,(0,original_limit[1]))
            armed=True
    if event=='exception' and armed:
        error=arg[1]
        matched=False
        if (phase=='rename' and isinstance(error,OSError) and error.errno==errno.EROFS
                and error.filename==temporary and error.filename2==str(transaction/'commit.env')):
            actual={'actual_errno':error.errno,'rename_refused':True,
                    'pending_retained':(transaction/'commit-uncertain.env').is_file()}
            matched=True
        elif (phase=='create' and isinstance(error,OSError) and error.errno==errno.EROFS
              and isinstance(error.filename,str) and Path(error.filename).parent==transaction
              and Path(error.filename).name.startswith('.commit-') and temporary is None):
            actual={'actual_errno':error.errno,'candidate_create_refused':True,
                    'pending_retained':(transaction/'commit-uncertain.env').is_file()}
            matched=True
        elif (phase in ('write','space') and isinstance(error,OSError)
              and error.errno==(errno.ENOSPC if phase=='space' else errno.EFBIG)
              and isinstance(temporary,str) and Path(temporary).parent==transaction):
            candidate=Path(temporary).lstat()
            if (candidate.st_dev,candidate.st_ino)==candidate_identity:
                actual={'actual_errno':error.errno,'candidate_'+phase+'_refused':True,
                        'pending_retained':(transaction/'commit-uncertain.env').is_file()}
                matched=True
        if matched:
            sys.settrace(None)
    return observe
sys.settrace(observe)
'''


def commit_guard(rename, *, space=False):
    if space:
        from guest_vm_boot import require_approved_vm
        return require_approved_vm
    if rename:
        # Resolve lazily: guest_commit_signal reuses transaction_for below.
        from guest_commit_signal import require_publisher_guest
        return require_publisher_guest
    return require_guest


def transaction_for(arguments):
    require(6<=len(arguments)<=64 and arguments[:2]==['-','publish'],
            'unexpected deployment publisher arguments')
    transaction=Path(arguments[2])
    require(transaction.parent==Path('/var/lib/pnm/transactions')
            and re.fullmatch(r'tx-[0-9a-f]{32}',transaction.name)
            and arguments[3]==transaction.name,'unexpected publisher transaction path')
    identity=parent_identity(transaction)
    metadata=transaction/'metadata.env'
    info=metadata.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o600,
            'unsafe publisher transaction metadata')
    fields=dict(line.split('=',1) for line in metadata.read_text().splitlines())
    require(fields.get('SCHEMA_VERSION')=='2' and fields.get('TRANSACTION_ID')==transaction.name
            and fields.get('OPERATION')=='deployment' and fields.get('DEPLOYMENT_ID')==arguments[4],
            'publisher transaction identity mismatch')
    rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
    require(rows and rows[-1][1]=='COMMIT_INTENT' and sum(row[1]=='COMMIT_INTENT' for row in rows)==1,
            'publisher did not follow unique commit intent')
    require(all(any(row[1:] == ['WRITE','label=applied_'+core] for row in rows)
                for core in ('xray','hysteria2')),'publisher has no dual applied publication')
    require(all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                for name in ('commit.env','commit-uncertain.env')),'publisher already has a marker')
    return transaction,identity


def run_commit(arguments, wrapper, *, isolated=False, rename=False, candidate=None):
    late=rename or candidate is not None
    guard=commit_guard(late,space=candidate in ('space','inode','inode-pending'))
    guard()
    require(type(rename) is bool and candidate in (None,'create','write','space','inode','inode-pending') and not (rename and candidate),
            'unknown or conflicting marker fault variants')
    private=Path(wrapper).parent
    info=private.lstat()
    require(private.resolve()==private and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
            'private commit launcher required')
    if arguments[:2]!=['-','publish'] or (private/'attempted').exists():
        return subprocess.run(['/usr/bin/python3',*arguments],timeout=90).returncode
    transaction,identity=transaction_for(arguments)
    config=json.loads((private/'config.json').read_text())
    if not isolated:
        require(os.stat('/proc/self/ns/mnt').st_ino==config['mount_namespace'],
                'publisher parent namespace changed')
        config.update({'transaction':str(transaction),'parent_identity':identity,
                       'original_mounts':[row for row in mounts() if row[4]==str(transaction)]})
        (private/'config.json').write_text(json.dumps(config))
        variant=['--candidate-'+candidate] if candidate else (['--rename'] if rename else [])
        timeout=280 if candidate in ('inode','inode-pending') else 130
        return subprocess.run(['/usr/bin/unshare','--mount','--propagation','private',
            '/usr/bin/python3','-B','/opt/guest_commit_fault.py',*variant,wrapper,*arguments],timeout=timeout).returncode
    require(config['transaction']==str(transaction) and config['parent_identity']==identity,
            'publisher transaction changed before child execution')
    require(os.stat('/proc/self/ns/mnt').st_ino!=config['mount_namespace'],
            'publisher did not enter its private mount namespace')
    with (private/'attempted').open('x') as stream:
        stream.write('one unchanged real publisher\n')
    observer=private/'observer'
    (observer/'config.json').write_text(json.dumps({'transaction':str(transaction),
        'identity':identity,'parent_namespace':config['mount_namespace'],
        'phase':candidate or ('rename' if rename else 'pending')}))
    if late:
        # The fault is confined to the publisher. Its atexit callback retires
        # the owned bind or file-size limit before the parent CLI compensates.
        result=subprocess.run(['/usr/bin/python3',*arguments],
            env={**os.environ,'PYTHONPATH':str(observer)},capture_output=True,
            timeout=240 if candidate in ('inode','inode-pending') else 90)
        observed=json.loads((observer/'observed-rename.json').read_text())
        event=('pending_creation_inode_refused' if candidate=='inode-pending'
               else 'candidate_create_inode_refused' if candidate=='inode'
               else 'candidate_'+candidate+'_refused' if candidate else 'rename_refused')
        expected_errno=errno.ENOSPC if candidate in ('space','inode','inode-pending') else (errno.EFBIG if candidate=='write' else errno.EROFS)
        retired=(observed.get('space_recovered') if candidate=='space' else
                 observed.get('inodes_recovered') if candidate in ('inode','inode-pending') else
                 observed.get('file_size_limit_restored') if candidate=='write' else observed.get('mount_removed'))
        require(result.returncode==73 and not result.stdout
                and observed.get('actual_errno')==expected_errno and observed.get(event) is True
                and observed.get('pending_retained') is (candidate!='inode-pending') and retired is True
                and not (transaction/'commit.env').exists(),
                'actual marker refusal or fault retirement was not observed')
        observed.update({'publisher_rc':result.returncode,'commit_intent_recorded':True,
                         'both_applied_recorded':True})
        (private/'result.json').write_text(json.dumps(observed))
        sys.stderr.buffer.write(result.stderr)
        return result.returncode
    with readonly_bind(transaction,private,identity,config['mount_namespace']) as observed:
        child_env={**os.environ,'PYTHONPATH':str(observer)}
        result=subprocess.run(['/usr/bin/python3',*arguments],env=child_env,
                              capture_output=True,timeout=90)
        trace=json.loads((observer/'observed-exception.json').read_text())
        require(trace=={'actual_errno':errno.EROFS,'pending_creation_refused':True},
                'publisher has no observed real pending-file EROFS')
        require(result.returncode==73 and not result.stdout
                and b'Deployment commit record could not be persisted or verified.' in result.stderr,
                'publisher failure has a different cause or result')
        require(all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                    for name in ('commit.env','commit-uncertain.env')),'failed publisher left a marker')
        observed.update(trace)
        observed.update({'publisher_rc':result.returncode,'commit_intent_recorded':True,
                         'both_applied_recorded':True})
    (private/'result.json').write_text(json.dumps(observed))
    sys.stderr.buffer.write(result.stderr)
    return result.returncode


@contextmanager
def readonly_deployment_commit(logs, env, *, rename=False, candidate=None):
    late=rename or candidate is not None
    commit_guard(late,space=candidate in ('space','inode','inode-pending'))()
    require(type(rename) is bool and candidate in (None,'create','write','space','inode','inode-pending') and not (rename and candidate),
            'unknown or conflicting marker fault variants')
    parent_limit=None
    if candidate=='write':
        import resource
        parent_limit=resource.getrlimit(resource.RLIMIT_FSIZE)
    private=logs/('readonly-commit-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    (private/'config.json').write_text(json.dumps({'mount_namespace':namespace}))
    observer=private/'observer'
    observer.mkdir(mode=0o700)
    trace=RENAME_TRACE_SOURCE if late else TRACE_SOURCE
    if late:
        trace='import sys\nsys.path.insert(0,\'/opt\')\n'+trace
    (observer/'sitecustomize.py').write_text(trace)
    launcher=private/'python3'
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_commit_fault import run_commit\nraise SystemExit(run_commit(sys.argv[1:],__file__,rename='
        +repr(rename)+',candidate='+repr(candidate)+'))\n')
    launcher.chmod(0o700)
    original=env['PATH']
    observation={}
    completed=False
    try:
        env['PATH']=str(private)+':'+original
        yield observation
        completed=True
    finally:
        env['PATH']=original
        require(os.stat('/proc/self/ns/mnt').st_ino==namespace,'commit fault changed parent namespace')
        config=json.loads((private/'config.json').read_text())
        if 'transaction' in config:
            require([row for row in mounts() if row[4]==config['transaction']]==config['original_mounts'],
                    'commit fault changed parent mounts')
        if completed:
            receipt=private/'result.json'
            require(receipt.is_file() and not receipt.is_symlink(),
                    'publisher refusal receipt missing; inspect protected CLI output')
            observation.update(json.loads(receipt.read_text()))
            expected={'private_namespace':True,'actual_errno':errno.ENOSPC if candidate in ('space','inode','inode-pending') else (errno.EFBIG if candidate=='write' else errno.EROFS),'publisher_rc':73,
                'commit_intent_recorded':True,'both_applied_recorded':True}
            if candidate=='space':
                expected.update({'candidate_space_refused':True,'pending_retained':True,
                                 'fill_errno':errno.ENOSPC,'space_recovered':True})
            elif candidate in ('inode','inode-pending'):
                event='pending_creation_inode_refused' if candidate=='inode-pending' else 'candidate_create_inode_refused'
                expected.update({event:True,'pending_retained':candidate=='inode',
                                 'inode_exhausted':True,'inodes_recovered':True})
            elif candidate=='write':
                require(resource.getrlimit(resource.RLIMIT_FSIZE)==parent_limit,'publisher fault changed parent limits')
                observation['parent_file_size_limit_unchanged']=True
                expected.update({'candidate_write_refused':True,'pending_retained':True,
                                 'file_size_limit_restored':True,'parent_file_size_limit_unchanged':True})
            else:
                expected.update({'probe_errno':errno.EROFS,'mount_removed':True})
                expected.update({'candidate_create_refused':True,'pending_retained':True} if candidate=='create'
                                else ({'rename_refused':True,'pending_retained':True} if rename
                                      else {'pending_creation_refused':True}))
            require(observation==expected,
                'publisher refusal receipt is incomplete')


if __name__=='__main__':
    if sys.argv[1:2] in (['--candidate-create'],['--candidate-write'],['--candidate-space'],['--candidate-inode'],['--candidate-inode-pending']):
        raise SystemExit(run_commit(sys.argv[3:],sys.argv[2],isolated=True,
                                    candidate=sys.argv[1].removeprefix('--candidate-')))
    elif sys.argv[1:2]==['--rename']:
        raise SystemExit(run_commit(sys.argv[3:],sys.argv[2],isolated=True,rename=True))
    raise SystemExit(run_commit(sys.argv[2:],sys.argv[1],isolated=True))
