"""Real installed-node Profile cycle inside the existing approved guest only."""
from pathlib import Path
import json
import socket


def profile_cycle(call, core_state, binding, resources, fingerprint, check, passed, observer=None):
    units={'xray':'xray.service','hysteria2':'hysteria-server.service'}
    files={path:fingerprint(path) for paths in resources.values() for path in paths}
    policies={'dual':set(units),'reality':{'xray'},'hy2':{'hysteria2'}}
    for target in ('reality','hy2','dual'):
        before={core:core_state(core) for core in units}
        call('profile-'+target,['profile','set',target,'--yes'])
        observed=json.loads(call('profile-show-'+target,['--json','profile','show']).stdout)
        check(observed['desired']==target,'Profile selection was not persisted')
        check(files=={path:fingerprint(path) for path in files},'Profile changed Core bytes or credentials')
        for core in units:
            after=core_state(core)
            active=core in policies[target]
            check((after['active'],after['enabled'])==(('active','enabled') if active else ('inactive','disabled')),
                  'Profile actual service policy differs from desired selection')
            if (before[core]['active'],before[core]['enabled'])==(after['active'],after['enabled']):
                check(before[core]==after,'Profile changed an unchanged peer')
            if active:
                binding(core)
        if observer is not None:
            observer(target)
        passed.append('real Profile '+target+' preserves credentials and unchanged peers')
        if target=='reality':
            # Own one UDP socket in this approved private guest; force real HY2 bind failure.
            before_failure={core:core_state(core) for core in units}
            desired=Path('/etc/pnm/node.conf').read_bytes()
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as occupied:
                port=int(next(line.split('=',1)[1] for line in desired.decode().splitlines() if line.startswith('HY2_PORT=')))
                occupied.bind(('0.0.0.0',port))
                call('profile-startup-refusal',['profile','set','hy2','--yes'],accepted=(70,78))
            check(desired==Path('/etc/pnm/node.conf').read_bytes(),'Profile compensation changed desired selection')
            for core in units:
                after=core_state(core)
                check((after['active'],after['enabled'])==(before_failure[core]['active'],before_failure[core]['enabled']),
                      'Profile compensation did not restore service policy')
                check(after['resources']==before_failure[core]['resources'],'Profile compensation changed Core resources')
            binding('xray')
            call('profile-recovery-clear',['recovery','list'])
            passed.append('real Profile startup failure restores services and bindings then permits retry')

    # Existing validation refusal: no service mutation may precede admission.
    path=Path('/etc/hysteria/config.yaml')
    original=path.read_bytes()
    baseline={core:core_state(core) for core in units}
    node=Path('/etc/pnm/node.conf').read_bytes()
    try:
        path.write_bytes(b'not a PNM HY2 candidate\n')
        call('profile-invalid-candidate',['profile','set','hy2','--yes'],accepted=(78,))
        check(node==Path('/etc/pnm/node.conf').read_bytes(),'Profile refusal changed desired state')
        check(path.read_bytes()==b'not a PNM HY2 candidate\n','Profile refusal rewrote the rejected fixture')
        for core in units:
            current=core_state(core)
            # The fixture edit is intentional; all runtime/binding observations stay exact.
            current['resources']={name:value for name,value in current['resources'].items() if name!=str(path)}
            expected=dict(baseline[core],resources={name:value for name,value in baseline[core]['resources'].items() if name!=str(path)})
            check(current==expected,'Profile refusal changed service or applied state')
    finally:
        path.write_bytes(original)
    check(files=={name:fingerprint(name) for name in files},'Profile refusal did not preserve original files')
    passed.append('real Profile rejects invalid candidate before service changes')
