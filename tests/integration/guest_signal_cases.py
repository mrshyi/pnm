"""Owned CLI signal fixtures for native restart and deployment acceptance."""
from pathlib import Path
from contextlib import contextmanager
import json
import hashlib
import os
import signal
import subprocess
import threading
import time

from guest_start_fault import require, require_guest, start_fault
from guest_recovery_cases import require_commands_blocked


def run_restore_interruptions(logs, call, state, binding, links_ready, all_paths,
                              archive, backup_resources, passed, *, hard_core=None) -> None:
    require_guest()
    require(hard_core in (None,'xray','hysteria2'),'unknown interrupted restore Core')
    from guest_recovery_cases import fingerprint
    cores=('xray','hysteria2')
    directory_paths=('/etc/pnm','/etc/pnm/secrets','/usr/local/etc/xray',
                     '/etc/hysteria','/etc/hysteria/tls',
                     '/etc/systemd/system/multi-user.target.wants')

    def resources():
        return {p:fingerprint(Path(p))[:4] for p in all_paths}

    def directories():
        result={}
        for name in directory_paths:
            info=Path(name).lstat()
            result[name]=(info.st_mode,info.st_uid,info.st_gid,info.st_dev,info.st_ino)
        return result

    def previous():
        result={}
        for core in cores:
            for name in ('previous','previous.env'):
                path=Path('/var/lib/pnm/cores')/core/name
                require(not path.is_symlink(),'unexpected previous-state link')
                result[str(path)]=fingerprint(path) if path.exists() else None
        return result

    def listener(core):
        flag,port=('-lnt',443) if core=='xray' else ('-lnu',8443)
        lines=subprocess.check_output(['ss','-H',flag],text=True,timeout=3).splitlines()
        return any(line.split()[3].endswith(':'+str(port)) for line in lines)

    def trusted_archive():
        require(hashlib.sha256(archive.read_bytes()).hexdigest()==
                (logs/'trusted-backup.sha256').read_text(),'trusted interruption archive changed')

    node=Path('/etc/pnm/node.conf')
    original=node.read_text()
    changed=original.replace('XRAY_TARGET=edge.example.net:443','XRAY_TARGET=signal.example.net:443')
    require(changed!=original,'restore interruption fixture did not change desired configuration')
    node.write_text(changed)
    call('apply-before-restore-signal',['apply','xray'])
    require(resources()!=backup_resources,'restore interruption candidate equals the baseline')
    identity_paths=[Path('/etc')/name for name in ('passwd','group','shadow','gshadow')]
    identities={str(path):fingerprint(path) for path in identity_paths}
    for core in (cores if hard_core is None else (hard_core,)):
        before=resources()
        before_directories=directories()
        before_previous=previous()
        services={name:state(name) for name in cores}
        transactions=set(Path('/var/lib/pnm/transactions').iterdir())
        trusted_archive()
        hard=hard_core is not None
        with start_fault(core,mode='delay-pre') as fault:
            with signal_owned_command_on_start(fault,signal.SIGKILL if hard else signal.SIGTERM) as slot:
                call('restore-signal-'+core,['restore',str(archive)],
                     accepted=(-9 if hard else 143,),process_slot=slot)
            created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
            require(len(created)==1,'restore signal created unexpected transactions')
            transaction=created.pop()
            events=[line.split('\t')[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
            marker=transaction/'commit.env'
            require(events.count('WRITE')>=12 and 'COMMIT' not in events
                    and not marker.exists() and not marker.is_symlink(),
                    'restore signal did not follow uncommitted resource publication')
            if hard:
                deadline=time.monotonic()+10
                while not listener(core):
                    require(time.monotonic()<deadline,'interrupted restore listener did not stabilize')
                    time.sleep(0.1)
                (logs/('restore-SIGKILL-'+core+'-services.json')).write_text(json.dumps({
                    name:{key:state(name)[key] for key in ('active','pid','invocation','enabled')}
                    for name in cores}))
                require(fault['attempts']==1 and fault['rejected']==0
                        and resources()==backup_resources,'SIGKILL restore changed candidate resources')
                require('ROLLBACK_COMPLETE' not in events and 'ROLLED_BACK' not in events,
                        'SIGKILL restore was falsely recovered')
                for name in cores:
                    after=state(name)
                    require(after['applied']==services[name]['applied']
                            and after['enabled']==services[name]['enabled'],
                            'SIGKILL restore promoted applied evidence or changed service policy')
                    if core=='xray' and name=='hysteria2':
                        require(after['active']=='inactive' and after['pid']=='0',
                                'first-start restore interruption unexpectedly started HY2')
                    else:
                        require(after['active']=='active' and after['pid']!='0'
                                and after['invocation']!=services[name]['invocation'] and listener(name),
                                'interrupted restore candidate service is not the new live generation')
            else:
                require(fault['attempts']==2 and fault['rejected']==0 and resources()==before,
                        'TERM restore did not recover original resources and start both generations')
                require('ROLLBACK_COMPLETE' in events and events[-1]=='ROLLED_BACK'
                        and 'RECOVERY_REQUIRED' not in events,'TERM restore did not finish compensation')
                for name in cores:
                    binding(name)
                    require(state(name)['invocation']!=services[name]['invocation'] and listener(name),
                            'TERM restore retained stale invocation or returned before runtime readiness')
            require(directories()==before_directories and previous()==before_previous,
                    'restore signal changed directory identity/metadata or previous state')
            require(identities=={str(path):fingerprint(path) for path in identity_paths},
                    'restore signal changed service identities')
        trusted_archive()
        if hard:
            passed.append('actual '+core+' restore SIGKILL retains published archive and prior applied evidence')
            require_commands_blocked(call,state,core,passed,operation='core-restore')
            return
        links_ready('links-after-restore-TERM-'+core)
        passed.append('actual '+core+' restore TERM preserves143 and recovers both original generations')
    trusted_archive()
    call('restore-retry-after-TERM',['restore',str(archive)])
    require(resources()==backup_resources,'restore TERM retry differs from the trusted archive')
    for core in cores:
        binding(core)
    links_ready('links-after-restore-TERM-retry')
    report=json.loads(call('check-after-restore-TERM-retry',['--json','check'],accepted=(0,1,2)).stdout)
    require(not [row for row in report['checks'] if row['status'] in ('FAIL','UNKNOWN')
                 and row['id']!='time_sync'],'restore TERM retry left unhealthy local evidence')
    passed.append('actual trusted restore succeeds after both TERM compensation windows')


@contextmanager
def signal_owned_command_on_start(fault, caught):
    require_guest()
    require(caught in (signal.SIGTERM,signal.SIGKILL),'unsupported owned command signal')
    slot=[]
    sent=[]
    errors=[]
    stop=threading.Event()

    def interrupt() -> None:
        deadline=time.monotonic()+60
        try:
            while not stop.wait(0.02):
                require(time.monotonic()<deadline,'owned command signal observation timed out')
                if not slot or fault['attempts']<1:
                    continue
                process=slot[0]
                require(process.poll() is None and os.getsid(process.pid)==process.pid
                        and os.getpgid(process.pid)==process.pid,'owned CLI session is no longer live')
                os.killpg(process.pid,caught)
                sent.append(int(caught))
                return
        except Exception as error:
            errors.append(type(error).__name__)

    observer=threading.Thread(target=interrupt,name='pnm-owned-cli-interrupt')
    observer.start()
    completed=False
    try:
        yield slot
        completed=True
    finally:
        stop.set()
        observer.join(timeout=3)
        require(not observer.is_alive(),'owned command signal observer did not retire')
        # Keep an initiating CLI exception; validate delivery on a normal return.
        if completed:
            require(not errors and sent==[int(caught)],'owned command signal was not delivered exactly once')


def run_interruptions(logs, call, state, binding, links_ready, passed, *, core='xray') -> None:
    require_guest()
    require(core in ('xray','hysteria2'),'unknown interrupted Core')
    peer_core='hysteria2' if core=='xray' else 'xray'
    socket_flag,port=('-lnt',443) if core=='xray' else ('-lnu',8443)

    def listener_ready() -> bool:
        sockets=subprocess.check_output(['ss','-H',socket_flag],text=True,timeout=5)
        return any(line.split()[3].endswith(':'+str(port)) for line in sockets.splitlines())

    for caught in (signal.SIGTERM,signal.SIGKILL):
        before=state(core)
        peer=state(peer_core)
        transactions=set(Path('/var/lib/pnm/transactions').iterdir())
        with start_fault(core,mode='delay') as fault:
            with signal_owned_command_on_start(fault,caught) as slot:
                call('restart-signal-'+caught.name,['restart',core],
                     accepted=(143 if caught==signal.SIGTERM else -9,),process_slot=slot)
                if caught==signal.SIGTERM:
                    ready=listener_ready()
                    (logs/'TERM-return-readiness.json').write_text(json.dumps({
                        'core':core,'listener_present_at_return':ready,'start_attempts':fault['attempts']}))
                    require(ready,'TERM compensation returned before the original runtime listener was ready')
            require(fault['rejected']==0,'signal case unexpectedly rejected Core startup')
            created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
            require(len(created)==1,'interruption created an unexpected transaction count')
            transaction=created.pop()
            events=[line.split('\t')[1] for line in (transaction/'journal.tsv').read_text().splitlines()]
            require('COMMIT' not in events and not (transaction/'commit.env').exists(),
                    'interrupted restart was committed')
            if caught==signal.SIGTERM:
                require(events[-1]=='ROLLED_BACK' and 'ROLLBACK_COMPLETE' in events
                        and 'RECOVERY_REQUIRED' not in events,'TERM recovery did not complete')
                require(fault['attempts'] in (1,2),'unexpected starts during TERM compensation')
                binding(core)
                after=state(core)
                require(after['resources']==before['resources'] and after['invocation']!=before['invocation']
                        and after['enabled']==before['enabled'],'TERM recovery changed original resources or policy')
            else:
                require('ROLLBACK_COMPLETE' not in events and 'ROLLED_BACK' not in events
                        and 'STEP_BEGIN' in events,'SIGKILL interruption lost its unfinished journal')
                # SIGKILL leaves the independently managed service starting.
                # Wait for its real listener so later refusal comparisons do not
                # confuse ongoing fixture startup with PNM command mutation.
                deadline=time.monotonic()+10
                while True:
                    if listener_ready():
                        break
                    require(time.monotonic()<deadline,'post-SIGKILL real listener did not stabilize')
                    time.sleep(0.1)
                after=state(core)
                require(fault['attempts']==1 and after['resources']==before['resources']
                        and after['applied']==before['applied'] and after['invocation']!=before['invocation'],
                        'SIGKILL promoted evidence or changed original resources')
            require(state(peer_core)==peer,'interrupted restart changed peer Core')
        if caught==signal.SIGTERM:
            links_ready('links-after-TERM')
            passed.append('actual TERM preserves143 and completes original-config service recovery without peer changes')
        else:
            passed.append('actual SIGKILL retains unfinished disk journal and prior applied evidence')
            require_commands_blocked(call,state,peer_core,passed)
