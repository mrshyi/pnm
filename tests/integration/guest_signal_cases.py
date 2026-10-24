"""Interrupt only this guest test's owned CLI process group during real restart."""
from pathlib import Path
import json
import os
import signal
import subprocess
import threading
import time

from guest_start_fault import require, require_guest, start_fault
from guest_recovery_cases import require_commands_blocked


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
            slot=[]
            sent=[]
            errors=[]
            stop=threading.Event()

            def interrupt() -> None:
                deadline=time.monotonic()+60
                try:
                    while not stop.wait(0.02):
                        require(time.monotonic()<deadline,'restart signal observation timed out')
                        if not slot or fault['attempts']<1:
                            continue
                        process=slot[0]
                        # No name lookup or namespace traversal: target only the
                        # exact child/session created by the call helper below.
                        require(process.poll() is None and os.getsid(process.pid)==process.pid
                                and os.getpgid(process.pid)==process.pid,'owned CLI session is no longer live')
                        os.killpg(process.pid,caught)
                        sent.append(int(caught))
                        return
                except Exception as error:
                    errors.append(type(error).__name__)

            observer=threading.Thread(target=interrupt,name='pnm-owned-cli-interrupt')
            observer.start()
            try:
                call('restart-signal-'+caught.name,['restart',core],
                     accepted=(143 if caught==signal.SIGTERM else -9,),process_slot=slot)
                if caught==signal.SIGTERM:
                    ready=listener_ready()
                    (logs/'TERM-return-readiness.json').write_text(json.dumps({
                        'core':core,'listener_present_at_return':ready,'start_attempts':fault['attempts']}))
                    require(ready,'TERM compensation returned before the original runtime listener was ready')
            finally:
                stop.set()
                observer.join(timeout=3)
            require(not observer.is_alive() and not errors and sent==[int(caught)],
                    'owned restart signal was not delivered and retired exactly once')
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
