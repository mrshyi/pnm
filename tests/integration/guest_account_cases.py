"""Real preexisting identities in a guarded disposable native guest."""
from pathlib import Path
import grp
import json
import pwd
import stat
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


def run_deletion_failure(logs, env, call, passed, *, program) -> None:
    require_guest()
    require(program in ('userdel','groupdel'),'unexpected account deletion tool')
    from guest_account_fault import readonly_account_tool
    from guest_commit_fault import readonly_deployment_commit
    from guest_recovery_cases import receipt_state
    if program=='groupdel':
        # Debian normally lets userdel remove its empty private group. Retain
        # groups through that real policy so PNM must execute explicit groupdel.
        policy=Path('/etc/login.defs')
        info=policy.lstat()
        parent=policy.parent.stat()
        require(policy.resolve()==policy and stat.S_ISREG(info.st_mode)
                and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o644
                and parent.st_uid==0 and not parent.st_mode & 0o022,
                'unexpected private-group policy fixture')
        lines=policy.read_text().splitlines(keepends=True)
        matches=[index for index,line in enumerate(lines)
                 if line.split() and line.split()[0]=='USERGROUPS_ENAB']
        require(len(matches)==1 and lines[matches[0]].split()==['USERGROUPS_ENAB','yes'],
                'private-group default policy differs from trusted baseline')
        lines[matches[0]]='USERGROUPS_ENAB\tno\n'
        policy.write_text(''.join(lines))
        after=policy.lstat()
        require((after.st_mode,after.st_uid,after.st_gid,after.st_ino)==
                (info.st_mode,info.st_uid,info.st_gid,info.st_ino),
                'private-group policy fixture changed ownership or identity')
    resources=tuple(Path(name) for name in (
        '/etc/login.defs','/etc/pnm/node.conf','/etc/pnm/versions.conf',
        '/etc/pnm/secrets/reality.env','/etc/pnm/secrets/hysteria.env',
        '/usr/local/bin/xray','/usr/local/bin/hysteria',
        '/usr/local/etc/xray/config.json','/etc/hysteria/config.yaml',
        '/etc/hysteria/tls/server.crt','/etc/hysteria/tls/server.key',
        '/etc/systemd/system/xray.service','/etc/systemd/system/hysteria-server.service',
        '/var/lib/pnm/cores/xray/applied.env','/var/lib/pnm/cores/hysteria2/applied.env'))

    def resource_state():
        result={}
        for path in resources:
            require(not path.is_symlink(),'unexpected deletion recovery resource link')
            result[str(path)]=fingerprint(path) if path.exists() else None
        return result

    def units():
        return {unit:dict(line.split('=',1) for line in subprocess.check_output([
            'systemctl','show',unit,'--property=LoadState,ActiveState,MainPID'],
            text=True,timeout=10).splitlines() if line)
            for unit in ('xray.service','hysteria-server.service')}

    original=resource_state()
    original_units=units()
    original_nss=nss_state()
    transactions=Path('/var/lib/pnm/transactions')
    before=set(transactions.iterdir())
    with readonly_account_tool(logs,env,program) as account_fault:
        with readonly_deployment_commit(logs,env) as commit_fault:
            result=call('install-account-delete-refusal-'+program,
                ['install','--apply','--yes'],accepted=(70,))
    require(b'original_rc=73 recovery_rc=70' in result.stderr,
            'deletion failure lost initiating and recovery errors')
    created=set(transactions.iterdir())-before
    require(len(created)==1,'deletion failure created unexpected transactions')
    transaction=created.pop()
    events=[line.split('\t')[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
    require(events[-1]=='RECOVERY_REQUIRED' and events.count('COMMIT_INTENT')==1
            and 'ROLLBACK_BEGIN' in events and not any(event in events for event in
                ('COMMIT','ROLLED_BACK','ROLLBACK_COMPLETE')),
            'failed account deletion was falsely fully recovered')
    accounts=[line.split('\t') for line in (transaction/'accounts.tsv').read_text().splitlines()]
    remaining=(('user','hysteria'),('group','hysteria')) if program=='userdel' else (('group','hysteria'),)
    for kind,name in (('user','xray'),('group','xray'),('user','hysteria'),('group','hysteria')):
        require(['APPLIED',kind,name] in accounts,'deletion case lost creation ownership')
        require((['RESTORED',kind,name] not in accounts)==((kind,name) in remaining),
                'deletion failure receipt does not describe remaining identities')
        try:
            record=pwd.getpwnam(name) if kind=='user' else grp.getgrnam(name)
        except KeyError:
            require((kind,name) not in remaining,'owned unrecovered identity disappeared')
        else:
            require((kind,name) in remaining and (record.pw_uid if kind=='user' else record.gr_gid)>0,
                    'unexpected identity remains after deletion failure')
    current=resource_state()
    require({name:(value[:4] if value else None) for name,value in current.items()}=={
        name:(value[:4] if value else None) for name,value in original.items()}
        and units()==original_units,'account failure did not restore ordinary resource/service baseline')
    require(all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                for name in ('commit.env','commit-uncertain.env')),'account deletion failure left a marker')
    remaining_nss=nss_state()
    require(remaining_nss!=original_nss and all(remaining_nss[name][1:]==value[1:]
                for name,value in original_nss.items()),'remaining owned identity state is not explicit')
    passed.append('actual '+program+' refusal preserves original73 recovery70 and precise owned identity remainder')
    retained=receipt_state()
    before_units=units()
    def directory_state():
        result={}
        for name in ('/usr/local/etc/xray','/etc/hysteria','/etc/hysteria/tls',
                     '/usr/local/bin','/etc/systemd/system',
                     '/etc/systemd/system/multi-user.target.wants'):
            path=Path(name)
            require(not path.is_symlink(),'unexpected retained directory link')
            if path.exists():
                info=path.stat()
                result[name]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino,info.st_mtime_ns)
            else:
                result[name]=None
        return result
    retained_directories=directory_state()
    for label,arguments in (('writer',['apply','hysteria2']),
            ('links',['--json','node','links','--address','203.0.113.10']),
            ('show',['--json','node','show']),('check',['--json','check'])):
        refusal=call('account-recovery-pending-'+label,arguments,accepted=(70,))
        require(not refusal.stdout and b'Unresolved deployment transaction ' in refusal.stderr,
                'account recovery refusal disclosed output or has another cause')
    require(retained==receipt_state() and current==resource_state() and before_units==units()
            and retained_directories==directory_state(),
            'protected account recovery refusal changed retained state')
    passed.append('four fresh protected commands retain incomplete account recovery without output or mutation')
    (logs/'account-deletion-refusal.json').write_text(json.dumps({
        'program':program,'remaining_owned_identities':len(remaining),
        'ordinary_resources_recovered':True,'service_baseline_recovered':True,
        'full_recovery':False,'fresh_commands_blocked':4,
        'private_groups_retained_by_fixture_policy':program=='groupdel',
        'commit_refusal':commit_fault,'account_refusal':account_fault}))
