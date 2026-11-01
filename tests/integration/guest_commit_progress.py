"""Refuse the actual derived journal append after a durable deployment commit."""
from contextlib import contextmanager
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import uuid

from guest_commit_fault import transaction_for
from guest_commit_signal import require_publisher_guest
from guest_io_fault import mounts, parent_identity


# Observe the last successful fsync return after uncertainty removal. Product
# file APIs and publisher stdin remain unchanged. The caller Bash shares this
# private CLI mount namespace, so its real append encounters kernel EROFS.
TRACE_SOURCE='''import json,sys
from pathlib import Path
sys.path.insert(0,'/opt')
from guest_commit_progress import seal_progress
private=Path(__file__).parent
transaction=Path(json.loads((private/'config.json').read_text())['transaction'])
def observe(frame,event,arg):
    if (event=='return' and frame.f_code.co_filename=='<stdin>'
            and frame.f_code.co_name=='sync_directory'
            and frame.f_locals.get('path')==str(transaction)
            and frame.f_globals.get('temporary') is None
            and (transaction/'commit.env').is_file()
            and not (transaction/'commit-uncertain.env').exists()):
        sys.settrace(None)
        seal_progress(private,transaction)
    if frame.f_code.co_filename=='<stdin>' and frame.f_code.co_name=='sync_directory':
        return observe
    return None
sys.settrace(observe)
'''


def need(condition, label):
    if not condition:
        raise RuntimeError(label)


def private_directory(path):
    info=path.lstat()
    need(path.resolve()==path and stat.S_ISDIR(info.st_mode) and info.st_uid==0
         and stat.S_IMODE(info.st_mode)==0o700,'private committed-progress control required')
    return path


def seal_progress(private, transaction):
    require_publisher_guest()
    private_directory(private)
    config=json.loads((private/'config.json').read_text())
    need(str(transaction)==config['transaction'] and transaction.parent==Path('/var/lib/pnm/transactions')
         and re.fullmatch(r'tx-[0-9a-f]{32}',transaction.name),'unexpected committed-progress transaction')
    parent_identity(transaction)
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    need(namespace!=config['parent_namespace'],'committed-progress CLI did not isolate mounts')
    before=mounts()
    for row in before:
        need(not any(value.startswith(('shared:','master:')) for value in row[6:row.index('-')]),
             'committed-progress mount propagation is not private')
    marker=transaction/'commit.env'
    pending=transaction/'commit-uncertain.env'
    need(marker.is_file() and not marker.is_symlink() and not pending.exists() and not pending.is_symlink(),
         'publisher has not completed uncertainty cleanup')
    journal=transaction/'journal.tsv'
    info=journal.lstat()
    need(stat.S_ISREG(info.st_mode) and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o600
         and info.st_nlink==1 and not any(row[4]==str(journal) for row in before),
         'unprotected or already mounted progress journal')
    digest=hashlib.sha256(journal.read_bytes()).digest()
    subprocess.run(['/usr/bin/mount','--bind',str(journal),str(journal)],
                   check=True,capture_output=True,timeout=10)
    current=[row for row in mounts() if row[4]==str(journal)]
    need(len(current)==1 and current[0][0] not in {row[0] for row in before},
         'committed-progress mount identity was not established')
    mount_id=current[0][0]
    subprocess.run(['/usr/bin/mount','-o','remount,bind,ro',str(journal),str(journal)],
                   check=True,capture_output=True,timeout=10)
    current=[row for row in mounts() if row[4]==str(journal)]
    observed=journal.lstat()
    need(len(current)==1 and current[0][0]==mount_id and 'ro' in current[0][5].split(',')
         and (observed.st_dev,observed.st_ino)==(info.st_dev,info.st_ino),
         'committed-progress read-only bind identity differs')
    try:
        descriptor=os.open(journal,os.O_WRONLY|os.O_APPEND|os.O_NOFOLLOW)
    except OSError as error:
        need(error.errno==errno.EROFS,'committed-progress probe did not encounter kernel EROFS')
    else:
        os.close(descriptor)
        raise RuntimeError('committed-progress journal unexpectedly writable')
    need(hashlib.sha256(journal.read_bytes()).digest()==digest,'progress probe changed the journal')
    (private/'sealed.json').write_text(json.dumps({'private_cli_namespace':True,
        'after_final_directory_sync':True,'uncertainty_absent':True,
        'journal_probe_errno':errno.EROFS,'journal_unchanged':True}))
    # Keep only this owned namespace's bind until the caller Bash has attempted
    # its append. Kernel namespace teardown removes it when that CLI exits.


