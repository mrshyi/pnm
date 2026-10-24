"""Real CLI missing-tool preflight in a guarded private native guest."""
from pathlib import Path
import json
import os
import subprocess

from guest_start_fault import require, require_guest
from guest_recovery_cases import fingerprint


def run_dependencies(logs, env, call, absent, passed) -> None:
    require_guest()
    classes={name:'tools' for name in
             ('apt-get','awk','curl','flock','install','python3','sha256sum','ss')}
    classes.update({'systemctl':'systemd','unzip':'xray_assets','openssl':'tls_tools',
                    'systemd-analyze':'unit_tools','runuser':'service_access_tools'})
    classes.update({name:'service_account_tools' for name in
                    ('getent','groupadd','useradd','userdel','groupdel','id')})
    baseline_paths=[Path('/etc/pnm/node.conf'),Path('/etc/pnm/versions.conf')]
    baseline_paths.extend(Path('/etc')/name for name in ('passwd','group','shadow','gshadow'))
    baseline={str(path):fingerprint(path) for path in baseline_paths}
    transactions=Path('/var/lib/pnm/transactions')
    original_transactions=set(transactions.iterdir())

    def inventory() -> dict:
        # Hash the authority/NSS bytes above; metadata also detects new or
        # rewritten state/cache entries without rehashing large assets19 times.
        result={}
        for root in (Path('/var/lib/pnm'),Path('/etc/pnm')):
            for path in [root,*sorted(root.rglob('*'))]:
                info=path.lstat()
                result[str(path)]=(info.st_dev,info.st_ino,info.st_mode,info.st_uid,
                                   info.st_gid,info.st_size,info.st_mtime_ns)
        return result

    def unit_state() -> dict:
        result={}
        for unit in ('xray.service','hysteria-server.service'):
            output=subprocess.check_output(['systemctl','show',unit,
                '--property=LoadState,ActiveState,MainPID'],text=True,timeout=10)
            result[unit]=dict(line.split('=',1) for line in output.splitlines() if line)
            require(result[unit]=={'LoadState':'not-found','ActiveState':'inactive','MainPID':'0'},
                    'managed unit unexpectedly exists during dependency refusal')
        return result

    original_inventory=inventory()
    original_units=unit_state()
    filtered=logs/'dependency-path'
    filtered.mkdir(mode=0o700)
    for folder in ('/usr/sbin','/usr/bin','/sbin','/bin'):
        for program in Path(folder).iterdir():
            link=filtered/program.name
            if program.is_file() and os.access(program,os.X_OK) and not link.exists():
                link.symlink_to(program)
    original_path=env['PATH']
    for command,check_id in classes.items():
        link=filtered/command
        require(link.is_symlink(),'required native dependency is missing from the trusted fixture')
        target=link.readlink()
        link.unlink()
        env['PATH']=str(filtered)
        try:
            refusal=call('missing-'+command,['--json','install','--apply','--yes'],accepted=(2,))
        finally:
            env['PATH']=original_path
            link.symlink_to(target)
        report=json.loads(refusal.stdout)['preflight']
        checks={item['id']:item for item in report['checks']}
        require(report['overall']=='FAIL' and checks[check_id]['status']=='FAIL',
                'missing dependency was not diagnosed in its required class: '+command)
        require(command=='systemctl' or command in checks[check_id]['detail'],
                'missing dependency diagnostic did not name its cause: '+command)
        absent()
        require(baseline=={str(path):fingerprint(path) for path in baseline_paths}
                and original_transactions==set(transactions.iterdir())
                and original_inventory==inventory() and original_units==unit_state(),
                'missing dependency changed managed state, identities or services: '+command)
        passed.append('actual missing '+command+' refuses2 before managed state, account or service changes')
