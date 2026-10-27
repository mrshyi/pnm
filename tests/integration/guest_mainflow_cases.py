from pathlib import Path
import base64
from datetime import datetime
import fcntl,hashlib,json,os,pwd,grp,re,secrets,signal,socket,stat,subprocess,sys
from urllib.parse import urlsplit,parse_qs
mapping=[int(x) for x in Path('/proc/self/uid_map').read_text().split()]
if sys.flags.optimize:
    raise SystemExit('enabled assertions required')
if os.geteuid()!=0:
    raise SystemExit(77)
if len(mapping)==3 and mapping[0]==0 and mapping[1]>0 and mapping[2]==65536:
    expected=json.loads(Path('/opt/pnm-boot-expected.json').read_text())
    assert all(os.stat('/proc/self/ns/'+n).st_ino!=v for n,v in expected['host_namespaces'].items())
    assert Path('/run/host/container-manager').read_text().strip()=='systemd-nspawn'
else:
    try:
        from guest_vm_boot import GuestRefusal, require_approved_vm
    except ImportError:
        raise SystemExit(77) from None
    try:
        require_approved_vm()
    except GuestRefusal:
        raise SystemExit(77) from None
logs=Path('/var/tmp/pnm-install-evidence')
logs.mkdir(mode=0o700)
os.umask(0o077)
passed=[]
stage='initial managed-resource baseline'
result={}
source_identity=None
ports={'xray':443,'hysteria2':8443}
default_sockets=[]
reused_accounts={}
env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','LANG':'C.UTF-8','TZ':'UTC'}
def check(condition,label):
    if not condition:
        raise RuntimeError(label)
def call(label,args,accepted=(0,),*,process_slot=None):
    (logs/'operation.json').write_text(json.dumps({'label':label,'state':'started'}))
    command=['bash','/opt/pnm/bin/pnm']+args
    if label=='install-apply' and scenario=='deployment-progress-readonly':
        command=['/usr/bin/unshare','--mount','--propagation','private',*command]
    # A CLI descendant can retain PIPE fds after Bash exits. Own a separate
    # session so timeout retires the whole command group with bounded waits.
    with subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,env=env,start_new_session=True) as process:
        if process_slot is not None:
            process_slot.append(process)
        timed_out=False
        try:
            stdout,stderr=process.communicate(timeout=300 if scenario=='deployment-inode-full' else 150)
        except subprocess.TimeoutExpired:
            timed_out=True
            for caught,limit in ((signal.SIGTERM,10),(signal.SIGKILL,5)):
                try:
                    os.killpg(process.pid,caught)
                except ProcessLookupError:
                    pass
                try:
                    stdout,stderr=process.communicate(timeout=limit)
                    break
                except subprocess.TimeoutExpired:
                    if caught==signal.SIGKILL:
                        raise RuntimeError(label+' command group could not retire') from None
        (logs/(label+'.stdout')).write_bytes(stdout)
        (logs/(label+'.stderr')).write_bytes(stderr)
        (logs/'operation.json').write_text(json.dumps({'label':label,'state':'timeout' if timed_out else 'finished'}))
        if timed_out or process.returncode not in accepted:
            # Journal entries may contain private configuration details. Retain
            # them only in this mode-0700 guest evidence directory, never stdout.
            try:
                diagnostic=subprocess.run(['journalctl','--no-pager','-n','120',
                    '-u','xray.service','-u','hysteria-server.service'],
                    capture_output=True,timeout=10)
                (logs/(label+'.service-journal')).write_bytes(diagnostic.stdout)
            except (OSError,subprocess.TimeoutExpired):
                pass # Diagnostics cannot replace the original command failure.
        check(not timed_out,label+' command timed out')
        check(process.returncode in accepted,label+' exit='+str(process.returncode))
        return subprocess.CompletedProcess(command,process.returncode,stdout,stderr)
def show(unit,field):
    return subprocess.check_output(['systemctl','show',unit,'--property='+field,'--value'],text=True,timeout=10).strip()
def fields(path):
    return dict(line.split('=',1) for line in Path(path).read_text().splitlines() if line and not line.startswith('#'))
def absent():
    if reused_accounts:
        check(reused_accounts=={path:fingerprint(path) for path in reused_accounts},
              'preexisting accounts changed before installation or after compensation')
    for name in ('xray','hysteria'):
        if reused_accounts:
            continue
        try:
            pwd.getpwnam(name)
        except KeyError:
            pass
        else:
            raise RuntimeError('unexpected preexisting managed identity')
        try:
            grp.getgrnam(name)
        except KeyError:
            pass
        else:
            raise RuntimeError('unexpected preexisting managed group')
    for name in ('/usr/local/bin/xray','/usr/local/bin/hysteria','/usr/local/etc/xray/config.json','/etc/hysteria/config.yaml','/etc/systemd/system/xray.service','/etc/systemd/system/hysteria-server.service'):
        check(not Path(name).exists() and not Path(name).is_symlink(),'unexpected managed resource')
def fingerprint(path: str | Path) -> tuple[str,int,int,int]:
    p=Path(path)
    st=p.stat()
    return (hashlib.sha256(p.read_bytes()).hexdigest(),st.st_mode,st.st_uid,st.st_gid)

