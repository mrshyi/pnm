"""Real first-deployment service failures without repairing recovery in the fixture."""
from pathlib import Path
import json
import signal
import subprocess
import threading
import time

from guest_start_fault import require, require_guest, start_fault
from guest_recovery_cases import fingerprint, receipt_state


def require_pending_deployment(call, unit_state, passed) -> None:
    require_guest()
    managed=tuple(Path(name) for name in ('/usr/local/bin/xray','/usr/local/bin/hysteria',
        '/usr/local/etc/xray/config.json','/etc/hysteria/config.yaml',
        '/etc/hysteria/tls/server.crt','/etc/hysteria/tls/server.key',
        '/etc/systemd/system/xray.service','/etc/systemd/system/hysteria-server.service'))
    receipts=receipt_state()
    resources={str(path):fingerprint(path) for path in managed}
    services=unit_state()
    for label,args in (('writer',['apply','hysteria2']),
            ('links',['--json','node','links','--address','203.0.113.10']),
            ('show',['--json','node','show']),('check',['--json','check'])):
        refused=call('pending-deployment-'+label,args,accepted=(70,))
        require(not refused.stdout,'pending deployment disclosed protected output')
        require(b'Unresolved deployment transaction ' in refused.stderr,
                'protected command refusal did not identify the interrupted deployment')
    require(receipts==receipt_state() and resources=={str(path):fingerprint(path) for path in managed}
            and services==unit_state(),'refused deployment command changed persisted state or services')
    passed.append('interrupted deployment blocks real writer and protected readers without mutation after fault removal')


