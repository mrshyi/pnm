"""Actual PNM lifecycle followed by same-disk independent-kernel reboot checks."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

from guest_vm_boot import GuestRefusal, main as boot_main, require_approved_vm, require_vm


BASELINE=Path('/var/tmp/pnm-vm-lifecycle-baseline.json')
UNITS={'xray':'xray.service','hysteria2':'hysteria-server.service'}
CONFIGS={'xray':'/usr/local/etc/xray/config.json','hysteria2':'/etc/hysteria/config.yaml'}
RESOURCES={
    'xray':('/usr/local/bin/xray',CONFIGS['xray'],'/etc/pnm/secrets/reality.env',
            '/etc/systemd/system/xray.service'),
    'hysteria2':('/usr/local/bin/hysteria',CONFIGS['hysteria2'],'/etc/pnm/secrets/hysteria.env',
                 '/etc/hysteria/tls/server.crt','/etc/hysteria/tls/server.key',
                 '/etc/systemd/system/hysteria-server.service'),
}


def need(condition: bool,label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def fingerprint(path: str) -> list:
    file=Path(path)
    info=file.stat()
    return [hashlib.sha256(file.read_bytes()).hexdigest(),info.st_mode,info.st_uid,info.st_gid]


def show(unit: str,field: str) -> str:
    return subprocess.check_output(['systemctl','show',unit,'--property='+field,'--value'],
                                   text=True,timeout=10).strip()


def core_state(core: str) -> dict:
    unit=UNITS[core]
    previous={}
    for name in ('previous','previous.env'):
        path=Path('/var/lib/pnm/cores')/core/name
        need(not path.is_symlink(),'reboot previous-state path is a symlink')
        previous[name]=fingerprint(str(path)) if path.exists() else None
    return {'invocation':show(unit,'InvocationID'),'pid':show(unit,'MainPID'),
            'active':show(unit,'ActiveState'),'enabled':show(unit,'UnitFileState'),
            'resources':{p:fingerprint(p) for p in RESOURCES[core]},
            'applied':fingerprint('/var/lib/pnm/cores/'+core+'/applied.env'),'previous':previous}


def previous_pair(core: str) -> None:
    directory=Path('/var/lib/pnm/cores')/core
    metadata=dict(line.split('=',1) for line in (directory/'previous.env').read_text().splitlines())
    need(set(metadata)=={'SCHEMA_VERSION','CORE','VERSION'} and metadata['SCHEMA_VERSION']=='1'
         and metadata['CORE']==core,'reboot previous-state metadata identity differs')
    result=subprocess.run([str(directory/'previous'),'version'],capture_output=True,text=True,timeout=10)
    found=re.search(r'(?m)^Xray (\d+\.\d+\.\d+)' if core=='xray'
                    else r'(?m)^Version:\s*v?(\d+\.\d+\.\d+)',result.stdout+result.stderr)
    need(result.returncode==0 and found is not None and found.group(1)==metadata['VERSION'].removeprefix('v'),
         'reboot previous binary and metadata version differ')


def binding(core: str) -> None:
    state=core_state(core)
    record=dict(line.split('=',1) for line in
                Path('/var/lib/pnm/cores/'+core+'/applied.env').read_text().splitlines()
                if line and not line.startswith('#'))
    need(state['active']=='active' and state['enabled']=='enabled' and int(state['pid'])>0,
         'reboot Core is not enabled and active')
    need(record['CONFIG_SHA256']==hashlib.sha256(Path(CONFIGS[core]).read_bytes()).hexdigest()
         and record['SERVICE_INVOCATION_ID']==state['invocation'],'reboot applied binding differs')


def lifecycle() -> dict:
    identity=require_approved_vm()
    log=Path('/var/tmp/pnm-vm-lifecycle.log')
    with log.open('xb') as output:
        result=subprocess.run(['/usr/bin/python3','-B','/opt/pnm-install-cases.py'],
                              stdout=output,stderr=subprocess.STDOUT,timeout=600)
    detail=json.loads(Path('/var/tmp/pnm-install-result.json').read_text())
    scenario=Path('/opt/pnm-test-scenario').read_text().strip()
    need(scenario in ('lifecycle','core-update','deployment-progress-readonly','deployment-rename-readonly',
                     'deployment-marker-failures','deployment-space-full'),
         'unknown VM lifecycle scenario')
    update=scenario=='core-update'
    progress=scenario=='deployment-progress-readonly'
    rename=scenario=='deployment-rename-readonly'
    candidates=scenario=='deployment-marker-failures'
    space=scenario=='deployment-space-full'
    expected=26 if update else (17 if candidates else (15 if progress or rename or space else 14))
    need(result.returncode==0 and detail.get('passed') is True
         and detail.get('mainflow_completed') is True and len(detail.get('checks',[]))==expected,
         'independent VM mainflow/update checks did not pass')
    for core in UNITS:
        binding(core)
        if update:
            previous_pair(core)
    baseline={'schema':1,'boot_id':identity.boot_id,'update_matrix':update,
              'cores':{core:core_state(core) for core in UNITS},
              'authority':{p:fingerprint(p) for p in ('/etc/pnm/node.conf','/etc/pnm/versions.conf',
                           '/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow')}}
    with BASELINE.open('x') as stream:
        json.dump(baseline,stream)
        stream.flush()
        os.fsync(stream.fileno())
    return {'mainflow_checks':14,'update_checks':12 if update else 0,
            'committed_progress_refusal_checks':1 if progress else 0,
            'marker_rename_refusal_checks':1 if rename else 0,
            'marker_candidate_refusal_checks':3 if candidates else 0,
            'disk_space_refusal_checks':1 if space else 0,
            'both_bindings_confirmed':True,'baseline_persisted':True}


def reboot_acceptance() -> dict:
    identity=require_approved_vm()
    baseline=json.loads(BASELINE.read_text())
    need(baseline['schema']==1 and baseline['boot_id']!=identity.boot_id,
         'independent kernel boot identity did not change')
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if all(show(unit,'ActiveState')=='active' for unit in UNITS.values()):
            break
        time.sleep(0.2)
    for core in UNITS:
        current=core_state(core)
        original=baseline['cores'][core]
        need(current['active']=='active' and current['enabled']=='enabled'
             and current['invocation']!=original['invocation']
             and current['resources']==original['resources'] and current['applied']==original['applied']
             and current['previous']==original['previous'],
             'reboot changed persisted resources or retained old invocation')
        if baseline['update_matrix']:
            previous_pair(core)
    need(baseline['authority']=={p:fingerprint(p) for p in baseline['authority']},
         'reboot changed authority or NSS baseline')
    logs=Path('/var/tmp/pnm-vm-reboot-evidence')
    logs.mkdir(mode=0o700)

    def call(label: str,args: list[str],accepted: tuple[int,...]=(0,)) -> dict:
        result=subprocess.run(['bash','/opt/pnm/bin/pnm']+args,stdin=subprocess.DEVNULL,
                              capture_output=True,timeout=150,
                              env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','LANG':'C.UTF-8','TZ':'UTC'})
        (logs/(label+'.stdout')).write_bytes(result.stdout)
        (logs/(label+'.stderr')).write_bytes(result.stderr)
        need(result.returncode in accepted,'reboot CLI command failed: '+label)
        return json.loads(result.stdout) if '--json' in args and result.stdout else {}

    def links(label: str,ready: set[str]) -> None:
        # The real CLI returns78 with JSON when both unsafe links are withheld.
        data=call(label,['--json','node','links','--address','203.0.113.10'],
                  accepted=(0,) if ready else (78,))
        for core,key in (('xray','xray_vless_reality'),('hysteria2','hysteria2')):
            need((data[core+'_status']=='ready')==(core in ready),
                 'reboot link readiness differs from confirmed state')
            need(bool(data.get(key))==(core in ready),'reboot exposed an unconfirmed URI')

    links('stale-links',set())
    report=call('stale-show',['--json','node','show'],accepted=(78,))
    for core in UNITS:
        need(report['runtime'][core+'_applied_state']!='confirmed',
             'reboot node show promoted stale applied evidence')
    count=2
    for core in UNITS:
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(core)
        other=core_state(peer)
        call('restart-'+core,['restart',core])
        current=core_state(core)
        need(current['invocation']!=before['invocation'] and current['applied']==before['applied']
             and current['resources']==before['resources'] and core_state(peer)==other,
             'reboot restart promoted stale state or changed peer')
        links('restart-stale-links-'+core,set())
        count+=1
    ready=set()
    for core in UNITS:
        peer='hysteria2' if core=='xray' else 'xray'
        other=core_state(peer)
        call('apply-'+core,['apply',core])
        binding(core)
        need(core_state(peer)==other,'reboot apply changed peer')
        ready.add(core)
        links('applied-links-'+core,ready)
        count+=1
    for protocol,port in (('tcp',443),('udp',8443)):
        output=subprocess.check_output(['ss','-H','-lnt' if protocol=='tcp' else '-lnu'],text=True,timeout=10)
        need(any(line.split()[3].rsplit(':',1)[-1]==str(port) for line in output.splitlines()),
             'reboot actual Core listener is absent')
    return {'reboot_checks':count+1,'kernel_boot_id_changed':True,'both_invocations_changed':True,
            'paired_previous_preserved':baseline['update_matrix'],
            'persisted_resources_preserved':True,'stale_links_withheld':True,
            'ordinary_restart_did_not_promote':True,'both_bindings_reconfirmed':True,
            'tcp_udp_listeners_observed':True}


def main() -> None:
    require_vm()  # Refuse before looking at mutable guest state or invoking controls.
    os.umask(0o077)
    reboot=BASELINE.exists()
    boot_main(action=reboot_acceptance if reboot else lifecycle,
              scope='pnm-reboot' if reboot else 'pnm-lifecycle',
              power_action='poweroff' if reboot else 'reboot')


if __name__=='__main__':
    try:
        main()
    except GuestRefusal:
        raise SystemExit(77) from None
