from pathlib import Path
import hashlib,json,os,stat,subprocess,sys,time
if sys.flags.optimize:
    raise SystemExit('enabled assertions required')
os.umask(0o077)
expected=json.loads(Path('/opt/pnm-boot-expected.json').read_text())
result={'passed':False}
safe=False
stage='namespace identity'
try:
    names=expected['host_namespaces']
    assert set(names)=={'mnt','pid','net','user','cgroup','uts','ipc'}
    assert {p.name for p in Path('/sys/class/net').iterdir()}=={'lo'}
    assert all(os.stat('/proc/self/ns/'+n).st_ino!=names[n] for n in names)
    stage='UID mapping'
    mapping=[int(x) for x in Path('/proc/self/uid_map').read_text().split()]
    assert len(mapping)==3 and mapping[0]==0 and mapping[1]>0 and mapping[2]==65536
    stage='PID1 and root identity'
    assert os.geteuid()==0 and Path('/proc/1/comm').read_text().strip()=='systemd'
    stage='machine identity'
    assert hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()!=expected['host_machine_id_digest']
    stage='root mount identity'
    result['observed_root']=[os.stat('/').st_dev,os.stat('/').st_ino]
    assert (os.stat('/').st_dev,os.stat('/').st_ino)==tuple(expected['root_identity'])
    stage='guest root traversal permissions'
    root_mode=stat.S_IMODE(os.stat('/').st_mode)
    assert root_mode==0o755
    stage='container type'
    virtual=subprocess.run(['systemd-detect-virt','--container'],capture_output=True,text=True,timeout=5)
    assert Path('/run/host/container-manager').read_text().strip()=='systemd-nspawn'
    assert virtual.returncode==0 and virtual.stdout.strip() in ('wsl','systemd-nspawn')
    safe=True
    deadline=time.monotonic()+60
    while time.monotonic()<deadline:
        state=subprocess.run(['systemctl','is-system-running'],capture_output=True,text=True,timeout=5).stdout.strip()
        if state in ('running','degraded'):
            stage='boot cgroup write scope'
            unified=Path('/sys/fs/cgroup/cgroup.controllers').exists()
            paths=[Path('/sys/fs/cgroup')]
            if not unified:
                paths += [p for p in Path('/sys/fs/cgroup').iterdir() if p.is_dir() and not p.is_symlink()]
            writable=sorted(str(p) for p in paths if os.access(p,os.W_OK))
            result['writable_cgroups']=writable
            allowed=({'/sys/fs/cgroup'} if unified
                     else {'/sys/fs/cgroup/systemd','/sys/fs/cgroup/unified'})
            assert set(writable)==allowed
            result={'passed':True,'writable_cgroups':writable,'controllers_checked':len(paths)-1,'manager_state':state,'root_mode':f'{root_mode:04o}','identity_guards':True,'uid_base':mapping[1],'native_marker':'systemd-nspawn','detected_container':virtual.stdout.strip()}
            ready=Path('/var/tmp/pnm-integration-ready.json')
            with ready.open('x') as stream:
                json.dump(result,stream)
            approval=Path('/var/tmp/pnm-integration-approved')
            limit=time.monotonic()+60
            while time.monotonic()<limit:
                if approval.exists() and not approval.is_symlink() and approval.read_text()==expected['approval_nonce']:
                    break
                time.sleep(0.2)
            else:
                raise RuntimeError('host boundary approval was not received')
            if expected.get('boot_only') is True:
                result['boot_only']=True
                break
            stage='PNM installation cases'
            with Path('/var/tmp/pnm-install-cases.log').open('xb') as output:
                case=subprocess.run(['/usr/bin/python3','/opt/pnm-install-cases.py'],stdout=output,stderr=subprocess.STDOUT,timeout=600)
            details=json.loads(Path('/var/tmp/pnm-install-result.json').read_text())
            result['installation']=details
            result['passed']=case.returncode==0 and details.get('passed') is True
            break
        time.sleep(1)
except Exception as error:
    result.update({'passed':False,'error_class':type(error).__name__,'guard':stage})
finally:
    path=Path('/var/tmp/pnm-integration-result.json')
    fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    with os.fdopen(fd,'w') as stream:
        json.dump(result,stream)
    if safe:
        time.sleep(3)
        subprocess.run(['systemctl','--no-ask-password','poweroff'],timeout=10,check=False)
