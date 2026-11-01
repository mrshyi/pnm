"""Pause the actual publisher for an owned VM kill, then inspect the next boot."""
import json
import os
from pathlib import Path
import re
import select
import signal
import stat
import subprocess
import time

from guest_vm_boot import GuestRefusal, main as boot_main, require_approved_vm, require_vm
from guest_vm_lifecycle import UNITS, binding, core_state, fingerprint, need, show
from guest_commit_signal import late_deployment_commit


BASELINE=Path('/var/tmp/pnm-vm-abrupt-baseline.json')
ENV={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','LANG':'C.UTF-8','TZ':'UTC'}
LOGS=Path('/var/tmp/pnm-vm-abrupt-evidence')


def receipts() -> dict:
    result={}
    for directory in Path('/var/lib/pnm/transactions').iterdir():
        need(directory.is_dir() and not directory.is_symlink(),'unexpected transaction entry')
        for path in directory.rglob('*'):
            need(not path.is_symlink(),'unexpected transaction link')
            if path.is_file():
                result[str(path)]=fingerprint(str(path))
    return result


def journal_observation(path: Path) -> dict:
    """Progress appends may tear across a VM stop; never repair or trust them."""
    rows=[line.split(b'\t',2) for line in path.read_bytes().splitlines()]
    valid=[row for row in rows if len(row)==3 and all(b'\0' not in value for value in row)]
    events=[row[1] for row in valid]
    return {'commit_intent_present':b'COMMIT_INTENT' in events,
            'terminal_present':any(event in events for event in
                (b'COMMIT',b'ROLLBACK_BEGIN',b'ROLLBACK_COMPLETE',b'ROLLED_BACK')),
            'malformed_rows':len(rows)-len(valid),'row_count':len(rows)}


def call(label: str,args: list[str],accepted: tuple[int,...]=(0,)) -> subprocess.CompletedProcess:
    with subprocess.Popen(['bash','/opt/pnm/bin/pnm']+args,env=ENV,stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True) as process:
        try:
            stdout,stderr=process.communicate(timeout=150)
        except subprocess.TimeoutExpired:
            for caught in (signal.SIGTERM,signal.SIGKILL):
                try:
                    os.killpg(process.pid,caught)
                except ProcessLookupError:
                    pass
                if caught==signal.SIGTERM:
                    time.sleep(2)
            process.communicate(timeout=10)
            raise RuntimeError('abrupt VM CLI timed out') from None
        (LOGS/(label+'.stdout')).write_bytes(stdout)
        (LOGS/(label+'.stderr')).write_bytes(stderr)
        need(process.returncode in accepted,'abrupt VM CLI failed: '+label)
        return subprocess.CompletedProcess(process.args,process.returncode,stdout,stderr)


def emit_window(identity,transaction: Path) -> None:
    record={'schema':1,'kind':'crash-window','instance':identity.instance,'boot_id':identity.boot_id,
            'scope':'deployment-abrupt','transaction':transaction.name,
            'post_rename':True,'uncertainty_present':True,'both_applied_bound':True}
    message=('PNM_VM '+json.dumps(record)+'\n').encode()
    descriptor=os.open('/dev/ttyS0',os.O_WRONLY|os.O_NOCTTY|os.O_NONBLOCK|os.O_NOFOLLOW)
    try:
        info=os.fstat(descriptor)
        need(stat.S_ISCHR(info.st_mode) and (os.major(info.st_rdev),os.minor(info.st_rdev))==(4,64),
             'unexpected abrupt VM serial device')
        deadline=time.monotonic()+3
        while message and time.monotonic()<deadline:
            if select.select([],[descriptor],[],0.2)[1]:
                try:
                    message=message[os.write(descriptor,message):]
                except BlockingIOError:
                    pass
        need(not message,'abrupt VM window announcement timed out')
    finally:
        os.close(descriptor)


def prepare_interruption() -> dict:
    identity=require_approved_vm()
    LOGS.mkdir(mode=0o700)
    pins=json.loads(Path('/opt/pnm-test-versions.json').read_text())
    call('node-init',['node','init','--region','test','--address','203.0.113.10','--timezone','UTC',
         '--server-name','www.cloudflare.com','--target','www.cloudflare.com:443',
         '--hy2-server-name','guest.invalid','--xray-version',pins['xray']['version'],
         '--xray-sha256',pins['xray']['sha256'],'--hy2-version',pins['hysteria2']['version'],
         '--hy2-sha256',pins['hysteria2']['sha256']])
    call('node-validate',['node','validate'])
    transactions=Path('/var/lib/pnm/transactions')
    before=set(transactions.iterdir())
    with late_deployment_commit(LOGS,ENV) as ready:
        with (LOGS/'install.stdout').open('xb') as output,(LOGS/'install.stderr').open('xb') as error:
            process=subprocess.Popen(['bash','/opt/pnm/bin/pnm','install','--apply','--yes'],
                env=ENV,stdin=subprocess.DEVNULL,stdout=output,stderr=error,start_new_session=True)
            try:
                deadline=time.monotonic()+60
                observed=False
                while time.monotonic()<deadline and process.poll() is None:
                    try:
                        info=ready.lstat()
                        observed=(stat.S_ISREG(info.st_mode) and info.st_uid==0
                            and stat.S_IMODE(info.st_mode)==0o600 and info.st_size<=1024
                            and json.loads(ready.read_text())=={'marker_present':True,
                                'uncertainty_present':True,'before_directory_sync':True})
                    except (OSError,ValueError):
                        pass
                    if observed:
                        break
                    time.sleep(0.02)
                need(observed and process.poll() is None,'actual publisher pause was not reached')
                paused_at=time.monotonic()
                created=set(transactions.iterdir())-before
                need(len(created)==1,'abrupt VM created unexpected deployment count')
                transaction=created.pop()
                rows=[row.split('\t',2) for row in (transaction/'journal.tsv').read_text().splitlines()]
                need(rows[-1][1]=='COMMIT_INTENT' and sum(row[1]=='COMMIT_INTENT' for row in rows)==1,
                     'abrupt VM did not reach unique commit intent')
                for core in UNITS:
                    binding(core)
                baseline={'schema':1,'boot_id':identity.boot_id,'transaction':transaction.name,
                          'commit_intent_observed_before_stop':True,
                          'cores':{core:core_state(core) for core in UNITS},
                          'authority':{p:fingerprint(p) for p in ('/etc/pnm/node.conf','/etc/pnm/versions.conf',
                              '/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')}}
                with BASELINE.open('x') as stream:
                    json.dump(baseline,stream)
                    stream.flush()
                    os.fsync(stream.fileno())
                current_rows=(transaction/'journal.tsv').read_text().splitlines()
                need(time.monotonic()-paused_at<15 and process.poll() is None
                     and current_rows and current_rows[-1].split('\t',2)[1]=='COMMIT_INTENT'
                     and (transaction/'commit-uncertain.env').is_file()
                     and (transaction/'commit.env').is_file(),
                     'publisher pause expired while persisting the observed baseline')
                emit_window(identity,transaction)
                # Only the live host owner may kill QEMU. Never signal the CLI
                # as a substitute for stopping this independent kernel.
                time.sleep(12)
                raise RuntimeError('owned VM was not stopped at the announced window')
            finally:
                if process.poll() is None:
                    need(os.getsid(process.pid)==process.pid and os.getpgid(process.pid)==process.pid,
                         'abrupt VM CLI cleanup lost its process group')
                    for caught in (signal.SIGTERM,signal.SIGKILL):
                        try:
                            os.killpg(process.pid,caught)
                        except ProcessLookupError:
                            pass
                        if caught==signal.SIGTERM:
                            time.sleep(2)
                    process.wait(timeout=10)


def recovery() -> dict:
    identity=require_approved_vm()
    baseline=json.loads(BASELINE.read_text())
    need(baseline['schema']==1 and baseline['boot_id']!=identity.boot_id,
         'abrupt VM did not enter a different kernel boot')
    name=baseline['transaction']
    need(re.fullmatch(r'tx-[0-9a-f]{32}',name),'abrupt VM transaction identity differs')
    transaction=Path('/var/lib/pnm/transactions')/name
    uncertainty=transaction/'commit-uncertain.env'
    need(uncertainty.read_text()=='SCHEMA_VERSION=1\nORIGINAL_RC=70\n',
         'abrupt VM lost persistent uncertainty')
    observation=journal_observation(transaction/'journal.tsv')
    # The publisher fsyncs uncertainty before rename. The progress journal is
    # not its commit authority and may have lost/torn appends after this stop.
    # Retain the exact damaged bytes and test real fresh-command refusal below.
    need(baseline.get('commit_intent_observed_before_stop') is True
         and not observation['terminal_present'],
         'abrupt VM finalized or compensated the observed pending transaction')
    need(baseline['authority']=={p:fingerprint(p) for p in baseline['authority']},
         'abrupt VM changed authority or NSS resources')
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if all(show(unit,'ActiveState')=='active' for unit in UNITS.values()):
            break
        time.sleep(0.2)
    states={core:core_state(core) for core in UNITS}
    for core,current in states.items():
        original=baseline['cores'][core]
        need(current['active']=='active' and current['enabled']=='enabled'
             and current['invocation']!=original['invocation'] and current['resources']==original['resources']
             and current['applied']==original['applied'],'abrupt VM persisted/runtime baseline differs')
    before=receipts()
    for label,args in (('writer',['apply','hysteria2']),
            ('links',['--json','node','links','--address','203.0.113.10']),
            ('show',['--json','node','show']),('check',['--json','check'])):
        result=call('pending-'+label,args,(70,))
        need(not result.stdout and b'Unresolved deployment transaction ' in result.stderr,
             'abrupt VM protected command refused for another cause or leaked output')
    need(before==receipts() and states=={core:core_state(core) for core in UNITS}
         and baseline['authority']=={p:fingerprint(p) for p in baseline['authority']},
         'abrupt VM refused commands changed persisted or runtime state')
    return {'kernel_boot_id_changed':True,'uncertainty_retained':True,
            'commit_intent_observed_before_stop':True,'journal_observation':observation,
            'both_invocations_changed':True,'resources_preserved':True,'fresh_commands_blocked':4,
            'protected_output_empty':True,'refusals_did_not_mutate':True,
            'commit_marker_present':(transaction/'commit.env').is_file()}


def main() -> None:
    require_vm()
    os.umask(0o077)
    resumed=BASELINE.exists()
    boot_main(action=recovery if resumed else prepare_interruption,
              scope='deployment-recovery' if resumed else 'deployment-abrupt')


if __name__=='__main__':
    try:
        main()
    except GuestRefusal:
        raise SystemExit(77) from None
