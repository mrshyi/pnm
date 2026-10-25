"""Real preexisting identities in a guarded disposable native guest."""
from pathlib import Path
import grp
import json
import pwd
import subprocess

from guest_start_fault import require, require_guest
from guest_recovery_cases import fingerprint


def nss_state() -> dict:
    return {str(path):fingerprint(path)[:4] for path in
            (Path('/etc')/name for name in ('passwd','group','shadow','gshadow'))}


def prepare_accounts() -> dict:
    require_guest()
    for name in ('xray','hysteria'):
        for lookup in (pwd.getpwnam,grp.getgrnam):
            try:
                lookup(name)
            except KeyError:
                pass
            else:
                raise RuntimeError('unexpected identity before account reuse fixture')
    for name in ('xray','hysteria'):
        subprocess.run(['groupadd','--system',name],check=True,capture_output=True,timeout=10)
        subprocess.run(['useradd','--system','--gid',name,'--home-dir','/nonexistent',
                        '--shell','/usr/sbin/nologin','--no-create-home',name],
                       check=True,capture_output=True,timeout=10)
        user=pwd.getpwnam(name)
        group=grp.getgrnam(name)
        require(user.pw_uid>0 and user.pw_gid==group.gr_gid>0
                and user.pw_dir=='/nonexistent' and user.pw_shell=='/usr/sbin/nologin',
                'preexisting service identity does not match policy')
    require(pwd.getpwnam('xray').pw_uid!=pwd.getpwnam('hysteria').pw_uid,
            'preexisting service identities overlap')
    return nss_state()


def require_preserved(baseline: dict) -> None:
    require_guest()
    require(len(baseline)==4 and nss_state()==baseline,'PNM changed preexisting NSS identities')
    # Existing identities must never enter the transaction's created-account
    # ledger, including the deployment that already completed compensation.
    for receipt in Path('/var/lib/pnm/transactions').glob('*/accounts.tsv'):
        require(receipt.is_file() and not receipt.is_symlink() and receipt.stat().st_size==0,
                'PNM claimed a preexisting identity as a created resource')


def run_creation_failures(logs, env, call, absent, passed) -> None:
    require_guest()
    from guest_account_fault import readonly_account_creation
    baseline=nss_state()
    authority={str(path):fingerprint(path)[:4] for path in
               (Path('/etc/pnm/node.conf'),Path('/etc/pnm/versions.conf'))}
    directories=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray','/etc/hysteria',
        '/etc/hysteria/tls','/usr/local/bin','/etc/systemd/system',
        '/etc/systemd/system/multi-user.target.wants','/var/lib/pnm/cores')

    def directory_state():
        result={}
        for name in directories:
            path=Path(name)
            require(not path.is_symlink(),'unexpected account baseline directory link')
            if not path.exists():
                result[name]=None
            else:
                info=path.stat()
                require(path.is_dir(),'unexpected account baseline directory type')
                result[name]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino)
        return result

    def unit_state():
        return {unit:subprocess.check_output(['systemctl','show',unit,
            '--property=LoadState,ActiveState,MainPID'],text=True,timeout=10)
            for unit in ('xray.service','hysteria-server.service')}

    original_directories=directory_state()
    original_units=unit_state()
    observations=[]
    for program,kind in (('groupadd','group'),('useradd','user')):
        transactions=Path('/var/lib/pnm/transactions')
        before=set(transactions.iterdir())
        with readonly_account_creation(logs,env,program) as fault:
            call('install-account-refusal-'+program,['install','--apply','--yes'],accepted=(70,))
            created=set(transactions.iterdir())-before
            require(len(created)==1,'account refusal created unexpected transactions')
            transaction=created.pop()
            events=[line.split('\t')[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
            require(events[-1]=='ROLLED_BACK' and 'ROLLBACK_COMPLETE' in events
                    and not any(event in events for event in ('COMMIT','COMMIT_INTENT','RECOVERY_REQUIRED')),
                    'account creation refusal did not complete compensation')
            accounts=[line.split('\t') for line in (transaction/'accounts.tsv').read_text().splitlines()]
            require(['APPLIED','user','xray'] in accounts and ['RESTORED','user','xray'] in accounts
                    and ['INTENT',kind,'hysteria'] in accounts and ['APPLIED',kind,'hysteria'] not in accounts,
                    'account refusal missed the intended partially created identity set')
            for row in accounts:
                if row[0]=='APPLIED':
                    require(['RESTORED',*row[1:]] in accounts,'created identity lacks compensation receipt')
            require(sum(row[0]=='APPLIED' for row in accounts)==(2 if kind=='group' else 3),
                    'account creation refused at an unexpected point')
            absent()
            require(nss_state()==baseline and authority=={
                name:fingerprint(Path(name))[:4] for name in authority},
                'account refusal changed primary NSS or authority bytes/metadata')
            require(directory_state()==original_directories and unit_state()==original_units,
                    'account refusal changed directory identity/metadata or service baseline')
            require(all(not path.exists() and not path.is_symlink() for path in
                [transaction/'commit.env',transaction/'commit-uncertain.env',
                 *(Path('/var/lib/pnm/cores')/core/'applied.env' for core in ('xray','hysteria2'))]),
                'account refusal promoted commit or applied evidence')
        observations.append({'program':program,'created_identities':2 if kind=='group' else 3,
            'primary_nss_recovered':True,'directories_recovered':True,'service_baseline_recovered':True,
            'refusal':fault})
        passed.append('actual second '+program+' read-only refusal compensates all earlier identities and permits retry')
    (logs/'account-creation-refusals.json').write_text(json.dumps(observations))
