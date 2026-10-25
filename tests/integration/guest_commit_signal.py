"""Pause a real publisher after rename for an owned CLI process interruption."""
from contextlib import contextmanager
import json
import hashlib
import os
from pathlib import Path
import stat
import signal
import subprocess
import uuid

from guest_start_fault import require, require_guest
from guest_commit_fault import transaction_for


def require_publisher_guest():
    try:
        require_guest()
    except RuntimeError as original:
        # Only this publisher observer gains the separately approved VM route;
        # account, mount and general startup-fault guards remain unchanged.
        try:
            from guest_vm_boot import require_approved_vm
            require_approved_vm()
        except (ImportError,RuntimeError):
            raise original from None


# Observe a call after the real rename; do not replace any filesystem operation.
# The receipt contains no marker content, resource hashes, credentials or locals.
TRACE_SOURCE='''import json,sys,time
from pathlib import Path
private=Path(__file__).parent
transaction=Path(json.loads((private/'config.json').read_text())['transaction'])

def observe(frame,event,arg):
    if (event=='call' and frame.f_code.co_filename=='<stdin>'
            and frame.f_code.co_name=='sync_directory'
            and frame.f_locals.get('path')==str(transaction)
            and frame.f_globals.get('temporary') is None
            and all((transaction/name).is_file() and not (transaction/name).is_symlink()
                    for name in ('commit.env','commit-uncertain.env'))):
        sys.settrace(None)
        (private/'ready.json').write_text(json.dumps({
            'marker_present':True,'uncertainty_present':True,'before_directory_sync':True}))
        time.sleep(30)
    return None
sys.settrace(observe)
'''


def run_late_commit(arguments, wrapper):
    require_publisher_guest()
    private=Path(wrapper).parent
    info=private.lstat()
    require(private.resolve()==private and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
            'private late commit launcher required')
    if arguments[:2]!=['-','publish'] or (private/'attempted').exists():
        return subprocess.run(['/usr/bin/python3',*arguments],timeout=90).returncode
    transaction,_=transaction_for(arguments)
    with (private/'attempted').open('x') as stream:
        stream.write('one unchanged real publisher\n')
    observer=private/'observer'
    (observer/'config.json').write_text(json.dumps({'transaction':str(transaction)}))
    return subprocess.run(['/usr/bin/python3',*arguments],
        env={**os.environ,'PYTHONPATH':str(observer)},timeout=90).returncode


@contextmanager
def late_deployment_commit(logs, env):
    require_publisher_guest()
    private=logs/('late-commit-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    observer=private/'observer'
    observer.mkdir(mode=0o700)
    (observer/'sitecustomize.py').write_text(TRACE_SOURCE)
    launcher=private/'python3'
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_commit_signal import run_late_commit\nraise SystemExit(run_late_commit(sys.argv[1:],__file__))\n')
    launcher.chmod(0o700)
    original=env['PATH']
    try:
        env['PATH']=str(private)+':'+original
        yield observer/'ready.json'
    finally:
        env['PATH']=original


def run_late_interruption(logs, env, call, passed):
    require_guest()
    from guest_signal_cases import signal_owned_command_on_start
    from guest_deployment_cases import require_pending_deployment
    transactions=Path('/var/lib/pnm/transactions')
    before=set(transactions.iterdir())
    with late_deployment_commit(logs,env) as ready:
        expected={'marker_present':True,'uncertainty_present':True,'before_directory_sync':True}

        def publisher_paused():
            # Creation precedes write completion: never kill on existence alone.
            try:
                info=ready.lstat()
                return (stat.S_ISREG(info.st_mode) and info.st_uid==0
                        and stat.S_IMODE(info.st_mode)==0o600 and info.st_size<=1024
                        and json.loads(ready.read_text())==expected)
            except (OSError,ValueError):
                return False

        with signal_owned_command_on_start({},signal.SIGKILL,ready=publisher_paused) as slot:
            call('install-late-commit-SIGKILL',['install','--apply','--yes'],
                 accepted=(-9,),process_slot=slot)
        require(json.loads(ready.read_text())==expected,
            'late signal missed the actual publisher window')
    created=set(transactions.iterdir())-before
    require(len(created)==1,'late signal created unexpected transactions')
    transaction=created.pop()
    rows=[line.split('\t',2) for line in (transaction/'journal.tsv').read_text().splitlines()]
    events=[row[1] for row in rows]
    require(events.count('COMMIT_INTENT')==1 and events[-1]=='COMMIT_INTENT'
            and not any(event in events for event in ('COMMIT','ROLLBACK_BEGIN','ROLLED_BACK','ROLLBACK_COMPLETE')),
            'late interrupted deployment was finalized or compensated')
    require(all(any(row[1:]==['WRITE','label=applied_'+core] for row in rows)
                for core in ('xray','hysteria2')),'late interruption preceded dual applied publication')
    require((transaction/'commit-uncertain.env').read_text()=='SCHEMA_VERSION=1\nORIGINAL_RC=70\n',
            'late interruption lost its uncertainty record')
    metadata=dict(line.split('=',1) for line in (transaction/'metadata.env').read_text().splitlines())
    verification=subprocess.run(['bash','-c',
        'source "$1"; pnm_tx_deployment_marker verify "$2" "$3" "$4"','verify-marker',
        '/opt/pnm/lib/deployment-state.sh',str(transaction),transaction.name,metadata['DEPLOYMENT_ID']],
        env=env,capture_output=True,timeout=20)
    require(verification.returncode==0 and not verification.stdout,'late marker failed real product verification')
    passed.append('actual publisher post-rename SIGKILL retains valid marker and uncertainty without finalization')

    def unit_state():
        result={}
        for core,unit,configuration in (
                ('xray','xray.service','/usr/local/etc/xray/config.json'),
                ('hysteria2','hysteria-server.service','/etc/hysteria/config.yaml')):
            output=subprocess.check_output(['systemctl','show',unit,
                '--property=LoadState,ActiveState,MainPID,InvocationID,UnitFileState'],text=True,timeout=10)
            fields=dict(line.split('=',1) for line in output.splitlines() if line)
            applied=Path('/var/lib/pnm/cores')/core/'applied.env'
            record=dict(line.split('=',1) for line in applied.read_text().splitlines())
            require(fields['LoadState']=='loaded' and fields['ActiveState']=='active'
                    and fields['MainPID']!='0' and fields['UnitFileState']=='enabled'
                    and record['CONFIG_SHA256']==hashlib.sha256(Path(configuration).read_bytes()).hexdigest()
                    and record['SERVICE_INVOCATION_ID']==fields['InvocationID'],
                    'late interrupted candidate lacks a live matching applied generation')
            flag,port=('-lnt',443) if core=='xray' else ('-lnu',8443)
            sockets=subprocess.check_output(['ss','-H',flag],text=True,timeout=5)
            require(any(line.split()[3].endswith(':'+str(port)) for line in sockets.splitlines()),
                    'late interrupted candidate has no listener')
            result[core]=fields
        return result

    unit_state()
    passed.append('both late interrupted real Core generations remain enabled healthy and applied-bound')
    require_pending_deployment(call,unit_state,passed)
    (logs/'late-commit-signal.json').write_text(json.dumps({
        'marker_verified':True,'uncertainty_retained':True,'before_directory_sync':True,
        'signal':int(signal.SIGKILL),'both_applied_bound':True,'fresh_commands_blocked':4}))
