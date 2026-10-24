"""Real first-deployment service failures without repairing recovery in the fixture."""
from pathlib import Path
import json
import subprocess
import threading
import time

from guest_start_fault import require, require_guest, start_fault
from guest_recovery_cases import fingerprint


def run_startup_failures(logs, call, absent, passed, *, failure='start') -> None:
    require_guest()
    require(failure in ('start','listener'),'unknown deployment startup failure')
    delayed=failure=='listener'
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
    for core in ('xray','hysteria2'):
        before=set(transactions.iterdir())
        before_deployments=set(deployments.iterdir()) if deployments.exists() else set()
        with start_fault(core,mode='delay' if delayed else 'reject-once',delay_seconds=12 if delayed else 3) as fault:
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
            else:
                cause=any(row[1]=='STEP_FAILED' and row[2]=='start rc=70' for row in rows)
                wait_preserved=None
            observation={'core':core,'failure':failure,'failure_cause_confirmed':cause,
                'startup_runtime':startup_runtime,'program_wait_preserved':wait_preserved,
                'start_attempts':fault['attempts'],'rejected':fault['rejected'],
                'events':events,'units':unit_state(),
                'authority_nss_recovered':baseline=={str(path):fingerprint(path)[:4] for path in fixed},
                'directories_recovered':original_directories==directory_state(),
                'applied_absent':all(not path.exists() and not path.is_symlink() for path in
                    (Path('/var/lib/pnm/cores')/name/'applied.env' for name in ('xray','hysteria2'))),
                'commit_absent':all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                                    for name in ('commit.env','commit-uncertain.env'))}
            observations.append(observation)
            (logs/'deployment-startup-failures.json').write_text(json.dumps(observations))
            require(fault['attempts']==1 and fault['rejected']==(0 if delayed else 1) and cause,
                    'deployment failure did not follow the intended real Core startup phase')
            require(events[-1]=='ROLLED_BACK' and 'ROLLBACK_COMPLETE' in events
                    and 'RECOVERY_REQUIRED' not in events and 'COMMIT' not in events
                    and observation['authority_nss_recovered'] and observation['directories_recovered']
                    and observation['applied_absent'] and observation['commit_absent']
                    and observation['units']==original_units,
                    'incomplete deployment rollback after '+core+' startup failure')
            absent()
        passed.append('actual first-deployment '+core+' '+failure+' failure restores original resources identities and service baseline')
