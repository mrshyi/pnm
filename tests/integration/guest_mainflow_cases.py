from pathlib import Path
import hashlib,json,os,pwd,grp,re,secrets,signal,subprocess,sys
from urllib.parse import urlsplit,parse_qs
mapping=[int(x) for x in Path('/proc/self/uid_map').read_text().split()]
if sys.flags.optimize:
    raise SystemExit('enabled assertions required')
if os.geteuid()!=0 or len(mapping)!=3 or mapping[0]!=0 or mapping[1]<=0 or mapping[2]!=65536:
    raise SystemExit(77)
expected=json.loads(Path('/opt/pnm-boot-expected.json').read_text())
assert all(os.stat('/proc/self/ns/'+n).st_ino!=v for n,v in expected['host_namespaces'].items())
assert Path('/run/host/container-manager').read_text().strip()=='systemd-nspawn'
logs=Path('/var/tmp/pnm-install-evidence')
logs.mkdir(mode=0o700)
os.umask(0o077)
passed=[]
stage='initial managed-resource baseline'
result={}
env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','LANG':'C.UTF-8','TZ':'UTC'}
def check(condition,label):
    if not condition:
        raise RuntimeError(label)
def call(label,args,accepted=(0,)):
    (logs/'operation.json').write_text(json.dumps({'label':label,'state':'started'}))
    command=['bash','/opt/pnm/bin/pnm']+args
    # A CLI descendant can retain PIPE fds after Bash exits. Own a separate
    # session so timeout retires the whole command group with bounded waits.
    with subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,env=env,start_new_session=True) as process:
        timed_out=False
        try:
            stdout,stderr=process.communicate(timeout=150)
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
        check(not timed_out,label+' command timed out')
        check(process.returncode in accepted,label+' exit='+str(process.returncode))
        return subprocess.CompletedProcess(command,process.returncode,stdout,stderr)
def show(unit,field):
    return subprocess.check_output(['systemctl','show',unit,'--property='+field,'--value'],text=True,timeout=10).strip()
def fields(path):
    return dict(line.split('=',1) for line in Path(path).read_text().splitlines() if line and not line.startswith('#'))
def absent():
    for name in ('xray','hysteria'):
        try:
            pwd.getpwnam(name)
        except KeyError:
            continue
        raise RuntimeError('unexpected preexisting managed identity')
    for name in ('/usr/local/bin/xray','/usr/local/bin/hysteria','/usr/local/etc/xray/config.json','/etc/hysteria/config.yaml','/etc/systemd/system/xray.service','/etc/systemd/system/hysteria-server.service'):
        check(not Path(name).exists() and not Path(name).is_symlink(),'unexpected managed resource')
try:
    absent()
    passed.append('fresh guest has no managed accounts or resources')
    stage='node init and validate'
    pins=json.loads(Path('/opt/pnm-test-versions.json').read_text())
    call('node-init',['node','init','--region','test','--address','203.0.113.10','--timezone','UTC',
        '--server-name','www.cloudflare.com','--target','www.cloudflare.com:443','--hy2-server-name','guest.invalid',
        '--xray-version',pins['xray']['version'],'--xray-sha256',pins['xray']['sha256'],
        '--hy2-version',pins['hysteria2']['version'],'--hy2-sha256',pins['hysteria2']['sha256']])
    call('node-validate',['node','validate'])
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='no','node configured before apply')
    passed.append('actual CLI initializes and validates an uncommitted node')
    stage='installation preview'
    call('install-preview',['install','--dry-run'])
    absent()
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='no','preview committed node state')
    passed.append('installation preview leaves accounts and runtime resources absent')
    stage='installation apply'
    call('install-apply',['install','--apply','--yes'])
    check(fields('/etc/pnm/node.conf')['PNM_CONFIGURED']=='yes','successful install lacks committed node state')
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
    def fingerprint(path):
        p=Path(path)
        st=p.stat()
        return (hashlib.sha256(p.read_bytes()).hexdigest(),st.st_mode,st.st_uid,st.st_gid)
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
    result={'passed':True,'checks':passed,'clock_diagnostic':checks.get('time_sync'),'uids_distinct':True}
except Exception as error:
    result={'passed':False,'checks':passed,'stage':stage,'error_class':type(error).__name__}
    if isinstance(error,RuntimeError):
        result['reason']=str(error)
finally:
    path=Path('/var/tmp/pnm-install-result.json')
    with path.open('x') as stream:
        json.dump(result,stream)
raise SystemExit(0 if result['passed'] else 1)