def verify_source_snapshot(root: Path,manifest: Path) -> dict:
    expected=json.loads(manifest.read_text())
    actual={}
    for path in root.rglob('*'):
        if path.is_symlink():
            raise RuntimeError('guest source contains a symlink')
        if path.is_file():
            actual[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
    if not actual or actual!=expected:
        raise RuntimeError('guest source differs from the copied worktree snapshot')
    return {'files':len(actual),'manifest_sha256':hashlib.sha256(manifest.read_bytes()).hexdigest()}

def deployment_failure_cases() -> None:
    # Filter command discovery only within this guest process. No package or
    # system executable is removed, replaced or mocked.
    baseline_paths=('/etc/pnm/node.conf','/etc/pnm/versions.conf','/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')
    baseline={p:fingerprint(p) for p in baseline_paths}
    transactions=Path('/var/lib/pnm/transactions')
    before_transactions=set(transactions.iterdir())
    filtered=logs/'without-openssl'
    filtered.mkdir(mode=0o700)
    for folder in ('/usr/sbin','/usr/bin','/sbin','/bin'):
        for program in Path(folder).iterdir():
            link=filtered/program.name
            if program.name!='openssl' and program.is_file() and os.access(program,os.X_OK) and not link.exists():
                link.symlink_to(program)
    original_path=env['PATH']
    env['PATH']=str(filtered)
    try:
        refusal=call('missing-openssl',['install','--apply','--yes'],accepted=(2,))
    finally:
        env['PATH']=original_path
    check(b'TLS tools are unavailable' in refusal.stdout and b'openssl' in refusal.stdout,'preflight refusal has a different cause')
    absent()
    check(baseline=={p:fingerprint(p) for p in baseline_paths},'missing dependency changed configuration or identities')
    check(before_transactions==set(transactions.iterdir()),'missing dependency began a write transaction')
    passed.append('missing TLS dependency refuses before managed resource mutation')

    # A real unit start delay crosses the supported 30-second commit window.
    # This changes only a uniquely owned drop-in inside this disposable guest.
    delay_dir=Path('/etc/systemd/system/xray.service.d')
    check(not delay_dir.exists() and not delay_dir.is_symlink(),'unexpected delay directory')
    delay_dir.mkdir(mode=0o755)
    delay=delay_dir/'pnm-test-delay.conf'
    delay.write_text('[Service]\nExecStartPre=/bin/sleep 35\n')
    delay_policy=fingerprint(delay)
    subprocess.run(['systemctl','daemon-reload'],check=True,timeout=15,capture_output=True)
    directories=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray','/etc/hysteria','/etc/hysteria/tls','/usr/local/bin','/etc/systemd/system')
    def directory_state(path: str) -> tuple[int,int,int,int,int] | None:
        p=Path(path)
        if not p.exists():
            return None
        st=p.stat()
        return st.st_mode,st.st_uid,st.st_gid,st.st_dev,st.st_ino
    directory_baseline={p:directory_state(p) for p in directories}
    env['PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS']='30'
    try:
        call('deadline-install',['install','--apply','--yes'],accepted=(77,))
    finally:
        del env['PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS']
    absent()
    check(baseline=={p:fingerprint(p) for p in baseline_paths},'rollback changed baseline configuration or identities')
    check(directory_baseline=={p:directory_state(p) for p in directories},'rollback did not restore directory identity or metadata')
    check(fingerprint(delay)==delay_policy,'rollback changed the preexisting delay drop-in')
    for unit in ('xray.service','hysteria-server.service'):
        check(show(unit,'LoadState')=='not-found' and show(unit,'ActiveState')=='inactive' and show(unit,'MainPID')=='0','rollback left a managed service or process')
    for protocol,port in (('tcp',443),('udp',8443)):
        sockets=subprocess.check_output(['ss','-H','-lnt' if protocol=='tcp' else '-lnu'],text=True,timeout=10)
        check(not any(re.search(r':'+str(port)+r'\b',line) for line in sockets.splitlines()),'rollback left a managed listener')
    for core in ('xray','hysteria2'):
        check(not Path('/var/lib/pnm/cores/'+core+'/applied.env').exists(),'rollback retained applied promotion')
    created=set(transactions.iterdir())-before_transactions
    check(len(created)==1,'unexpected deployment transaction count')
    transaction=created.pop()
    events=[line.split('\t')[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
    check('ROLLBACK_COMPLETE' in events and events[-1]=='ROLLED_BACK' and 'RECOVERY_REQUIRED' not in events,'deployment compensation is incomplete')
    check(not (transaction/'commit.env').exists(),'failed deployment has a commit marker')
    deployments=list(Path('/var/lib/pnm/deployments').iterdir())
    check(len(deployments)==1,'unexpected deployment receipt count')
    journal=(deployments[0]/'journal.tsv').read_text()
    check('\tPHASE_DONE\tpost-health\n' in journal,'failure did not follow actual dual-Core post-health')
    apply_receipts=list(Path('/var/lib/pnm/apply').iterdir())
    check(len(apply_receipts)==1,'unexpected apply receipt count')
    receipt=apply_receipts[0]
    metadata=fields(receipt/'metadata.env')
    deadline=int(metadata['COMMIT_DEADLINE_EPOCH'])
    check(deadline-int(metadata['CREATED_EPOCH'])==30,'commit window differs from fixture')
    audit=[line.split('\t') for line in (receipt/'journal.tsv').read_text().splitlines()]
    names=[row[1] for row in audit]
    failures=[row for row in audit if row[1]=='APPLY_FAILED']
    check(len(failures)==1 and failures[0][2]=='rc=77','apply failure cause differs from fixture')
    check(names.index('APPLY_DONE')<names.index('HEALTH_CHECK')<names.index('APPLY_FAILED') and 'COMMIT' not in names,'apply failed before the deadline gate')
    check(int(datetime.fromisoformat(failures[0][0].replace('Z','+00:00')).timestamp())>deadline,'apply failed before the recorded deadline')
    check(not (receipt/'commit.env').exists(),'failed apply receipt has a commit pointer')
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='no','rollback left node committed')
    delay.unlink()
    delay_dir.rmdir()
    subprocess.run(['systemctl','daemon-reload'],check=True,timeout=15,capture_output=True)
    passed.append('late deployment deadline restores live services resources accounts and commit state')

def restore_start_failure_case(core_state, binding, links_ready, all_paths, archive, backup_resources,
                               *, publication_fault=False) -> None:
    from guest_start_fault import start_fault
    desired=Path('/etc/pnm/node.conf')
    original=desired.read_text()
    changed=original.replace('XRAY_TARGET=edge.example.net:443','XRAY_TARGET=recovery.example.net:443')
    check(changed!=original,'restore failure fixture did not change desired target')
    desired.write_text(changed)
    call('apply-before-restore-failure',['apply','xray'])
    before_resources={p:fingerprint(p) for p in all_paths}
    check(before_resources!=backup_resources,'restore failure candidate equals the original generation')
    before_services={core:core_state(core) for core in ('xray','hysteria2')}
    directory_paths=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray','/etc/hysteria','/etc/hysteria/tls')
    def directory_state(path: str) -> tuple[int,int,int,int,int]:
        info=Path(path).stat()
        return info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino
    before_directories={p:directory_state(p) for p in directory_paths}
    identities={p:fingerprint(p) for p in ('/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')}
    transactions=set(Path('/var/lib/pnm/transactions').iterdir())
    check(hashlib.sha256(archive.read_bytes()).hexdigest()==(logs/'trusted-backup.sha256').read_text(),
          'trusted archive changed before failure test')
    if publication_fault:
        from guest_io_fault import readonly_publication
        context=readonly_publication(logs,env,'/etc/hysteria/config.yaml')
    else:
        context=start_fault('hysteria2')
    with context as fault:
        result=call('restore-publication-failure' if publication_fault else 'restore-start-failure',
                    ['restore',str(archive)],accepted=(73 if publication_fault else 1,))
        (logs/'restore-start-failure-state.json').write_text(json.dumps({
            'fault':fault,'services':{core:{field:show(unit,field) for field in
                ('ActiveState','SubState','Result','MainPID','UnitFileState')}
                for core,unit in (('xray','xray.service'),('hysteria2','hysteria-server.service'))}}))
        error='Core restore failed (rc='+('73' if publication_fault else '1')+'); prior resources and service policy were restored.'
        check(error.encode() in result.stderr,
              'restore failure or recovery cause differs from fixture')
        if not publication_fault:
            check(fault['attempts']==2 and fault['rejected']==1,'restore did not execute failure and compensation starts')
        check(before_resources=={p:fingerprint(p) for p in all_paths},'failed restore did not recover original resources')
        check(before_directories=={p:directory_state(p) for p in directory_paths},'failed restore did not recover directory metadata/identity')
        check(identities=={p:fingerprint(p) for p in identities},'restore compensation changed service identities')
        for core in ('xray','hysteria2'):
            binding(core)
            check(core_state(core)['invocation']!=before_services[core]['invocation'],'restore compensation retained stale invocation')
        links_ready('links-after-restore-compensation')
        health=json.loads(call('check-after-restore-compensation',['--json','check'],accepted=(0,1,2)).stdout)
        check(not [x for x in health['checks'] if x['status'] in ('FAIL','UNKNOWN') and x['id']!='time_sync'],
              'restore compensation left failed local health')
        created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
        check(len(created)==1,'unexpected failed restore transaction count')
        transaction=created.pop()
        journal=(transaction/'journal.tsv').read_text().splitlines()
        events=[line.split('\t')[1] for line in journal]
        writes=events.count('WRITE')
        check((0<writes<len(all_paths) if publication_fault else writes>=12) and 'ROLLBACK_COMPLETE' in events
              and events[-1]=='ROLLED_BACK' and 'RECOVERY_REQUIRED' not in events,
              'restore did not fail after publication with completed compensation')
        check('COMMIT' not in events and not (transaction/'commit.env').exists()
              and not (transaction/'commit.env').is_symlink(),'failed restore was committed')
    if publication_fault:
        check(fault['probe_errno']==30 and fault['move_rc']==1 and fault['readonly_error']
              and fault['mount_removed'] and fault['private_namespace'],'partial restore has no real retired EROFS refusal')
        rows=[line.split('\t') for line in (transaction/'changes.tsv').read_text().splitlines()]
        node_path=base64.b64encode(b'/etc/pnm/node.conf').decode('ascii')
        node_writes=[row for row in rows if len(row)==6 and row[0]=='APPLIED' and row[2]==node_path]
        check(len(node_writes)==1 and node_writes[0][5]==backup_resources['/etc/pnm/node.conf'][0]
              and node_writes[0][5]!=before_resources['/etc/pnm/node.conf'][0],
              'restore did not publish the distinct archived node before the failure')
        target_path=base64.b64encode(b'/etc/hysteria/config.yaml').decode('ascii')
        check(any(len(row)==6 and row[0]=='INTENT' and row[2]==target_path for row in rows)
              and not any(len(row)==6 and row[0]=='APPLIED' and row[2]==target_path for row in rows),
              'restore failure did not precede target publication')
        (logs/'restore-partial-publication.json').write_text(json.dumps({'ordinary_resources':len(all_paths),
            'published_before_failure':writes,'changed_node_published':True,
            'failed_target_unpublished':True,'refusal':fault}))
    passed.append('actual partial restore EROFS recovers both original generations' if publication_fault else
                  'actual HY2 startup failure after restore publication recovers both original generations')
    check(hashlib.sha256(archive.read_bytes()).hexdigest()==(logs/'trusted-backup.sha256').read_text(),
          'trusted archive changed before restore retry')
    call('restore-retry-after-start-failure',['restore',str(archive)])
    check(backup_resources=={p:fingerprint(p) for p in all_paths},'restore retry did not reproduce trusted archive resources')
    for core in ('xray','hysteria2'):
        binding(core)
    links_ready('links-restored-after-start-failure')
    passed.append('actual restore retries successfully after completed publication-failure compensation' if publication_fault else
                  'actual restore retries successfully after completed startup-failure compensation')


def runtime_evidence_cases(core_state, binding, links_ready) -> None:
    units={'xray':'xray.service','hysteria2':'hysteria-server.service'}
    uri_keys={'xray':'xray_vless_reality','hysteria2':'hysteria2'}
    for core,unit in units.items():
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(core)
        peer_before=core_state(peer)
        subprocess.run(['systemctl','restart',unit],check=True,timeout=20,capture_output=True)
        external=core_state(core)
        check(external['invocation']!=before['invocation'] and external['resources']==before['resources']
              and external['applied']==before['applied'],'external restart changed resources or failed to replace invocation')

        def unconfirmed(label: str) -> None:
            links=json.loads(call(label,['--json','node','links','--address','203.0.113.10']).stdout)
            check(links[core+'_status']!='ready' and not links.get(uri_keys[core])
                  and links[peer+'_status']=='ready','unconfirmed restart disclosed an unsafe URI or suppressed peer')
            report=json.loads(call(label+'-show',['--json','node','show'],accepted=(78,)).stdout)
            check(report['runtime'][core+'_applied_state']!='confirmed'
                  and report['runtime'][core+'_link_status']!='ready'
                  and report['runtime'][peer+'_link_status']=='ready','node show promoted unknown runtime evidence')

        unconfirmed('links-external-'+core)
        call('restart-unconfirmed-'+core,['restart',core])
        restarted=core_state(core)
        check(restarted['invocation']!=external['invocation'] and restarted['applied']==before['applied']
              and restarted['resources']==before['resources'],
              'PNM restart promoted stale applied evidence')
        unconfirmed('links-unconfirmed-restart-'+core)
        check(core_state(peer)==peer_before,'external/repeated restart changed peer Core')
        passed.append('actual '+core+' external and unconfirmed restart withhold stale evidence and preserve peer')

        call('apply-reconfirm-'+core,['apply',core])
        binding(core)
        links_ready('links-reconfirmed-'+core)
        check(core_state(peer)==peer_before,'validated reconfirmation changed peer Core')
        passed.append('actual '+core+' validated apply rebuilds the confirmed runtime binding')

    before={core:core_state(core) for core in units}
    transactions=set(Path('/var/lib/pnm/transactions').iterdir())
    lock=Path('/run/lock/pnm.lock')
    fd=os.open(lock,os.O_RDWR|os.O_NOFOLLOW)
    try:
        info=os.fstat(fd)
        check(stat.S_ISREG(info.st_mode) and info.st_uid==0,'unexpected PNM lock object')
        fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        probe=os.open(lock,os.O_RDWR|os.O_NOFOLLOW)
        try:
            try:
                fcntl.flock(probe,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise RuntimeError('independent lock probe did not observe the held lock')
        finally:
            os.close(probe)
        writer=call('contended-apply',['apply','xray'],accepted=(73,))
        reader=call('contended-links',['--json','node','links','--address','203.0.113.10'],accepted=(73,))
        check(not writer.stdout and not reader.stdout,'contended operation emitted output or credentials')
        check(before=={core:core_state(core) for core in units},'contended operation changed a Core')
        check(transactions==set(Path('/var/lib/pnm/transactions').iterdir()),'contended operation began a transaction')
    finally:
        fcntl.flock(fd,fcntl.LOCK_UN)
        os.close(fd)
    call('apply-after-contention',['apply','xray'])
    binding('xray')
    links_ready('links-after-contention')
    check(core_state('hysteria2')==before['hysteria2'],'post-contention apply changed peer Core')
    passed.append('real cross-process lock refuses writers and protected readers then releases without leakage')

try:
    stage='guest source identity'
    source_identity=verify_source_snapshot(Path('/opt/pnm'),Path('/opt/pnm-source-hashes.json'))
    absent()
    passed.append('fresh guest has no managed accounts or resources')
    scenario=Path('/opt/pnm-test-scenario').read_text().strip()
    update_interruptions=('core-update-term','core-update-sigkill-xray','core-update-sigkill-hysteria2',
                          'core-rollback-sigkill-xray','core-rollback-sigkill-hysteria2')
    restore_interruptions=('restore-term','restore-sigkill-xray','restore-sigkill-hysteria2')
    publication_cases=('core-publication-previous','core-publication-metadata','core-publication-applied')
    account_deletions=('account-deletion-userdel','account-deletion-groupdel')
    check(scenario in ('lifecycle','deployment-failure','core-update','core-update-failure','configured-ports','restore-publication',
          'runtime-evidence','restore-failure','startup-readiness','core-recovery-failure-xray',
          'core-recovery-failure-hysteria2','restore-recovery-failure','tls-access','account-reuse',
          'core-interruption','core-interruption-hysteria2','restart-readiness','dependency-refusal',
          'deployment-startup-failure','deployment-listener-failure','deployment-term',
          'deployment-sigkill','deployment-commit-readonly','deployment-late-sigkill',
          'deployment-progress-readonly','deployment-rename-readonly','deployment-marker-failures','deployment-space-full',
          'deployment-inode-full',
          'deployment-acquisition-failures','deployment-version-failures',
          'account-creation-failure')+update_interruptions+restore_interruptions+publication_cases+account_deletions,'unknown guest scenario')
    if scenario=='account-reuse':
        from guest_account_cases import prepare_accounts, require_preserved
        reused_accounts=prepare_accounts()
        passed.append('guest-only valid preexisting service identities establish a fixed NSS baseline')
    if scenario=='configured-ports':
        ports={'xray':10443,'hysteria2':18443}
        for kind,port in ((socket.SOCK_STREAM,443),(socket.SOCK_DGRAM,8443)):
            fixture=socket.socket(socket.AF_INET,kind)
            default_sockets.append(fixture)
            fixture.bind(('127.0.0.1',port))
            if kind==socket.SOCK_STREAM:
                fixture.listen(1)
    stage='node init and validate'
    pins=json.loads(Path('/opt/pnm-test-versions.json').read_text())
    call('node-init',['node','init','--region','test','--address','203.0.113.10','--timezone','UTC',
        '--server-name','www.cloudflare.com','--target','www.cloudflare.com:443','--hy2-server-name','guest.invalid',
        '--xray-version',pins['xray']['version'],'--xray-sha256',pins['xray']['sha256'],
        '--hy2-version',pins['hysteria2']['version'],'--hy2-sha256',pins['hysteria2']['sha256'],
        '--xray-port',str(ports['xray']),'--hy2-port',str(ports['hysteria2'])])
    call('node-validate',['node','validate'])
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='no','node configured before apply')
    passed.append('actual CLI initializes and validates an uncommitted node')
    stage='installation preview'
    call('install-preview',['install','--dry-run'])
    absent()
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='no','preview committed node state')
    passed.append('installation preview preserves original accounts and leaves runtime resources absent')
    if scenario=='configured-ports':
        stage='configured-port conflict refusal'
        baseline_paths=('/etc/pnm/node.conf','/etc/pnm/versions.conf','/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')
        baseline={p:fingerprint(p) for p in baseline_paths}
        transactions=set(Path('/var/lib/pnm/transactions').iterdir())
        with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as tcp, socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as udp:
            tcp.bind(('127.0.0.1',ports['xray']))
            tcp.listen(1)
            udp.bind(('127.0.0.1',ports['hysteria2']))
            refusal=call('configured-port-conflict',['install','--apply','--yes'],accepted=(2,))
        check(b'Required TCP/10443 is already in use' in refusal.stdout and b'Required UDP/18443 is already in use' in refusal.stdout,'port refusal has another cause')
        absent()
        check(baseline=={p:fingerprint(p) for p in baseline_paths},'port conflict changed configuration or identities')
        check(transactions==set(Path('/var/lib/pnm/transactions').iterdir()),'port conflict began publication')
        passed.append('configured port conflicts refuse before managed writes')
    if scenario in ('deployment-failure','account-reuse'):
        stage='actual dependency refusal and late deployment compensation'
        deployment_failure_cases()
        if reused_accounts:
            require_preserved(reused_accounts)
    if scenario=='dependency-refusal':
        stage='actual installation dependency refusal matrix'
        from guest_preflight_cases import run_dependencies
        run_dependencies(logs,env,call,absent,passed)
    if scenario in account_deletions:
        stage='actual account deletion refusal retains incomplete recovery'
        from guest_account_cases import run_deletion_failure
        run_deletion_failure(logs,env,call,passed,program=scenario.rsplit('-',1)[1])
        result={'passed':True,'checks':passed,'expected_recovery_required':True,'mainflow_completed':False}
        raise SystemExit(0)
    if scenario=='account-creation-failure':
        stage='actual account creation refusal and compensation'
        from guest_account_cases import run_creation_failures
        run_creation_failures(logs,env,call,absent,passed)
    if scenario=='deployment-late-sigkill':
        stage='actual publisher post-rename SIGKILL'
        from guest_commit_signal import run_late_interruption
        run_late_interruption(logs,env,call,passed)
        result={'passed':True,'checks':passed,'expected_recovery_required':True,'mainflow_completed':False}
        raise SystemExit(0)
    if scenario in ('deployment-startup-failure','deployment-listener-failure','deployment-term','deployment-sigkill','deployment-commit-readonly','deployment-rename-readonly'):
        stage='actual first-deployment Core startup failure compensation'
        from guest_deployment_cases import run_startup_failures
        failure={'deployment-startup-failure':'start','deployment-listener-failure':'listener',
                 'deployment-term':'term','deployment-sigkill':'kill','deployment-commit-readonly':'commit',
                 'deployment-rename-readonly':'rename'}[scenario]
        run_startup_failures(logs,call,absent,passed,failure=failure,env=env)
        if scenario=='deployment-sigkill':
            # This fixture intentionally retains an interrupted deployment.
            # Its protected result is still written by the shared finally block.
            result={'passed':True,'checks':passed,'expected_recovery_required':True,'mainflow_completed':False}
            raise SystemExit(0)
    if scenario in ('deployment-acquisition-failures','deployment-version-failures'):
        stage='actual first-install acquisition failures and compensation'
        from guest_acquisition_cases import run_acquisition
        run_acquisition(logs,env,call,absent,passed,include_versions=scenario=='deployment-version-failures')
    if scenario in ('deployment-marker-failures','deployment-space-full','deployment-inode-full'):
        from guest_deployment_cases import run_startup_failures
        failures=(('space-pending','space') if scenario=='deployment-space-full' else
                  ('inode-pending','inode') if scenario=='deployment-inode-full' else ('create','write','rename'))
        for failure in failures:
            stage='actual marker '+failure+' refusal and compensation'
            run_startup_failures(logs,call,absent,passed,failure=failure,env=env)
    stage='installation apply'
    if scenario=='deployment-progress-readonly':
        from guest_commit_progress import readonly_committed_progress, verify_committed_progress
        with readonly_committed_progress(logs,env) as observed:
            installed=call('install-apply',['install','--apply','--yes'])
        verify_committed_progress(observed,installed,passed)
    else:
        call('install-apply',['install','--apply','--yes'])
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='yes','successful install lacks committed node state')
    for protocol,port in (('tcp',ports['xray']),('udp',ports['hysteria2'])):
        observed=subprocess.check_output(['ss','-H','-lnt' if protocol=='tcp' else '-lnu'],text=True,timeout=10)
        check(any(re.search(r':'+str(port)+r'\b',line) for line in observed.splitlines()),'actual configured Core listener is absent')
    passed.append('real installation applies both Cores and commits node state')
    stage='actual account and process identity'
    users={}
    for name,unit in (('xray','xray.service'),('hysteria','hysteria-server.service')):
        record=pwd.getpwnam(name)
        check(record.pw_uid>0 and record.pw_gid>0 and record.pw_dir=='/nonexistent' and record.pw_shell=='/usr/sbin/nologin','service account policy mismatch')
        check(grp.getgrgid(record.pw_gid).gr_name==name,'service primary group mismatch')
        check(show(unit,'ActiveState')=='active' and show(unit,'UnitFileState')=='enabled','service is not active and enabled')
        check(show(unit,'User')==name,'unit user mismatch')
        pid=int(show(unit,'MainPID'))
        proc=Path('/proc/'+str(pid)+'/status').read_text()
        check('Uid:\t'+('\t'.join([str(record.pw_uid)]*4)) in proc,'actual Core identity mismatch')
        check('Gid:\t'+('\t'.join([str(record.pw_gid)]*4)) in proc,'actual Core primary group mismatch')
        check('NoNewPrivs:\t1' in proc,'actual Core can gain privileges')
        cap=next(line.split()[1] for line in proc.splitlines() if line.startswith('CapEff:'))
        check(int(cap,16)==(1024 if name=='xray' else 0),'actual Core capability mismatch')
        users[name]=record.pw_uid
    check(users['xray']!=users['hysteria'],'Core identities overlap')
    passed.append('distinct real service accounts run both enabled Cores with bounded privileges')
    stage='applied bindings'
    for core,unit,path in (('xray','xray.service','/usr/local/etc/xray/config.json'),('hysteria2','hysteria-server.service','/etc/hysteria/config.yaml')):
        record=fields('/var/lib/pnm/cores/'+core+'/applied.env')
        check(record['CONFIG_SHA256']==hashlib.sha256(Path(path).read_bytes()).hexdigest(),'applied digest mismatch')
        check(record['SERVICE_INVOCATION_ID']==show(unit,'InvocationID'),'applied invocation mismatch')
    passed.append('both applied records match real configuration bytes and service invocations')
    stage='production links'
    links=json.loads(call('node-links',['--json','node','links','--address','203.0.113.10']).stdout)
    check(links['xray_status']=='ready' and links['hysteria2_status']=='ready','real link readiness gate failed')
    check(links['xray_vless_reality'].startswith('vless://'),'REALITY link missing')
    check(urlsplit(links['xray_vless_reality']).port==ports['xray'] and urlsplit(links['hysteria2']).port==ports['hysteria2'],'client URI port differs from configured listener')
    pin=parse_qs(urlsplit(links['hysteria2']).query)['pinSHA256'][0]
    secret=fields('/etc/pnm/secrets/hysteria.env')
    der=subprocess.check_output(['openssl','x509','-in',secret['HY2_TLS_CERT_PATH'],'-outform','DER'],timeout=10)
    check(re.fullmatch('[0-9a-f]{64}',pin) is not None and pin==hashlib.sha256(der).hexdigest(),'actual installed HY2 URI fingerprint mismatch')
    passed.append('production readiness gates emit both URIs and the installed certificate DER pin')
    stage='Core health diagnostics'
    report=json.loads(call('check',['--json','check'],accepted=(0,1,2)).stdout)
    checks={item['id']:item['status'] for item in report['checks']}
    for key in ('configuration','xray','hysteria2','xray_runtime_config','hysteria2_runtime_config','hysteria_tls','hysteria_tls_permissions'):
        check(checks.get(key)=='OK','Core diagnostic failed: '+key)
    unexpected=[key for key,value in checks.items() if value in ('FAIL','UNKNOWN') and key!='time_sync']
    check(not unexpected,'unexpected non-clock diagnostic failures')
    passed.append('real Core/configuration/TLS/applied health diagnostics are OK')

    resources={
      'xray':('/usr/local/bin/xray','/usr/local/etc/xray/config.json','/etc/pnm/secrets/reality.env','/etc/systemd/system/xray.service'),
      'hysteria2':('/usr/local/bin/hysteria','/etc/hysteria/config.yaml','/etc/pnm/secrets/hysteria.env','/etc/hysteria/tls/server.crt','/etc/hysteria/tls/server.key','/etc/systemd/system/hysteria-server.service')}
    units={'xray':'xray.service','hysteria2':'hysteria-server.service'}
    configs={'xray':'/usr/local/etc/xray/config.json','hysteria2':'/etc/hysteria/config.yaml'}
    def core_state(core):
        unit=units[core]
        return {'invocation':show(unit,'InvocationID'),'pid':show(unit,'MainPID'),
          'active':show(unit,'ActiveState'),'enabled':show(unit,'UnitFileState'),
          'resources':{p:fingerprint(p) for p in resources[core]},
          'applied':fingerprint('/var/lib/pnm/cores/'+core+'/applied.env')}
    def binding(core):
        check(show(units[core],'ActiveState')=='active' and show(units[core],'UnitFileState')=='enabled','Core health policy mismatch')
        record=fields('/var/lib/pnm/cores/'+core+'/applied.env')
        check(record['CONFIG_SHA256']==hashlib.sha256(Path(configs[core]).read_bytes()).hexdigest(),'lifecycle applied digest mismatch')
        check(record['SERVICE_INVOCATION_ID']==show(units[core],'InvocationID'),'lifecycle applied invocation mismatch')
    def links_ready(label):
        data=json.loads(call(label,['--json','node','links','--address','203.0.113.10']).stdout)
        check(data['xray_status']=='ready' and data['hysteria2_status']=='ready','post-operation links not ready')
    stage='repeat installation refusal'
    baseline={c:core_state(c) for c in units}
    fixed={p:fingerprint(p) for p in ('/etc/pnm/node.conf','/etc/pnm/versions.conf','/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')}
    call('repeat-install',['install','--apply','--yes'],accepted=(2,))
    check(baseline=={c:core_state(c) for c in units},'repeat install changed Core state')
    check(fixed=={p:fingerprint(p) for p in fixed},'repeat install changed configuration or identities')
    passed.append('repeat installation refuses without changing either Core or identities')
    for core in units:
        stage='standalone restart '+core
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(core)
        peer_before=core_state(peer)
        call('restart-'+core,['restart',core])
        after=core_state(core)
        check(before['invocation']!=after['invocation'] and before['pid']!=after['pid'],'restart did not replace actual process')
        check(before['resources']==after['resources'],'restart changed managed resources')
        check(core_state(peer)==peer_before,'restart changed peer Core')
        binding(core)
        links_ready('links-restart-'+core)
        passed.append('actual '+core+' restart refreshes applied binding and preserves peer Core')
    for core in units:
        stage='desired configuration and apply '+core
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(core)
        peer_before=core_state(peer)
        if core=='xray':
            p=Path('/etc/pnm/node.conf')
            original=p.read_text()
            # HY2 masquerade also uses XRAY_SERVER_NAME; change only the
            # Xray-specific target when asserting independent peer readiness.
            changed=original.replace('XRAY_TARGET=www.cloudflare.com:443','XRAY_TARGET=edge.example.net:443')
        else:
            p=Path('/etc/pnm/secrets/hysteria.env')
            original=p.read_text()
            changed=re.sub(r'(?m)^HY2_AUTH_PASSWORD=.+$', 'HY2_AUTH_PASSWORD='+secrets.token_hex(24),original)
        check(changed!=original,'desired fixture edit did not change data')
        p.write_text(changed)
        data=json.loads(call('links-drift-'+core,['--json','node','links','--address','203.0.113.10'],accepted=(0,1,2,78)).stdout)
        status='xray_status' if core=='xray' else 'hysteria2_status'
        peer_status='hysteria2_status' if core=='xray' else 'xray_status'
        check(data[status]!='ready' and data[peer_status]=='ready','desired drift did not isolate affected link')
        if core=='xray':
            # Establish that the edited fixture itself is accepted by the real
            # Core. Keep its secret-bearing candidate/output in protected logs.
            candidate=json.loads(Path(configs[core]).read_text())
            candidate['inbounds'][0]['streamSettings']['realitySettings']['dest']=fields('/etc/pnm/node.conf')['XRAY_TARGET']
            for name in ('candidate','candidate.json'):
                path=logs/name
                path.write_text(json.dumps(candidate))
                probe=subprocess.run(['/usr/local/bin/xray','run','-test','-config',str(path)],capture_output=True,timeout=15)
                (logs/(name+'.validation')).write_bytes(probe.stdout+probe.stderr)
                (logs/(name+'.exit')).write_text(str(probe.returncode))
        call('apply-'+core,['apply',core])
        after=core_state(core)
        check(before['invocation']!=after['invocation'] and before['resources'][configs[core]]!=after['resources'][configs[core]],'apply did not publish and activate changed configuration')
        check(core_state(peer)==peer_before,'apply changed peer Core')
        binding(core)
        links_ready('links-apply-'+core)
        passed.append('actual '+core+' apply activates desired change and preserves peer Core')
    stage='protected backup and verified restore'
    all_paths=('/etc/pnm/node.conf','/etc/pnm/versions.conf')+tuple(p for c in units for p in resources[c])
    backup_resources={p:fingerprint(p) for p in all_paths}
    archive=logs/'trusted-backup.tar.gz'
    call('backup',['backup',str(archive)])
    check(archive.stat().st_uid==0 and archive.stat().st_mode&0o777==0o600,'backup is not protected')
    trusted_digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    (logs/'trusted-backup.sha256').write_text(trusted_digest)
    p=Path('/etc/pnm/node.conf')
    p.write_text(p.read_text().replace('XRAY_TARGET=edge.example.net:443','XRAY_TARGET=second.example.net:443'))
    call('apply-after-backup',['apply','xray'])
    check(fingerprint(configs['xray'])!=backup_resources[configs['xray']],'post-backup fixture did not change runtime')
    check(hashlib.sha256(archive.read_bytes()).hexdigest()==(logs/'trusted-backup.sha256').read_text(),'trusted archive provenance changed')
    before={c:core_state(c) for c in units}
    call('restore',['restore',str(archive)])
    check(backup_resources=={p:fingerprint(p) for p in all_paths},'restore did not reproduce original resource bytes or metadata')
    for core in units:
        binding(core)
        check(before[core]['invocation']!=show(units[core],'InvocationID'),'restore did not activate restored Core')
    links_ready('links-restored')
    final_checks={item['id']:item['status'] for item in json.loads(call('check-restored',['--json','check'],accepted=(0,1,2)).stdout)['checks']}
    check(not [k for k,v in final_checks.items() if v in ('FAIL','UNKNOWN') and k!='time_sync'],'restored diagnostics not healthy')
    passed.append('protected trusted backup restores all resources and real applied bindings')
    update_interrupted=False
    if scenario in ('core-update','core-update-failure','core-recovery-failure-xray','core-recovery-failure-hysteria2')+update_interruptions+publication_cases:
        stage='actual distinct-version Core update and rollback'
        from guest_update_cases import run_updates
        interruption='none'
        if scenario=='core-update-term':
            interruption='term'
        elif scenario in update_interruptions:
            operation,core=scenario.removeprefix('core-').split('-sigkill-')
            interruption='kill-'+operation+'-'+core
        interrupted=run_updates(logs,env,call,core_state,binding,links_ready,passed,
                    inject_start_failure=scenario=='core-update-failure',
                    recovery_failure_core=scenario.rsplit('-',1)[-1] if scenario.startswith('core-recovery-failure-') else None,
                    interruption=interruption,
                    publication_fault=scenario.rsplit('-',1)[-1] if scenario in publication_cases else None)
        if interrupted is not None:
            from guest_recovery_cases import require_commands_blocked
            peer='hysteria2' if interrupted['core']=='xray' else 'xray'
            require_commands_blocked(call,core_state,peer,passed,
                operation='core-'+interrupted['operation']+'-'+interrupted['core'])
            update_interrupted=True
    if scenario=='configured-ports':
        check(len(default_sockets)==2 and all(fixture.fileno()>=0 and fixture.getsockname()==('127.0.0.1',port)
              for fixture,port in zip(default_sockets,(443,8443))), 'unrelated default listeners changed')
        passed.append('unrelated default listeners survive the complete custom-port lifecycle')
    if scenario=='runtime-evidence':
        stage='external restart and real consistency lock'
        runtime_evidence_cases(core_state,binding,links_ready)
    if scenario in ('restore-failure','restore-publication'):
        stage='actual restore publication failure compensation' if scenario=='restore-publication' else 'actual restore startup failure compensation'
        restore_start_failure_case(core_state,binding,links_ready,all_paths,archive,backup_resources,
                                   publication_fault=scenario=='restore-publication')
    if scenario=='startup-readiness':
        stage='actual delayed Core listener readiness'
        from guest_readiness_cases import run_readiness
        run_readiness(logs,env,core_state,show,passed)
    if scenario=='restart-readiness':
        stage='actual ordinary restart with delayed Core listeners'
        from guest_readiness_cases import run_restart_readiness
        run_restart_readiness(logs,call,core_state,binding,links_ready,passed)
    if scenario=='restore-recovery-failure':
        stage='actual restore service recovery failure'
        from guest_recovery_cases import run_restore_recovery_failure
        run_restore_recovery_failure(logs,call,core_state,binding,all_paths,archive,passed)
    if scenario=='tls-access':
        stage='actual managed-account TLS access failures'
        from guest_tls_access import run_tls_access
        run_tls_access(logs,env,call,core_state,binding,links_ready,passed)
    if scenario=='account-reuse':
        stage='preexisting account preservation after actual lifecycle'
        require_preserved(reused_accounts)
        passed.append('dependency refusal, late rollback and complete real lifecycle preserve preexisting identities without ownership claims')
    if scenario in ('core-interruption','core-interruption-hysteria2'):
        stage='actual TERM and SIGKILL during standalone restart'
        from guest_signal_cases import run_interruptions
        run_interruptions(logs,call,core_state,binding,links_ready,passed,
                          core='hysteria2' if scenario.endswith('-hysteria2') else 'xray')
    if scenario in restore_interruptions:
        stage='actual trusted restore process interruption'
        from guest_signal_cases import run_restore_interruptions
        run_restore_interruptions(logs,call,core_state,binding,links_ready,all_paths,archive,
            backup_resources,passed,hard_core=scenario.rsplit('-',1)[-1] if '-sigkill-' in scenario else None)
    restore_interrupted=scenario.startswith('restore-sigkill-')
    verify_source_snapshot(Path('/opt/pnm'),Path('/opt/pnm-source-hashes.json'))
    result={'passed':True,'checks':passed,'clock_diagnostic':checks.get('time_sync'),'uids_distinct':True,
            'mainflow_completed':True,
            'update_matrix_completed':not update_interrupted if scenario in update_interruptions else None,
            'restore_matrix_completed':not restore_interrupted if scenario in restore_interruptions else None,
            'expected_recovery_required':update_interrupted or restore_interrupted or scenario.startswith('core-recovery-failure-')
            or scenario in ('restore-recovery-failure','core-interruption','core-interruption-hysteria2')}
except Exception as error:
    result={'passed':False,'checks':passed,'stage':stage,'error_class':type(error).__name__}
    if isinstance(error,RuntimeError):
        result['reason']=str(error)
finally:
    result['source_identity']=source_identity
    for fixture in default_sockets:
        fixture.close()
    path=Path('/var/tmp/pnm-install-result.json')
    with path.open('x') as stream:
        json.dump(result,stream)
raise SystemExit(0 if result['passed'] else 1)