def run_startup_failures(logs, call, absent, passed, *, failure='start', env=None) -> None:
    require_guest()
    require(failure in ('start','listener','term','kill','commit'),'unknown deployment startup failure')
    committing=failure=='commit'
    require(not committing or env is not None,'deployment commit fault requires CLI environment')
    delayed=failure=='listener'
    signalled=failure in ('term','kill')
    hard=failure=='kill'
    fixed=[Path('/etc/pnm/node.conf'),Path('/etc/pnm/versions.conf')]
    fixed.extend(Path('/etc')/name for name in ('passwd','group','shadow','gshadow'))
    baseline={str(path):fingerprint(path)[:4] for path in fixed}
    directories=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray','/etc/hysteria',
                 '/etc/hysteria/tls','/usr/local/bin','/etc/systemd/system',
                 '/etc/systemd/system/multi-user.target.wants','/var/lib/pnm/cores')

    def directory_state() -> dict:
        result={}
        for name in directories:
            path=Path(name)
            require(not path.is_symlink(),'unexpected deployment directory link')
            if not path.exists():
                result[name]=None
            else:
                info=path.stat()
                require(path.is_dir(),'unexpected deployment directory type')
                result[name]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino)
        return result

    def unit_state() -> dict:
        result={}
        for unit in ('xray.service','hysteria-server.service'):
            output=subprocess.check_output(['systemctl','show',unit,
                '--property=LoadState,ActiveState,MainPID'],text=True,timeout=10)
            result[unit]=dict(line.split('=',1) for line in output.splitlines() if line)
        return result

    original_directories=directory_state()
    original_units=unit_state()
    require(all(item=={'LoadState':'not-found','ActiveState':'inactive','MainPID':'0'}
                for item in original_units.values()),'unexpected pre-deployment service baseline')
    observations=[]
    transactions=Path('/var/lib/pnm/transactions')
    deployments=Path('/var/lib/pnm/deployments')
    applies=Path('/var/lib/pnm/apply')
    for core in (('commit',) if committing else (('xray',) if hard else ('xray','hysteria2'))):
        before=set(transactions.iterdir())
        before_deployments=set(deployments.iterdir()) if deployments.exists() else set()
        before_applies=set(applies.iterdir()) if applies.exists() else set()
        if committing:
            from guest_commit_fault import readonly_deployment_commit
            context=readonly_deployment_commit(logs,env)
        else:
            context=start_fault(core,mode='delay' if failure!='start' else 'reject-once',delay_seconds=12 if delayed else 3)
        with context as fault:
            startup_runtime={}
            stop=threading.Event()

            def observe_start() -> None:
                try:
                    while not stop.wait(0.02):
                        if not fault['attempts']:
                            continue
                        unit='xray.service' if core=='xray' else 'hysteria-server.service'
                        flag,port=('-lnt',443) if core=='xray' else ('-lnu',8443)
                        active=subprocess.check_output(['systemctl','show',unit,
                            '--property=ActiveState','--value'],text=True,timeout=3).strip()
                        if active!='active':
                            continue
                        sockets=subprocess.check_output(['ss','-H',flag],text=True,timeout=3)
                        startup_runtime.update({'active':active,'listener_present':any(
                            line.split()[3].endswith(':'+str(port)) for line in sockets.splitlines())})
                        return
                except Exception as error:
                    startup_runtime['error_class']=type(error).__name__

            observer=threading.Thread(target=observe_start,name='pnm-startup-observer') if delayed else None
            if observer is not None:
                observer.start()
            try:
                if signalled:
                    from guest_signal_cases import signal_owned_command_on_start
                    caught=signal.SIGKILL if hard else signal.SIGTERM
                    with signal_owned_command_on_start(fault,caught) as slot:
                        failed=call('install-'+failure+'-'+core,['install','--apply','--yes'],
                                    accepted=(-9 if hard else 143,),process_slot=slot)
                elif committing:
                    failed=call('install-commit-failure',['install','--apply','--yes'],accepted=(73,))
                else:
                    failed=call('install-'+failure+'-failure-'+core,['install','--apply','--yes'],
                                accepted=(78 if delayed else 70,))
                returned_at=time.monotonic()
            finally:
                stop.set()
                if observer is not None:
                    observer.join(timeout=7)
                    require(not observer.is_alive(),'startup observer did not retire')
            created=set(transactions.iterdir())-before
            require(len(created)==1,'startup failure created an unexpected transaction count')
            transaction=created.pop()
            rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
            events=[row[1] for row in rows]
            if hard:
                deadline=time.monotonic()+10
                while True:
                    sockets=subprocess.check_output(['ss','-H','-lnt'],text=True,timeout=3)
                    if any(line.split()[3].endswith(':443') for line in sockets.splitlines()):
                        break
                    require(time.monotonic()<deadline,'post-SIGKILL deployment listener did not stabilize')
                    time.sleep(0.1)
            created_deployments=set(deployments.iterdir())-before_deployments
            require(len(created_deployments)==1,'startup failure created an unexpected deployment count')
            phase_rows=[line.split('\t',2) for line in
                        (created_deployments.pop()/'journal.tsv').read_text().splitlines()]
            if delayed:
                name='Xray' if core=='xray' else 'Hysteria2'
                cause=('post-health failed for '+name).encode() in failed.stderr
                cause=cause and (core+' post-health failed at '+core+' (FAIL)').encode() in failed.stderr
                cause=cause and any(row[1]=='PHASE_FAILED' and row[2]=='post-health rc=78' for row in phase_rows)
                cause=cause and all(any(row[1]=='PHASE_DONE' and row[2]==phase for row in phase_rows)
                                    for phase in ('xray-lifecycle','hysteria-lifecycle'))
                cause=cause and startup_runtime=={'active':'active','listener_present':False}
                # The managed program cannot exec the Core before its12-second
                # sleep. Require the entire failed operation to return earlier.
                wait_preserved=(fault['first_attempt_at'] is not None and
                                returned_at-fault['first_attempt_at']<11.75)
                cause=cause and wait_preserved
            elif signalled:
                wait_preserved=None
                if hard:
                    cause=failed.returncode==-9 and 'WRITE' in events and 'STEP_BEGIN' in events
                else:
                    created_applies=set(applies.iterdir())-before_applies
                    require(len(created_applies)==1,'TERM deployment has an unexpected apply receipt count')
                    apply_rows=[line.split('\t',2) for line in
                                (created_applies.pop()/'journal.tsv').read_text().splitlines()]
                    cause=failed.returncode==143 and any(row[1]=='APPLY_FAILED' and row[2]=='rc=143'
                                                        for row in apply_rows)
            elif committing:
                wait_preserved=None
                cause=failed.returncode==73 and b'Deployment commit record could not be persisted or verified.' in failed.stderr
                cause=cause and events.count('COMMIT_INTENT')==1 and all(
                    any(row[1:]==['WRITE','label=applied_'+name] for row in rows) for name in ('xray','hysteria2'))
                cause=cause and all(any(row[1]=='PHASE_DONE' and row[2]==phase for row in phase_rows)
                                    for phase in ('xray-lifecycle','hysteria-lifecycle','post-health'))
            else:
                cause=any(row[1]=='STEP_FAILED' and row[2]=='start rc=70' for row in rows)
                wait_preserved=None
            observation={'core':core,'failure':failure,'failure_cause_confirmed':cause,
                'startup_runtime':startup_runtime,'program_wait_preserved':wait_preserved,
                'start_attempts':fault.get('attempts'),'rejected':fault.get('rejected'),
                'events':events,'units':unit_state(),
                'authority_nss_recovered':baseline=={str(path):fingerprint(path)[:4] for path in fixed},
                'directories_recovered':original_directories==directory_state(),
                'applied_absent':all(not path.exists() and not path.is_symlink() for path in
                    (Path('/var/lib/pnm/cores')/name/'applied.env' for name in ('xray','hysteria2'))),
                'commit_absent':all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                                    for name in ('commit.env','commit-uncertain.env'))}
            observations.append(observation)
            (logs/'deployment-startup-failures.json').write_text(json.dumps(observations))
            require((committing or (fault['attempts']==1 and fault['rejected']==(1 if failure=='start' else 0))) and cause,
                    'deployment failure did not follow the intended real Core startup phase')
            if hard:
                require(not any(event in events for event in ('COMMIT','ROLLED_BACK','ROLLBACK_COMPLETE'))
                        and observation['commit_absent'] and observation['applied_absent'],
                        'SIGKILL deployment was falsely finalized or promoted')
            else:
                require(events[-1]=='ROLLED_BACK' and 'ROLLBACK_COMPLETE' in events
                    and 'RECOVERY_REQUIRED' not in events and 'COMMIT' not in events
                    and observation['authority_nss_recovered'] and observation['directories_recovered']
                    and observation['applied_absent'] and observation['commit_absent']
                    and observation['units']==original_units,
                        'incomplete deployment rollback after '+core+' startup failure')
                absent()
        if committing:
            require(fault['actual_errno']==30 and fault['pending_creation_refused'] and fault['mount_removed'],
                    'deployment commit has no actual retired publisher EROFS')
            observations[-1]['commit_refusal']=fault
            (logs/'deployment-startup-failures.json').write_text(json.dumps(observations))
        if hard:
            passed.append('actual SIGKILL during first deployment retains unfinished resources and absent applied/commit promotion')
            require_pending_deployment(call,unit_state,passed)
            return
        passed.append('actual deployment commit publisher EROFS restores original resources identities and service baseline'
                      if committing else 'actual first-deployment '+core+' '+failure+' failure restores original resources identities and service baseline')
