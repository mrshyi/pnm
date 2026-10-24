"""Observe a real deployment publisher EROFS in a private child namespace."""
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


def run_commit(arguments, wrapper, *, isolated=False):
    require_guest()
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
        return subprocess.run(['/usr/bin/unshare','--mount','--propagation','private',
            '/usr/bin/python3','-B','/opt/guest_commit_fault.py',wrapper,*arguments],timeout=130).returncode
    require(config['transaction']==str(transaction) and config['parent_identity']==identity,
            'publisher transaction changed before child execution')
    with (private/'attempted').open('x') as stream:
        stream.write('one unchanged real publisher\n')
    observer=private/'observer'
    (observer/'config.json').write_text(json.dumps({'transaction':str(transaction)}))
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
def readonly_deployment_commit(logs, env):
    require_guest()
    private=logs/('readonly-commit-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    (private/'config.json').write_text(json.dumps({'mount_namespace':namespace}))
    observer=private/'observer'
    observer.mkdir(mode=0o700)
    (observer/'sitecustomize.py').write_text(TRACE_SOURCE)
    launcher=private/'python3'
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_commit_fault import run_commit\nraise SystemExit(run_commit(sys.argv[1:],__file__))\n')
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
            require(observation=={'private_namespace':True,'probe_errno':errno.EROFS,'mount_removed':True,
                'actual_errno':errno.EROFS,'pending_creation_refused':True,'publisher_rc':73,
                'commit_intent_recorded':True,'both_applied_recorded':True},
                'publisher refusal receipt is incomplete')


if __name__=='__main__':
    raise SystemExit(run_commit(sys.argv[2:],sys.argv[1],isolated=True))
