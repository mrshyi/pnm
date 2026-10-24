#!/usr/bin/env python3
"""Opt-in offline-cache CLI acceptance in a clone of a verified Debian fixture."""
from __future__ import annotations
import argparse
import stat
import sys
import os
from pathlib import Path
if sys.flags.optimize or os.environ.get('PNM_RUN_GUEST_TESTS')!='1':
    raise SystemExit('Explicit PNM_RUN_GUEST_TESTS=1 and enabled assertions required')
if sys.platform!='linux' or os.geteuid()!=0:
    raise SystemExit('Linux root required')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline',type=Path,required=True,help='private verified boot fixture parent')
parser.add_argument('--nspawn',type=Path,required=True,help='trusted native systemd-nspawn executable')
parser.add_argument('--asset-cache',type=Path,required=True,help='verified pinned Core asset cache')
parser.add_argument('--scenario',choices=('lifecycle','deployment-failure','core-update','core-update-failure',
    'configured-ports','runtime-evidence','restore-failure','startup-readiness',
    'core-recovery-failure-xray','core-recovery-failure-hysteria2','restore-recovery-failure','tls-access',
    'account-reuse','core-interruption','core-interruption-hysteria2','restart-readiness',
    'dependency-refusal'),default='lifecycle')
parser.add_argument('--previous-asset-cache',type=Path)
parser.add_argument('--work-dir',type=Path,help='optional canonical private root-owned POSIX fixture directory')
options=parser.parse_args()
work_dir=options.work_dir or Path('/var/tmp')
if options.work_dir is not None:
    assert work_dir.is_absolute() and work_dir==work_dir.resolve() and work_dir.is_dir(), 'canonical work directory required'
    info=work_dir.stat()
    assert info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700, 'private root-owned work directory required'
is_update=options.scenario in ('core-update','core-update-failure','core-recovery-failure-xray','core-recovery-failure-hysteria2')
if is_update and options.previous_asset_cache is None:
    parser.error('core-update requires --previous-asset-cache')
for location in (options.baseline,options.nspawn):
    assert location.is_absolute() and location==location.resolve(), 'canonical trusted paths required'
    info=location.stat()
    assert info.st_uid==0 and not info.st_mode & 0o022, 'trusted root ownership/modes required'
assert options.baseline.is_dir() and options.nspawn.is_file() and os.access(options.nspawn,os.X_OK)
assert options.baseline.stat().st_mode & 0o777 == 0o700, 'private baseline required'
os.umask(0o077)

def write_clone_file(path: Path, data: str) -> None:
    """Write a protected clone file without following an existing guest link."""
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_NOFOLLOW|os.O_NONBLOCK,0o600)
    with os.fdopen(fd,'w') as stream:
        info=os.fstat(stream.fileno())
        assert stat.S_ISREG(info.st_mode) and info.st_uid==0 and info.st_nlink==1
        os.fchmod(stream.fileno(),0o600)
        stream.truncate(0)
        stream.write(data)

from pathlib import Path
import os,sys,json,subprocess,tempfile,shutil,uuid,hashlib
sys.dont_write_bytecode=True
repo=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(repo/'tests/integration'))
from test_real_cores import verified_assets
assets=verified_assets(options.asset_cache)
manifest=json.loads((repo/'tests/integration/real_core_versions.json').read_text())
current_assets=assets
target_manifest=manifest
if is_update:
    previous_manifest=repo/'tests/integration/previous_core_versions.json'
    assets=verified_assets(options.previous_asset_cache,manifest_path=previous_manifest)
    manifest=json.loads(previous_manifest.read_text())
source=options.baseline/'rootfs'
assert source.is_dir() and source==source.resolve(), 'canonical rootfs required'
assert json.loads((options.baseline/'boot-result.json').read_text())['guest']['passed'] is True
base=Path(tempfile.mkdtemp(prefix='pnm-install-guest.',dir=work_dir))
root=base/'rootfs'
subprocess.run(['cp','-a','--reflink=auto',str(source),str(root)],check=True,timeout=120)
# Host-side preparation must never follow an absolute guest symlink out of its
# new clone. Native rootfs symlinks such as /bin are otherwise preserved.
for relative in ('etc','var/lib/dbus','opt','var/lib','var/tmp',
                 'etc/systemd/system','etc/systemd/system/multi-user.target.wants'):
    location=root/relative
    assert location.is_dir() and location==location.resolve(), 'unsafe clone parent'
