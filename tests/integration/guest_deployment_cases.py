"""Real first-deployment service failures without repairing recovery in the fixture."""
from pathlib import Path
import json
import subprocess

from guest_start_fault import require, require_guest, start_fault
from guest_recovery_cases import fingerprint


def run_startup_failures(logs, call, absent, passed) -> None:
    require_guest()
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
    for core in ('xray','hysteria2'):
        before=set(transactions.iterdir())
        with start_fault(core) as fault:
            call('install-start-failure-'+core,['install','--apply','--yes'],accepted=(70,))
            created=set(transactions.iterdir())-before
            require(len(created)==1,'startup failure created an unexpected transaction count')
            transaction=created.pop()
            rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
            events=[row[1] for row in rows]
            observation={'core':core,'start_attempts':fault['attempts'],'rejected':fault['rejected'],
                'events':events,'units':unit_state(),
                'authority_nss_recovered':baseline=={str(path):fingerprint(path)[:4] for path in fixed},
                'directories_recovered':original_directories==directory_state(),
                'applied_absent':all(not path.exists() and not path.is_symlink() for path in
                    (Path('/var/lib/pnm/cores')/name/'applied.env' for name in ('xray','hysteria2'))),
                'commit_absent':all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                                    for name in ('commit.env','commit-uncertain.env'))}
            observations.append(observation)
            (logs/'deployment-startup-failures.json').write_text(json.dumps(observations))
            require(fault['attempts']==1 and fault['rejected']==1
                    and any(row[1]=='STEP_FAILED' and row[2]=='start rc=70' for row in rows),
                    'deployment failure did not follow the actual rejected Core start')
            require(events[-1]=='ROLLED_BACK' and 'ROLLBACK_COMPLETE' in events
                    and 'RECOVERY_REQUIRED' not in events and 'COMMIT' not in events
                    and observation['authority_nss_recovered'] and observation['directories_recovered']
                    and observation['applied_absent'] and observation['commit_absent']
                    and observation['units']==original_units,
                    'incomplete deployment rollback after '+core+' startup failure')
            absent()
        passed.append('actual first-deployment '+core+' start failure restores original resources identities and service baseline')
