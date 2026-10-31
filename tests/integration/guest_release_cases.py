"""Finite release checks; called only after the mainflow guest approval guards."""
from pathlib import Path
import hashlib
import json
import re
import stat
import subprocess


def run_private(label, command, env, logs, check):
    result=subprocess.run(command,env=env,stdin=subprocess.DEVNULL,capture_output=True,timeout=300)
    (logs/(label+'.stdout')).write_bytes(result.stdout)
    (logs/(label+'.stderr')).write_bytes(result.stderr)
    check(result.returncode==0,label+' exit='+str(result.returncode))
    return result


def verify_runtime(runtime=Path('/usr/local/lib/pnm'), manifest=Path('/opt/pnm-source-hashes.json'), wrapper=Path('/usr/local/bin/pnm')):
    expected=json.loads(manifest.read_text())
    expected.pop('install.sh')
    actual={}
    for path in runtime.rglob('*'):
        if path.is_symlink():
            raise RuntimeError('installed runtime contains a symlink')
        if path.is_file():
            actual[str(path.relative_to(runtime))]=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual!=expected:
        raise RuntimeError('installed runtime differs from the approved source')
    if not wrapper.is_file() or wrapper.is_symlink() or wrapper.stat().st_mode & 0o022 or not wrapper.stat().st_mode & 0o111:
        raise RuntimeError('installed CLI wrapper is unsafe')


def prepare(env, logs, check, passed):
    check(not Path('/usr/local/lib/pnm').exists() and not Path('/usr/local/bin/pnm').exists(),
          'CLI delivery fixture is not fresh')
    candidate=Path('/opt/pnm-candidate-ref').read_text().strip()
    check(re.fullmatch('[0-9a-f]{40}',candidate) is not None,'release fixture requires a pinned candidate')
    run_private('cli-installer',['bash','/opt/pnm/install.sh'],dict(env,PNM_REF=candidate),logs,check)
    verify_runtime()
    version=run_private('installed-version',['/usr/local/bin/pnm','--version'],env,logs,check)
    check(Path('/opt/pnm/VERSION').read_text().strip().encode() in version.stdout,'installed CLI version mismatch')
    passed.append('actual install.sh delivers the pinned CLI wrapper and identical runtime')


def native_integrations(env, logs, check, passed):
    for label,command,variable,count in (
        ('native-systemd',['bash','/opt/pnm-native-suite/tests/integration/test_systemd_lifecycle.sh'],'PNM_RUN_SYSTEMD_TESTS',8),
        ('native-cores',['python3','-B','/opt/pnm-native-suite/tests/integration/test_real_cores.py'],'PNM_RUN_REAL_CORE_TESTS',10)):
        try:
            result=run_private(label,command,dict(env,**{variable:'1'},PNM_REAL_CORE_ASSETS='/opt/pnm-native-assets'),logs,check)
            check(('# passed='+str(count)+' failed=0').encode() in result.stdout,label+' incomplete checks')
        except RuntimeError as error:
            from guest_vm_boot import GuestAcceptanceFailure
            reason=str(error)
            if re.fullmatch(r'native-(systemd|cores) (exit=[0-9]{1,3}|incomplete checks)',reason) is None:
                reason='native suite assertion'
            summary={'stage':label,'reason':reason,'completed_suites':len(passed)}
            stdout=(logs/(label+'.stdout')).read_bytes() if (logs/(label+'.stdout')).exists() else b''
            stderr=(logs/(label+'.stderr')).read_bytes() if (logs/(label+'.stderr')).exists() else b''
            summary['error_categories']=[name for name,marker in (
                ('missing_file',b'No such file or directory'),('permission_denied',b'Permission denied'),
                ('missing_command',b'command not found'),('unbound_variable',b'unbound variable')) if marker in stderr]
            if label=='native-systemd':
                labels=re.findall(r"^run_test '([^']+)'",Path(command[-1]).read_text(),re.MULTILINE)
                summary['failed_cases']=[i+1 for i,name in enumerate(labels)
                    if ('not ok - '+name).encode() in stdout+stderr]
            raise GuestAcceptanceFailure(summary) from None
        passed.append(label+' existing private integration checks '+str(count)+'/0')


