"""First-install acquisition refusals using the existing private HTTPS fixture."""
import hashlib
import json
from pathlib import Path
import re
import ssl
import subprocess
import threading
import time

from guest_recovery_cases import fingerprint
from guest_start_fault import require
from guest_update_cases import AssetServer
from guest_vm_boot import require_approved_vm


def run_acquisition(logs, env, call, absent, passed, *, include_versions=False) -> None:
    require_approved_vm()  # Before path mutation, sockets or fixture preparation.
    require({p.name for p in Path('/sys/class/net').iterdir()}=={'lo'},'acquisition requires private lo')
    pins=json.loads(Path('/opt/pnm-test-versions.json').read_text())
    prior={}
    prior_payloads={}
    if include_versions:
        prior=json.loads(Path('/opt/pnm-acquisition-prior.json').read_text())
        for core in ('xray','hysteria2'):
            body=(Path('/opt/pnm-acquisition-prior')/prior[core]['filename']).read_bytes()
            require(hashlib.sha256(body).hexdigest()==prior[core]['sha256'] and len(body)==prior[core]['size']
                    and prior[core]['version']!=pins[core]['version'],'prior acquisition fixture differs from distinct pin')
            prior_payloads[core]=body
    cache=Path('/var/lib/pnm/assets')
    assets={core:cache/(core+'-'+pins[core]['version']+'-'+pins[core]['sha256']+extension)
            for core,extension in (('xray','.zip'),('hysteria2','.bin'))}
    payloads={}
    paths={}
    for core,path in assets.items():
        cached=fingerprint(path)
        require(cached[1]&0o777==0o600 and cached[2]==0,'initial acquisition cache is unprotected')
        body=path.read_bytes()
        require(hashlib.sha256(body).hexdigest()==pins[core]['sha256']
                and len(body)==pins[core]['size'],'initial acquisition cache differs from pin')
        paths[core]=('/XTLS/Xray-core/releases/download/'+pins[core]['version']+'/Xray-linux-64.zip'
                     if core=='xray' else '/apernet/hysteria/releases/download/app/'+pins[core]['version']+'/hysteria-linux-amd64')
        payloads[paths[core]]=body
    private=logs/'acquisition'
    private.mkdir(mode=0o700)
    cert,key=private/'server.crt',private/'server.key'
    generated=subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
        '-subj','/CN=github.com','-addext','subjectAltName=DNS:github.com',
        '-keyout',str(key),'-out',str(cert)],capture_output=True,timeout=15)
    require(generated.returncode==0,'acquisition fixture certificate generation failed')
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(str(cert),str(key))
    server=AssetServer(payloads,context)
    worker=threading.Thread(target=server.serve_forever,name='pnm-acquisition-fixture')
    authority=[Path('/etc/pnm/node.conf'),Path('/etc/pnm/versions.conf')]
    authority.extend(Path('/etc')/name for name in ('passwd','group','shadow','gshadow'))
    directories=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray','/etc/hysteria',
                 '/etc/hysteria/tls','/usr/local/bin','/etc/systemd/system',
                 '/etc/systemd/system/multi-user.target.wants','/var/lib/pnm/cores')

    def directory_state():
        result={}
        for name in directories:
            path=Path(name)
            require(not path.is_symlink(),'unexpected acquisition directory link')
            if not path.exists():
                result[name]=None
            else:
                require(path.is_dir(),'unexpected acquisition directory type')
                info=path.stat()
                result[name]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino)
        return result

    def units():
        result={}
        for unit in ('xray.service','hysteria-server.service'):
            output=subprocess.check_output(['systemctl','show',unit,
                '--property=LoadState,ActiveState,MainPID'],text=True,timeout=10)
            result[unit]=dict(line.split('=',1) for line in output.splitlines() if line)
        return result

    original_units=units()
    require(all(v=={'LoadState':'not-found','ActiveState':'inactive','MainPID':'0'}
                for v in original_units.values()),'acquisition requires absent initial units')
    original_directories=directory_state()
    versions=Path('/etc/pnm/versions.conf')
    original_versions=versions.read_text()
    original_env=dict(env)
    observations=[]
    try:
        worker.start()
        env.update({'https_proxy':'http://127.0.0.1:'+str(server.server_address[1]),
                    'CURL_CA_BUNDLE':str(cert),'NO_PROXY':''})
        for core in ('xray','hysteria2'):
            peer='hysteria2' if core=='xray' else 'xray'
            peer_before=fingerprint(assets[peer])
            held=private/assets[core].name
            assets[core].rename(held)
            held_before=fingerprint(held)
            try:
                failures=('partial','tls','checksum')+(('version',) if include_versions else ())+(('zip',) if core=='xray' else ())
                for failure in failures:
                    body=payloads[paths[core]]
                    checksum='0'*64 if failure=='checksum' else pins[core]['sha256']
                    if failure=='zip':
                        server.payloads[paths[core]]=b'PNM deliberately invalid ZIP fixture\n'
                        checksum=hashlib.sha256(server.payloads[paths[core]]).hexdigest()
                    elif failure=='version':
                        server.payloads[paths[core]]=prior_payloads[core]
                        checksum=prior[core]['sha256']
                    field='XRAY_SHA256' if core=='xray' else 'HY2_SHA256'
                    text,count=re.subn(r'(?m)^'+field+r'=.*$',lambda _:field+'='+checksum,original_versions)
                    require(count==1,'acquisition approval field missing')
                    versions.write_text(text)
                    baseline={str(p):fingerprint(p)[:4] for p in authority}
                    transactions=Path('/var/lib/pnm/transactions')
                    before_transactions=set(transactions.iterdir())
                    before_temporary=set(Path('/tmp').glob('pnm.*'))
                    before_requests=server.requests.count(paths[core])
                    before_tls=server.tls_refusals
                    if failure=='partial':
                        server.partial_paths.add(paths[core])
                    if failure=='tls':
                        server.tls_refusal_budget=1
                        env['CURL_CA_BUNDLE']='/etc/ssl/certs/ca-certificates.crt'
                    expected=69 if failure in ('partial','tls') else 78
                    try:
                        result=call('install-'+failure+'-'+core,['install','--apply','--yes'],accepted=(expected,))
                    finally:
                        env['CURL_CA_BUNDLE']=str(cert)
                        server.partial_paths.discard(paths[core])
                        server.payloads[paths[core]]=body
                    if failure in ('partial','tls'):
                        require(('curl: ('+('18' if failure=='partial' else '60')+')').encode() in result.stderr,
                                'install acquisition lacks the expected actual curl refusal')
                    elif failure=='version':
                        label='Xray' if core=='xray' else 'Hysteria2'
                        require(('Staged '+label+' version does not match the approved manifest.').encode() in result.stderr,
                                'version-pair refusal has a different cause')
                    deadline=time.monotonic()+2
                    while (server.requests.count(paths[core])<before_requests+(failure!='tls')
                           or server.tls_refusals<before_tls+(failure=='tls')) and time.monotonic()<deadline:
                        time.sleep(0.01)
                    require(server.requests.count(paths[core])==before_requests+(failure!='tls')
                            and server.tls_refusals==before_tls+(failure=='tls')
                            and server.tls_refusal_budget==0,'install acquisition request evidence differs')
                    absent()
                    require(baseline=={str(p):fingerprint(p)[:4] for p in authority}
                            and directory_state()==original_directories and units()==original_units,
                            'install acquisition did not restore authority, NSS, directories or units')
                    require(fingerprint(held)==held_before and fingerprint(assets[peer])==peer_before,
                            'install acquisition changed held or peer cache')
                    require(not assets[core].exists() and not assets[core].is_symlink() and not list(cache.glob('.pnm-asset.*'))
                            and set(Path('/tmp').glob('pnm.*'))==before_temporary,
                            'install acquisition published an original asset or retained temporary candidates')
                    created=set(transactions.iterdir())-before_transactions
                    require(len(created)==1,'install acquisition transaction count differs')
                    transaction=created.pop()
                    events=[line.split('\t',2)[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
                    require('ROLLBACK_COMPLETE' in events and events[-1]=='ROLLED_BACK'
                            and 'COMMIT' not in events and 'RECOVERY_REQUIRED' not in events,
                            'install acquisition outer recovery is incomplete')
                    require(all(not (transaction/name).exists() and not (transaction/name).is_symlink()
                                for name in ('commit.env','commit-uncertain.env')),
                            'install acquisition promoted a marker or uncertainty')
                    if failure in ('zip','version'):
                        bad=cache/(core+'-'+pins[core]['version']+'-'+checksum+('.zip' if core=='xray' else '.bin'))
                        require(hashlib.sha256(bad.read_bytes()).hexdigest()==checksum,
                                'rejected asset did not reach verified cache/staging')
                        accounts=[line.split('\t') for line in (transaction/'accounts.tsv').read_text().splitlines()]
                        created_accounts=[row for row in accounts if row[0]=='APPLIED']
                        require(len(created_accounts)==4 and all(['RESTORED',*row[1:]] in accounts
                                for row in created_accounts),'rejected staged asset did not compensate all four actual owned identities')
                    observations.append({'core':core,'failure':failure,'original_rc':expected,
                                         'complete_rollback':True,'managed_resources_absent':True})
                    (private/'results.json').write_text(json.dumps(observations))
                    passed.append('actual first-install '+core+' '+failure+' refusal preserves original authority and fully compensates')
            finally:
                # Restore only the owned fixture inode, never an unexpected
                # cache entry left by product behavior; preserve that evidence.
                require(not assets[core].exists() and not assets[core].is_symlink(),
                        'held fixture destination unexpectedly exists')
                held.rename(assets[core])
        versions.write_text(original_versions)
        require(len(observations)==(9 if include_versions else 7) and server.tls_refusals==2
                and len(server.requests)==(7 if include_versions else 5),
                'install acquisition coverage counts differ')
    finally:
        env.clear()
        env.update(original_env)
        if worker.ident is not None:
            server.shutdown()
        server.server_close()
        if worker.ident is not None:
            worker.join(timeout=2)
        require(not worker.is_alive() and not server.errors,'acquisition server failed or did not retire')
