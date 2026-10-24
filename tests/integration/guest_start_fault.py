"""Owned systemd start rejection/delay inside an approved native guest."""
from __future__ import annotations

from contextlib import contextmanager
import os
from pathlib import Path
import socket
import subprocess
import threading
import uuid


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def require_guest() -> None:
    mapping=[int(x) for x in Path('/proc/self/uid_map').read_text().split()]
    require(os.geteuid()==0 and len(mapping)==3 and mapping[0]==0 and mapping[1]>0
            and mapping[2]==65536,'start fault requires mapped guest root')
    require(Path('/run/host/container-manager').read_text().strip()=='systemd-nspawn',
            'start fault requires native guest')
    require({p.name for p in Path('/sys/class/net').iterdir()}=={'lo'},'start fault requires private lo')


@contextmanager
def start_fault(core: str, *, mode: str = 'reject-once'):
    require_guest()
    units={'xray':'xray.service','hysteria2':'hysteria-server.service'}
    require(core in units,'unknown start-fault Core')
    require(mode in ('reject-once','reject-twice','delay'),'unknown start-fault mode')
    unit=units[core]
    show=subprocess.run(['systemctl','show',unit,'--property=DropInPaths','--value'],
                        capture_output=True,text=True,timeout=10)
    require(show.returncode==0 and not show.stdout.strip(),'unexpected existing Core drop-in')
    directory=Path('/etc/systemd/system')/(unit+'.d')
    require(not directory.exists() and not directory.is_symlink(),'unexpected start-fault directory')
    program=Path('/opt')/('pnm-start-fault-'+uuid.uuid4().hex+'.py')
    code=("import os,socket,sys,time\n"
          "with socket.create_connection(('127.0.0.1',int(sys.argv[1])),timeout=3) as connection:\n"
          "    answer=connection.recv(1)\n"
          "if answer!=b'.': raise SystemExit(1 if answer==b'!' else 70)\n")
    if mode=='delay':
        code+="time.sleep(3)\nos.execv(sys.argv[2],sys.argv[2:])\n"
    stop=threading.Event()
    lock=threading.Lock()
    state={'attempts':0,'rejected':0,'errors':[]}
    listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    worker=None
    published=False
    program_identity=None
    directory_identity=None
    dropin_identity=None
    dropin=directory/'pnm-test-start.conf'
    policy=b''

    def serve() -> None:
        while not stop.is_set():
            try:
                connection,_address=listener.accept()
            except TimeoutError:
                continue
            except OSError:
                if not stop.is_set():
                    state['errors'].append('start probe accept failed')
                break
            with connection:
                connection.settimeout(2)
                with lock:
                    state['attempts']+=1
                    reject=(mode!='delay' and state['attempts']<=(2 if mode=='reject-twice' else 1))
                    state['rejected']+=int(reject)
                try:
                    connection.sendall(b'!' if reject else b'.')
                except OSError:
                    state['errors'].append('start probe response failed')
                    break

    try:
        listener.bind(('127.0.0.1',0))
        listener.listen(2)
        listener.settimeout(0.2)
        worker=threading.Thread(target=serve,name='pnm-private-start-probe')
        worker.start()
        fd=os.open(program,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o755)
        with os.fdopen(fd,'w') as stream:
            os.fchmod(stream.fileno(),0o755)
            info=os.fstat(stream.fileno())
            program_identity=(info.st_dev,info.st_ino)
            stream.write(code)
        directory.mkdir(mode=0o755)
        directory.chmod(0o755)
        directory_identity=(directory.stat().st_dev,directory.stat().st_ino)
        policy=('[Service]\nRestart=no\nExecStartPre=/usr/bin/python3 -B '+str(program)+' '+
                str(listener.getsockname()[1])+'\n').encode('ascii')
        if mode=='delay':
            command=('/usr/local/bin/xray run -config /usr/local/etc/xray/config.json'
                     if core=='xray' else '/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml')
            policy=('[Service]\nRestart=no\nExecStart=\nExecStart=/usr/bin/python3 -B '+str(program)+' '+
                    str(listener.getsockname()[1])+' '+command+'\n').encode('ascii')
        fd=os.open(dropin,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as stream:
            info=os.fstat(stream.fileno())
            dropin_identity=(info.st_dev,info.st_ino)
            stream.write(policy)
        published=True
        subprocess.run(['systemctl','daemon-reload'],check=True,capture_output=True,timeout=15)
        yield state
    finally:
        cleanup=[]
        if published:
            try:
                require(not directory.is_symlink() and (directory.stat().st_dev,directory.stat().st_ino)==directory_identity,
                        'owned start directory changed')
                require(not dropin.is_symlink() and (dropin.stat().st_dev,dropin.stat().st_ino)==dropin_identity
                        and dropin.read_bytes()==policy,'owned start drop-in changed')
                dropin.unlink()
                directory.rmdir()
                subprocess.run(['systemctl','daemon-reload'],check=True,capture_output=True,timeout=15)
            except Exception:
                cleanup.append('start drop-in cleanup failed')
        elif directory_identity is not None and directory.exists():
            try:
                require(not directory.is_symlink() and (directory.stat().st_dev,directory.stat().st_ino)==directory_identity,
                        'partial start directory changed')
                directory.rmdir()
            except Exception:
                cleanup.append('partial start directory retained')
        stop.set()
        try:
            listener.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        listener.close()
        if worker is not None:
            worker.join(timeout=3)
            if worker.is_alive():
                cleanup.append('start probe thread retained')
        if program_identity is not None and (program.exists() or program.is_symlink()):
            try:
                require(not program.is_symlink() and (program.stat().st_dev,program.stat().st_ino)==program_identity
                        and program.read_text()==code,'owned start probe changed')
                program.unlink()
            except Exception:
                cleanup.append('start probe program retained')
        require(not cleanup and not state['errors'],'start fault cleanup or transport failed')