for relative in ('etc/machine-id','etc/passwd'):
    location=root/relative
    assert location.is_file() and not location.is_symlink(), 'unsafe clone file'
assert not (root/'etc/pnm').exists()
names=[line.split(':',1)[0] for line in (root/'etc/passwd').read_text().splitlines()]
assert 'xray' not in names and 'hysteria' not in names
new_id=uuid.uuid4().hex+'\n'
write_clone_file(root/'etc/machine-id',new_id)
dbus=root/'var/lib/dbus/machine-id'
if dbus.is_symlink():
    assert os.readlink(dbus) in ('/etc/machine-id','../../../etc/machine-id')
else:
    write_clone_file(dbus,new_id)
dest=root/'opt/pnm'
assert not dest.exists()
dest.mkdir(mode=0o755)
for name in ('bin','lib','adapters'):
    shutil.copytree(repo/name,dest/name,symlinks=True)
shutil.copyfile(repo/'VERSION',dest/'VERSION')
hashes={}
for path in dest.rglob('*'):
    assert not path.is_symlink()
    path.chmod(0o755 if path.is_dir() or path==dest/'bin/pnm' else 0o644)
    if path.is_file():
        hashes[str(path.relative_to(dest))]=hashlib.sha256(path.read_bytes()).hexdigest()
state=root/'var/lib/pnm'
state.mkdir(mode=0o700)
cache=state/'assets'
cache.mkdir(mode=0o700)
for core,extension in (('xray','zip'),('hysteria2','bin')):
    pin=manifest[core]
    path=cache/(core+'-'+pin['version']+'-'+pin['sha256']+'.'+extension)
    path.write_bytes(assets[core])
    path.chmod(0o600)
write_clone_file(root/'opt/pnm-test-versions.json',json.dumps(manifest))
write_clone_file(root/'opt/pnm-test-scenario',options.scenario)
if is_update:
    update_assets=root/'opt/pnm-update-assets'
    assert not update_assets.exists() and not update_assets.is_symlink()
    update_assets.mkdir(mode=0o700)
    for core in ('xray','hysteria2'):
        path=update_assets/target_manifest[core]['filename']
        path.write_bytes(current_assets[core])
        path.chmod(0o600)
    write_clone_file(root/'opt/pnm-update-targets.json',json.dumps(target_manifest))
prefix=[str(options.nspawn),'--directory='+str(root),'--machine=placeholder','--settings=no','--register=no','--link-journal=no','--private-network','--private-users=pick','--private-users-ownership=auto','--resolv-conf=off','--timezone=off','--console=pipe']
machine='pnm-install-'+uuid.uuid4().hex[:18]
prefix=[('--directory='+str(root)) if s.startswith('--directory=') else ('--machine='+machine) if s.startswith('--machine=') else s for s in prefix]
(base/'nspawn-prefix.json').write_text(json.dumps(prefix))
(base/'guest-identity.json').write_text(json.dumps({'machine':machine,'dev':root.stat().st_dev,'ino':root.stat().st_ino}))
(base/'source-hashes.json').write_text(json.dumps(hashes,indent=2))
(base/'source-origin.json').write_text(json.dumps({'snapshot':'copied worktree; source-hashes.json is authoritative'}))
print('install_fixture='+str(base)+' source_files='+str(len(hashes)),flush=True)

# Only the newly created clone is writable; no host directory is bind-mounted.
for name,target in (('guest_mainflow_cases.py','pnm-install-cases.py'),
                    ('guest_mainflow_worker.py','pnm-boot-worker.py')):
    destination=root/'opt'/target
    assert not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration'/name,destination)
    destination.chmod(0o700)
    import py_compile
    py_compile.compile(str(destination),cfile=str(base/(name+'.pyc')),doraise=True)
if is_update:
    destination=root/'opt/guest_update_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_update_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_update_cases.pyc'),doraise=True)
if options.scenario in ('core-update-failure','restore-failure','startup-readiness',
                        'core-recovery-failure-xray','core-recovery-failure-hysteria2','restore-recovery-failure',
                        'tls-access','account-reuse','core-interruption','core-interruption-hysteria2',
                        'restart-readiness','dependency-refusal'):
    destination=root/'opt/guest_start_fault.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_start_fault.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_start_fault.pyc'),doraise=True)
