"""Expected retained uncertainty after a real service compensation also fails."""
from pathlib import Path
import hashlib
import stat

from guest_start_fault import require, require_guest, start_fault


def fingerprint(path: Path) -> tuple:
    info=path.lstat()
    require(stat.S_ISREG(info.st_mode),'unexpected recovery resource type')
    with path.open('rb') as stream:
        digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return digest,info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino,info.st_mtime_ns


def receipt_state() -> dict:
    result={}
    for root in (Path('/var/lib/pnm'),Path('/etc/pnm')):
        for path in [root,*sorted(root.rglob('*'))]:
            info=path.lstat()
            require(not stat.S_ISLNK(info.st_mode),'unexpected recovery-state link')
            if stat.S_ISDIR(info.st_mode):
                result[str(path)]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino,info.st_mtime_ns)
            else:
                result[str(path)]=fingerprint(path)
    for name in ('passwd','group','shadow','gshadow'):
        path=Path('/etc')/name
        result[str(path)]=fingerprint(path)
    return result


def require_uncertain(transaction: Path, *, minimum_writes: int) -> None:
    rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
    events=[row[1] for row in rows]
    require(events.count('WRITE')>=minimum_writes and events[-1]=='RECOVERY_REQUIRED'
            and 'ROLLBACK_COMPLETE' not in events and 'ROLLED_BACK' not in events
            and 'COMMIT' not in events,'failed compensation was incorrectly finalized')
    require(any(row[1]=='RECOVERY_REQUIRED' and 'rollback_rc=70 original_rc=1' in row[2]
                for row in rows),'original and recovery failures are not both retained')
    marker=transaction/'commit.env'
    require(not marker.exists() and not marker.is_symlink(),'uncertain operation has a commit marker')


def require_commands_blocked(call, state, healthy_core: str, passed: list) -> None:
    require_guest()
    before={core:state(core) for core in ('xray','hysteria2')}
    receipts=receipt_state()
    managed_paths=sorted({Path(path) for core in before.values() for path in core['resources']})
    managed={str(path):fingerprint(path) for path in managed_paths}
    commands=(('writer',['apply',healthy_core]),('links',['--json','node','links','--address','203.0.113.10']),
              ('show',['--json','node','show']),('check',['--json','check']))
    for label,arguments in commands:
        refused=call('uncertain-'+label,arguments,accepted=(70,))
        require(not refused.stdout,'uncertain operation disclosed protected output')
    require(before=={core:state(core) for core in before},'refused command changed a Core')
    require(receipts==receipt_state(),'refused command changed persisted state or identities')
    require(managed=={str(path):fingerprint(path) for path in managed_paths},
            'refused command replaced or rewrote a managed Core resource')
    passed.append('retained recovery uncertainty blocks real writer and protected reads after fault removal')


def run_core_recovery_failure(call, state, core: str, passed: list) -> None:
    require_guest()
    require(core in ('xray','hysteria2'),'unknown failed-recovery Core')
    peer='hysteria2' if core=='xray' else 'xray'
    before=state(core)
    peer_before=state(peer)
    transactions=set(Path('/var/lib/pnm/transactions').iterdir())
    with start_fault(core,mode='reject-twice') as fault:
        failed=call('rollback-recovery-failure-'+core,['rollback',core],accepted=(1,))
        require(b'Core rollback failed during service restart (rc=1) and rollback failed (rc=70); recovery files were retained.'
                in failed.stderr,'rollback recovery failure has a different cause')
        require(fault['attempts']==2 and fault['rejected']==2,'both rollback starts were not rejected')
        after=state(core)
        require(after['resources']==before['resources'] and after['previous']==before['previous']
                and after['applied']==before['applied'],'failed service recovery corrupted binary/previous/applied resources')
        require(after['active']=='failed' and after['pid']=='0' and after['enabled']==before['enabled'],
                'failed compensation target was incorrectly reported active')
        require(state(peer)==peer_before,'failed compensation changed peer Core')
        created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
        require(len(created)==1,'failed compensation created unexpected transactions')
        require_uncertain(created.pop(),minimum_writes=1)
    passed.append('actual '+core+' failed rollback compensation retains original failure and uncertain evidence')
    require_commands_blocked(call,state,peer,passed)


def run_restore_recovery_failure(logs, call, state, binding, all_paths, archive: Path, passed: list) -> None:
    require_guest()
    node=Path('/etc/pnm/node.conf')
    original=node.read_text()
    changed=original.replace('XRAY_TARGET=edge.example.net:443','XRAY_TARGET=recovery.example.net:443')
    require(changed!=original,'failed restore recovery fixture did not change target')
    node.write_text(changed)
    call('apply-before-restore-recovery-failure',['apply','xray'])
    # Publication is atomic: compare content/mode/UID/GID here; require stable
    # inode and mtime only for the later refused commands, which must not write.
    before_resources={p:fingerprint(Path(p))[:4] for p in all_paths}
    before={core:state(core) for core in ('xray','hysteria2')}
    transactions=set(Path('/var/lib/pnm/transactions').iterdir())
    require(hashlib.sha256(archive.read_bytes()).hexdigest()==(logs/'trusted-backup.sha256').read_text(),
            'trusted restore archive changed before failed recovery')
    with start_fault('hysteria2',mode='reject-twice') as fault:
        failed=call('restore-recovery-failure',['restore',str(archive)],accepted=(1,))
        require(b'Core restore failed (rc=1) and rollback failed (rc=70); recovery files were retained.'
                in failed.stderr,'restore recovery failure has a different cause')
        require(fault['attempts']==2 and fault['rejected']==2,'both restore starts were not rejected')
        require(before_resources=={p:fingerprint(Path(p))[:4] for p in all_paths},
                'restore recovery did not recover original ordinary resources')
        binding('xray')
        require(state('xray')['invocation']!=before['xray']['invocation'],'recovered Xray kept stale invocation')
        hy2=state('hysteria2')
        require(hy2['active']=='failed' and hy2['pid']=='0' and hy2['applied']==before['hysteria2']['applied'],
                'failed HY2 compensation was certified or lost prior evidence')
        created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
        require(len(created)==1,'restore recovery created unexpected transactions')
        require_uncertain(created.pop(),minimum_writes=12)
    passed.append('actual failed HY2 restore compensation retains recovered files and uncertain service evidence')
    require_commands_blocked(call,state,'xray',passed)