def observe(call, core_state, check, label):
    before={core:core_state(core) for core in ('xray','hysteria2')}
    receipts=Path('/var/lib/pnm/transactions')
    def receipt_state():
        state={}
        for path in (receipts,*receipts.rglob('*')):
            info=path.lstat()
            check(not path.is_symlink(),'unexpected transaction evidence symlink')
            digest=hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
            state[str(path)]=(digest,info.st_mode,info.st_uid,info.st_gid,info.st_ino,info.st_mtime_ns)
        return state
    evidence=receipt_state()
    private=[]
    for path in Path('/etc/pnm/secrets').glob('*.env'):
        for line in path.read_text().splitlines():
            key,sep,value=line.partition('=')
            if sep and value and (key.endswith('PRIVATE_KEY') or key.endswith('PASSWORD') or key.endswith('UUID')):
                private.append(value.encode())
    commands=(('status',['status']),('check',['check']),('resources',['check','--resources']),
              ('profile',['profile','show']),('recovery',['recovery','list']))
    documents={}
    for name,args in commands:
        result=call(label+'-'+name,['--json',*args],accepted=(0,1,2) if name in ('check','resources') else (0,))
        check(not any(secret in result.stdout+result.stderr for secret in private),'ordinary diagnostic exposes credentials')
        documents[name]=json.loads(result.stdout)
    desired=documents['profile']['desired']
    check(documents['status']['configured'] is True and documents['status']['desired_profile']==desired,
          'status differs from the persisted installed Profile')
    enabled={'dual':{'xray','hysteria2'},'reality':{'xray'},'hy2':{'hysteria2'}}[desired]
    for core in documents['status']['cores']:
        check(core['desired_enabled']==(core['id'] in enabled),'status reports the wrong desired Core policy')
    check(not documents['recovery']['writes_blocked'],'completed transactions still block writes')
    for tx in documents['recovery']['transactions']:
        result=call(label+'-inspect-'+tx['id'],['--json','recovery','inspect',tx['id']])
        check(not any(secret in result.stdout+result.stderr for secret in private),'recovery inspect exposes credentials')
        json.loads(result.stdout)
    for item in documents['check']['checks']:
        if before['xray']['active']=='inactive' and item['id'].startswith('xray'):
            check(item['status']!='FAIL','disabled Xray falsely fails diagnostics')
        if before['hysteria2']['active']=='inactive' and item['id'].startswith(('hysteria','hy2')):
            check(item['status']!='FAIL','disabled HY2 falsely fails diagnostics')
    check(before=={core:core_state(core) for core in before},'diagnostics changed Core state')
    check(evidence==receipt_state(),
          'diagnostics modified transaction evidence')


def finish(call, core_state, binding, check, passed, archive, resources):
    observe(call,core_state,check,'release-final')
    passed.append('actual status/resources/profile/recovery diagnostics are read-only and redact credentials')
    archive_hash=hashlib.sha256(archive.read_bytes()).hexdigest()
    for core in ('xray','hysteria2'):
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(peer)
        directory=Path('/var/backups/pnm')
        backups=set(directory.glob('*'))
        call('uninstall-'+core,['uninstall',core,'--yes'])
        created=set(directory.glob('*'))-backups
        check(len(created)==1,'uninstall lacks a distinct backup')
        backup=created.pop()
        check(stat.S_IMODE(backup.stat().st_mode)==0o600 and backup.stat().st_uid==0,
              'uninstall backup permissions are unsafe')
        check(b'CONTAINS SECRETS' in subprocess.check_output(['tar','-xOf',str(backup),'./MANIFEST.txt'],timeout=20),
              'uninstall backup is not identifiable')
        check(all(not Path(path).exists() for path in resources[core]),'uninstall retained owned Core resources')
        check(core_state(peer)==before,'uninstall changed the peer Core')
        binding(peer)
        unit='xray.service' if core=='xray' else 'hysteria-server.service'
        active=subprocess.check_output(['systemctl','show',unit,'--property=ActiveState','--value'],timeout=10)
        check(active.strip()==b'inactive','uninstall retained an active target service')
        passed.append('actual '+core+' uninstall preserves peer and a protected identifiable backup')
        if core=='xray':
            check(hashlib.sha256(archive.read_bytes()).hexdigest()==archive_hash,'trusted reset archive changed')
            call('restore-between-uninstall-cases',['restore',str(archive)])
            binding('xray');binding('hysteria2')
    verify_runtime()