if options.scenario in ('startup-readiness','restart-readiness'):
    destination=root/'opt/guest_readiness_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_readiness_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_readiness_cases.pyc'),doraise=True)
if options.scenario.startswith('core-recovery-failure-') or options.scenario in ('restore-recovery-failure','tls-access','account-reuse','core-interruption','core-interruption-hysteria2','dependency-refusal'):
    destination=root/'opt/guest_recovery_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_recovery_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_recovery_cases.pyc'),doraise=True)
if options.scenario=='tls-access':
    destination=root/'opt/guest_tls_access.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_tls_access.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_tls_access.pyc'),doraise=True)
if options.scenario=='account-reuse':
    destination=root/'opt/guest_account_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_account_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_account_cases.pyc'),doraise=True)
if options.scenario in ('core-interruption','core-interruption-hysteria2'):
    destination=root/'opt/guest_signal_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_signal_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_signal_cases.pyc'),doraise=True)
if options.scenario=='dependency-refusal':
    destination=root/'opt/guest_preflight_cases.py'
    assert not destination.exists() and not destination.is_symlink()
    shutil.copyfile(repo/'tests/integration/guest_preflight_cases.py',destination)
    destination.chmod(0o700)
    py_compile.compile(str(destination),cfile=str(base/'guest_preflight_cases.pyc'),doraise=True)
unit=root/'etc/systemd/system/pnm-boot-probe.service'
assert unit.is_file() and not unit.is_symlink()
assert 'ExecStart=/usr/bin/python3 /opt/pnm-boot-worker.py' in unit.read_text(), 'dedicated boot fixture unit required'
assert (root/'etc/systemd/system/multi-user.target.wants/pnm-boot-probe.service').is_symlink()
# The baseline's 80-second boot-only watchdog cannot cover CLI lifecycle work.
# Replace only its cloned dedicated test unit; guest cases retain their own
# 600-second limit and the host keeps the independent 720-second deadline.
write_clone_file(unit,'[Unit]\nDescription=Private PNM guest main-flow test\nAfter=basic.target\n'
    '[Service]\nType=simple\nExecStart=/usr/bin/python3 /opt/pnm-boot-worker.py\n'
    'NoNewPrivileges=yes\nRuntimeMaxSec=690\n[Install]\nWantedBy=multi-user.target\n')
from pathlib import Path
import hashlib,json,os,signal,subprocess,time,uuid
root=base/'rootfs'
prefix=json.loads((base/'nspawn-prefix.json').read_text())
identity=json.loads((base/'guest-identity.json').read_text())
scope=identity['machine']+'.scope'
def value(field):
    return subprocess.check_output(['systemctl','show',scope,'--property='+field,'--value'],text=True,timeout=10).strip()
assert value('LoadState')=='not-found'
assert (root.stat().st_dev,root.stat().st_ino)==(identity['dev'],identity['ino'])
assert not (root/'etc/pnm').exists()
policy=root/'usr/sbin/policy-rc.d'
if policy.exists() or policy.is_symlink():
    assert not policy.is_symlink() and hashlib.sha256(policy.read_bytes()).hexdigest()==(base/'policy-sha256').read_text()
    policy.unlink()
guest_result=root/'var/tmp/pnm-integration-ready.json'
final_result=root/'var/tmp/pnm-integration-result.json'
approval=root/'var/tmp/pnm-integration-approved'
assert not final_result.exists() and not approval.exists()
assert not guest_result.exists()
expected={'host_namespaces':{n:os.stat('/proc/self/ns/'+n).st_ino for n in ('mnt','pid','net','user','cgroup','uts','ipc')},'host_machine_id_digest':hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest(),'root_identity':[root.stat().st_dev,root.stat().st_ino],'approval_nonce':uuid.uuid4().hex}
write_clone_file(root/'opt/pnm-boot-expected.json',json.dumps(expected))
names=['/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow','/var/lib/dpkg/status']
before={n:hashlib.sha256(Path(n).read_bytes()).hexdigest() for n in names}
outcome={}
invocation=None
interrupted_signal=0
def record_interruption(signum, _frame):
    # Record rather than raise across Popen construction; the bounded loop
    # handles the interruption after ownership of the child is established.
    global interrupted_signal
    interrupted_signal=signum