def run_publisher(arguments, wrapper):
    require_publisher_guest()
    private=private_directory(Path(wrapper).parent)
    if arguments[:2]!=['-','publish'] or (private/'attempted').exists():
        return subprocess.run(['/usr/bin/python3',*arguments],timeout=90).returncode
    transaction,_=transaction_for(arguments)
    config=json.loads((private/'config.json').read_text())
    need(os.stat('/proc/self/ns/mnt').st_ino!=config['parent_namespace'],
         'publisher requires a separate private CLI mount namespace')
    (private/'attempted').write_text('one unchanged publisher\n')
    observer=private_directory(private/'observer')
    (observer/'config.json').write_text(json.dumps({'transaction':str(transaction),
                                               'parent_namespace':config['parent_namespace']}))
    result=subprocess.run(['/usr/bin/python3',*arguments],
                          env={**os.environ,'PYTHONPATH':str(observer)},timeout=90)
    need(result.returncode==0 and (observer/'sealed.json').is_file(),
         'actual publisher did not finish with its post-commit journal bind')
    (private/'publisher-result.json').write_text(json.dumps({'publisher_exit':result.returncode,
                                                          'transaction':str(transaction)}))
    return result.returncode


@contextmanager
def readonly_committed_progress(logs, env):
    require_publisher_guest()
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    original_mounts=mounts()
    private=logs/('committed-progress-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    (private/'config.json').write_text(json.dumps({'parent_namespace':namespace}))
    observer=private/'observer'
    observer.mkdir(mode=0o700)
    (observer/'sitecustomize.py').write_text(TRACE_SOURCE)
    launcher=private/'python3'
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_commit_progress import run_publisher\nraise SystemExit(run_publisher(sys.argv[1:],__file__))\n')
    launcher.chmod(0o700)
    original=env['PATH']
    observed={}
    try:
        env['PATH']=str(private)+':'+original
        yield observed
        receipt=json.loads((private/'publisher-result.json').read_text())
        need(receipt['publisher_exit']==0,'committed publisher reported failure')
        observed.update(json.loads((observer/'sealed.json').read_text()))
        observed['transaction']=receipt['transaction']
    finally:
        env['PATH']=original
        need(os.stat('/proc/self/ns/mnt').st_ino==namespace and mounts()==original_mounts,
             'committed-progress fault changed the parent mount namespace')


def verify_committed_progress(observed, result, passed):
    require_publisher_guest()
    need(observed.get('journal_probe_errno')==errno.EROFS and observed.get('private_cli_namespace') is True
         and observed.get('after_final_directory_sync') is True and observed.get('journal_unchanged') is True,
         'committed-progress observation is incomplete')
    need(result.returncode==0 and
         b'Deployment committed; transaction progress journal could not be completed.' in result.stdout
         and b'Read-only file system' in result.stderr,'actual caller append did not retain committed success')
    transaction=Path(observed['transaction'])
    rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
    events=[row[1] for row in rows]
    need(events[-1]=='COMMIT_INTENT' and events.count('COMMIT_INTENT')==1
         and not any(event in events for event in ('COMMIT','ROLLBACK_BEGIN','ROLLBACK_COMPLETE','ROLLED_BACK'))
         and not (transaction/'commit-uncertain.env').exists(),
         'derived progress refusal changed terminal deployment state')
    fields=dict(line.split('=',1) for line in (transaction/'metadata.env').read_text().splitlines())
    verify=subprocess.run(['bash','-c','source "$1"; pnm_tx_deployment_marker verify "$2" "$3" "$4"',
        'verify-marker','/opt/pnm/lib/deployment-state.sh',str(transaction),transaction.name,fields['DEPLOYMENT_ID']],
        capture_output=True,timeout=20)
    need(verify.returncode==0 and not verify.stdout,'committed marker failed actual product verification')
    passed.append('actual post-fsync journal EROFS keeps committed install success without rollback or parent mounts')
