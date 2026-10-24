"""Actual delayed service startup through the production local health gate."""
from pathlib import Path
import json
import subprocess
import time

from guest_start_fault import start_fault, require


def run_readiness(logs, env, core_state, show, passed) -> None:
    # Load exactly the trusted CLI libraries/initialization, replacing only its
    # final dispatcher with the existing gate and private structured diagnostics.
    entry=Path('/opt/pnm/bin/pnm').read_text()
    dispatch='pnm_main "$@"\n'
    require(entry.endswith(dispatch),'unexpected CLI dispatcher')
    script=logs/'readiness-gate.sh'
    with script.open('x') as stream:
        stream.write(entry[:-len(dispatch)]+
            'rc=0\npnm_check_deploy_core_health "$1" || rc=$?\npnm_check_render_json\nexit "$rc"\n')
    gate_env={**env,'PNM_LIB_DIR':'/opt/pnm/lib','PNM_ADAPTER_DIR':'/opt/pnm/adapters',
              'PNM_VERSION_FILE':'/opt/pnm/VERSION'}

    def gate(core, label):
        result=subprocess.run(['bash',str(script),core],env=gate_env,
                              capture_output=True,timeout=20)
        (logs/(label+'.stdout')).write_bytes(result.stdout)
        (logs/(label+'.stderr')).write_bytes(result.stderr)
        return result

    observations=[]
    for core,unit in (('xray','xray.service'),('hysteria2','hysteria-server.service')):
        peer='hysteria2' if core=='xray' else 'xray'
        before=core_state(core)
        peer_before=core_state(peer)
        with start_fault(core,mode='delay') as fault:
            subprocess.run(['systemctl','restart',unit],check=True,capture_output=True,timeout=15)
            invocation=show(unit,'InvocationID')
            require(invocation!=before['invocation'],'delay did not create a new service invocation')
            began=time.monotonic()
            first=gate(core,'delayed-first-'+core)
            elapsed=time.monotonic()-began
            details=json.loads(first.stdout)
            # Preserve the failed observation and prove eventual readiness with
            # the same invocation, without another restart or configuration edit.
            time.sleep(3.2)
            later=gate(core,'delayed-later-'+core)
            observations.append({'core':core,'initial_rc':first.returncode,
                'elapsed':round(elapsed,3),'later_rc':later.returncode,
                'same_invocation':invocation==show(unit,'InvocationID'),
                'checks':[{k:item[k] for k in ('id','status','summary')} for item in details['checks']]})
            (logs/'readiness-observations.json').write_text(json.dumps(observations))
            require(later.returncode==0 and invocation==show(unit,'InvocationID'),
                    'delayed service did not become healthy in the same invocation')
            require(fault['attempts']==1 and fault['rejected']==0,'delayed real ExecStart was not observed')
            after=core_state(core)
            require(after['resources']==before['resources'] and after['applied']==before['applied'],
                    'readiness probe changed managed resources or certified an external restart')
            require(core_state(peer)==peer_before,'readiness probe changed peer Core')
            require(first.returncode==0,'startup gate rejected a valid delayed listener')
        passed.append('actual delayed '+core+' listener becomes ready within the startup gate without state promotion')