for caught in (signal.SIGINT,signal.SIGTERM,signal.SIGHUP):
    signal.signal(caught,record_interruption)
with (base/'boot.log').open('wb') as log:
    args=[s for s in prefix if s!='--as-pid2']+['--boot','--','systemd.unit=multi-user.target','systemd.log_level=notice','systemd.show_status=no']
    proc=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    try:
        deadline=time.monotonic()+720
        seen_at=None
        while proc.poll() is None and time.monotonic()<deadline:
            if interrupted_signal:
                break
            if invocation is None and value('LoadState')!='not-found':
                assert value('Transient')=='yes' and identity['machine'] in value('Description')
                assert value('ControlGroup')=='/machine.slice/'+scope
                invocation=value('InvocationID')
            if guest_result.exists():
                assert guest_result.resolve()==guest_result
                if 'live_cgroup_boundary' not in outcome:
                    todo=[proc.pid]
                    while todo:
                        pid=todo.pop()
                        try:
                            todo.extend(int(x) for x in Path('/proc/'+str(pid)+'/task/'+str(pid)+'/children').read_text().split())
                            fields={s.split(':',1)[0]:s.split(':',1)[1].strip() for s in Path('/proc/'+str(pid)+'/status').read_text().splitlines() if ':' in s}
                            if fields.get('Name')!='systemd' or fields.get('NSpid','').split()[-1:]!=['1']:
                                continue
                            assert os.stat('/proc/'+str(pid)+'/ns/pid').st_ino!=os.stat('/proc/self/ns/pid').st_ino
                            mounts=Path('/proc/'+str(pid)+'/mountinfo').read_text().splitlines()
                            for path in ('/sys/fs/cgroup/systemd','/sys/fs/cgroup/unified'):
                                lines=[x.split() for x in mounts if x.split()[4]==path]
                                assert len(lines)==1 and lines[0][3]=='/machine.slice/'+scope+'/payload'
                            assert any(' /sys/fs/cgroup ' in x and ' - tmpfs ' in x for x in mounts)
                            outcome['live_cgroup_boundary']=True
                            (base/'boot-live-mounts.json').write_text(json.dumps(mounts))
                            break
                        except FileNotFoundError:
                            pass
                if outcome.get('live_cgroup_boundary') and not approval.exists():
                    ready=json.loads(guest_result.read_text())
                    assert ready.get('passed') is True
                    fd=os.open(approval,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
                    with os.fdopen(fd,'w') as stream:
                        stream.write(expected['approval_nonce'])
                    outcome['installation_approved']=True
            time.sleep(0.5)
    finally:
        for caught in (signal.SIGINT,signal.SIGTERM,signal.SIGHUP):
            signal.signal(caught,signal.SIG_IGN)
        if proc.poll() is None:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                if invocation and value('LoadState')!='not-found':
                    assert value('InvocationID')==invocation and value('ControlGroup')=='/machine.slice/'+scope
                    assert value('Transient')=='yes' and identity['machine'] in value('Description')
                    subprocess.run(['systemctl','stop',scope],timeout=15,check=True,capture_output=True)
                if proc.poll() is None:
                    proc.kill()
                    proc.wait(timeout=5)
        outcome['nspawn_exit']=proc.returncode
outcome['interrupted_signal']=interrupted_signal
if final_result.exists():
    assert final_result.resolve()==final_result and final_result.stat().st_size<=8192
    outcome['guest']=json.loads(final_result.read_text())
else:
    outcome['guest']={'passed':False,'error_class':'NoGuestReport'}
outcome['host_databases_unchanged']=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==before[n] for n in names)
outcome['scope_after']=value('LoadState')
outcome['remaining_fixture_mounts']=any(str(base) in line for line in Path('/proc/self/mountinfo').read_text().splitlines())
# Keep the safe cleanup/result summary observable even if the host filesystem
# becomes read-only and cannot persist its report. Persistence errors still fail.
print(json.dumps(outcome),flush=True)
(base/'boot-result.json').write_text(json.dumps(outcome))
assert outcome['host_databases_unchanged'] and outcome['scope_after']=='not-found' and not outcome['remaining_fixture_mounts']
assert interrupted_signal==0, 'guest test interrupted; owned resources retired'

assert outcome['guest'].get('passed') is True and outcome.get('live_cgroup_boundary') is True and outcome['nspawn_exit']==0, 'guest boot was not confirmed'
