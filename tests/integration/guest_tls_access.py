"""Real managed-account TLS permission failures; restricted to the private guest."""
from pathlib import Path
import json
import os
import stat
import subprocess

from guest_start_fault import require, require_guest
from guest_recovery_cases import fingerprint, receipt_state


def run_tls_access(logs, env, call, state, binding, links_ready, passed) -> None:
    require_guest()
    key=Path('/etc/hysteria/tls/server.key')
    directory=key.parent
    key_info=key.stat()
    directory_info=directory.stat()
    require(stat.S_ISREG(key_info.st_mode) and not key.is_symlink()
            and directory.resolve()==directory,'unsafe TLS fixture resource')
    secrets=[key.read_bytes()]
    for path in ('/etc/pnm/secrets/hysteria.env','/etc/pnm/secrets/reality.env'):
        for line in Path(path).read_bytes().splitlines():
            name,separator,value=line.partition(b'=')
            if separator and name in (b'HY2_AUTH_PASSWORD',b'XRAY_UUID',b'XRAY_REALITY_PRIVATE_KEY'):
                require(len(value)>=16,'missing diagnostic secrecy sentinel')
                secrets.append(value)
    entry=Path('/opt/pnm/bin/pnm').read_text()
    dispatcher='pnm_main "$@"\n'
    require(entry.endswith(dispatcher),'unexpected CLI dispatcher')
    script=logs/'tls-access-gate.sh'
    with script.open('x') as stream:
        stream.write(entry[:-len(dispatcher)]+
            'rc=0\npnm_check_deploy_core_health hysteria2 || rc=$?\npnm_check_render_json\nexit "$rc"\n')
    gate_env={**env,'PNM_LIB_DIR':'/opt/pnm/lib','PNM_ADAPTER_DIR':'/opt/pnm/adapters',
              'PNM_VERSION_FILE':'/opt/pnm/VERSION'}
    peer=state('xray')
    original=state('hysteria2')
    for case in ('wrong-key-owner','inaccessible-parent'):
        try:
            if case=='wrong-key-owner':
                os.chown(key,0,0)
            else:
                # Correct leaf metadata is insufficient when directory traversal
                # is denied. This exercises runuser, not just stat policy.
                directory.chmod(0o700)
            probe=subprocess.run(['runuser','-u','hysteria','--','test','-r',str(key)],
                                 capture_output=True,timeout=10)
            require(probe.returncode==1,'actual managed identity could still read the private key')
            cores={core:state(core) for core in ('xray','hysteria2')}
            receipts=receipt_state()
            managed={path:fingerprint(Path(path)) for core in cores.values() for path in core['resources']}
            observed=call('tls-access-'+case,['--json','check'],accepted=(2,))
            gate=subprocess.run(['bash',str(script)],env=gate_env,capture_output=True,timeout=25)
            (logs/(case+'.gate.stdout')).write_bytes(gate.stdout)
            (logs/(case+'.gate.stderr')).write_bytes(gate.stderr)
            require(gate.returncode==78,'deployment health gate accepted inaccessible TLS material')
            for result in (observed,gate):
                checks={item['id']:item for item in json.loads(result.stdout)['checks']}
                require(checks['hysteria_tls_permissions']['status']=='FAIL','TLS access diagnostic did not fail')
                if case=='inaccessible-parent':
                    require('effective read probe failed' in checks['hysteria_tls_permissions']['detail'],
                            'matching leaf policy did not reach the effective account probe')
                require(not any(value in result.stdout+result.stderr for value in secrets)
                        and b'PRIVATE KEY-----' not in result.stdout+result.stderr,
                        'TLS diagnostic disclosed a credential')
            require(cores=={core:state(core) for core in cores} and receipts==receipt_state()
                    and managed=={path:fingerprint(Path(path)) for path in managed},
                    'TLS inspection changed runtime, identities or managed files')
        finally:
            os.chown(key,key_info.st_uid,key_info.st_gid)
            key.chmod(stat.S_IMODE(key_info.st_mode))
            os.chown(directory,directory_info.st_uid,directory_info.st_gid)
            directory.chmod(stat.S_IMODE(directory_info.st_mode))
        require(state('xray')==peer and state('hysteria2')==original,'fixture did not restore TLS baseline')
        passed.append('actual hysteria TLS '+case+' fails diagnostics and startup gate without mutation or secret output')
    call('restart-after-tls-access',['restart','hysteria2'])
    binding('hysteria2')
    links_ready('links-after-tls-access')
    require(state('xray')==peer,'TLS recovery restart changed peer Core')
    restored=state('hysteria2')
    require(restored['resources']==original['resources'] and restored['invocation']!=original['invocation'],
            'TLS recovery did not restart with the original resources')
    checks={item['id']:item['status'] for item in json.loads(
        call('check-after-tls-access',['--json','check'],accepted=(0,1,2)).stdout)['checks']}
    require(checks.get('hysteria_tls_permissions')=='OK'
            and not any(status in ('FAIL','UNKNOWN') for name,status in checks.items() if name!='time_sync'),
            'TLS recovery diagnostics remain unhealthy')
    passed.append('actual HY2 restart after permission recovery refreshes binding and preserves Xray')
