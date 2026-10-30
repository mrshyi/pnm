"""Guest-only nonce handshake for an independently booted supported Linux VM."""
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import select
import stat
import subprocess
import sys
import termios
import time
from typing import Callable


class GuestRefusal(RuntimeError):
    """Identity is insufficient to permit serial or power operations."""


@dataclass(frozen=True)
class VmIdentity:
    instance: str
    boot_id: str
    root_uuid: str
    kernel_release: str
    host_machine_id_sha256: str


def guest_operating_system() -> tuple[str,str]:
    release=platform.freedesktop_os_release()
    identity=(release.get('ID'),release.get('VERSION_ID'))
    if identity not in (('debian','12'),('debian','13'),('ubuntu','22.04'),('ubuntu','24.04')):
        raise GuestRefusal('unexpected independent guest operating system')
    return identity


def require_vm() -> VmIdentity:
    """All checks are read-only; failure must never call power or serial APIs."""
    message='VM worker requires the approved independent guest'
    firmware=Path('/sys/firmware/qemu_fw_cfg/by_name/opt/pnm')
    if (sys.platform!='linux' or os.geteuid()!=0 or sys.flags.optimize
            or 'microsoft' in platform.release().lower() or not (firmware/'instance/raw').is_file()):
        raise GuestRefusal(message)
    try:
        expected_path=Path('/opt/pnm-vm-expected.json')
        info=expected_path.lstat()
        if (expected_path.resolve()!=expected_path or not stat.S_ISREG(info.st_mode)
                or info.st_uid!=0 or stat.S_IMODE(info.st_mode)!=0o600
                or info.st_nlink!=1 or info.st_size>4096):
            raise ValueError('expected record protection')
        expected=json.loads(expected_path.read_text())
        if (set(expected) not in ({'schema','backend','kernel_release','root_uuid',
                           'worker_sha256','host_machine_id_sha256'},
                          {'schema','backend','kernel_release','root_uuid',
                           'worker_sha256','host_machine_id_sha256','architecture'})
                or type(expected['schema']) is not int or expected['schema']!=1
                or expected['backend']!='qemu-kvm'):
            raise ValueError('expected record schema')
        architecture=platform.machine()
        if architecture not in ('x86_64','aarch64') or expected.get('architecture', 'x86_64')!=architecture:
            raise ValueError('guest architecture mismatch')
        vendor=(Path('/sys/class/dmi/id/sys_vendor').read_text().strip()=='QEMU'
                if architecture=='x86_64' else
                b'linux,dummy-virt' in Path('/sys/firmware/devicetree/base/compatible').read_bytes().split(b'\x00'))
        blobs={}
        for name in ('instance','host-boot-id','root-uuid'):
            with (firmware/name/'raw').open('rb') as stream:
                blobs[name]=stream.read(129).decode('ascii')
        guid=r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        if (not re.fullmatch(r'[0-9a-f]{32}',blobs['instance'])
                or not re.fullmatch(guid,blobs['host-boot-id'])
                or not re.fullmatch(guid,blobs['root-uuid']) or not re.fullmatch(guid,boot_id)
                or blobs['host-boot-id']==boot_id or blobs['root-uuid']!=expected['root_uuid']
                or platform.release()!=expected['kernel_release']
                or not re.fullmatch(r'[0-9a-f]{64}',expected['host_machine_id_sha256'])
                or hashlib.sha256(Path(__file__).read_bytes()).hexdigest()!=expected['worker_sha256']
                or Path('/proc/1/comm').read_text().strip()!='systemd'
                or not vendor
                or sorted(path.name for path in Path('/sys/class/net').iterdir())!=['lo']):
            raise ValueError('guest identity mismatch')
        return VmIdentity(blobs['instance'],boot_id,blobs['root-uuid'],platform.release(),
                          expected['host_machine_id_sha256'])
    except (OSError,ValueError,TypeError,KeyError) as error:
        raise GuestRefusal(message) from error


def require_approved_vm() -> VmIdentity:
    """Mutation helpers require this boot's post-handshake private approval."""
    identity=require_vm()
    try:
        path=Path('/run/pnm-vm-approved.json')
        info=path.lstat()
        if (path.resolve()!=path or not stat.S_ISREG(info.st_mode) or info.st_uid!=0
                or stat.S_IMODE(info.st_mode)!=0o600 or info.st_nlink!=1 or info.st_size>2048):
            raise ValueError('approval protection')
        record=json.loads(path.read_text())
        if (record!={'schema':1,'instance':identity.instance,'boot_id':identity.boot_id,
                     'scope':'pnm-lifecycle'} or type(record.get('schema')) is not int):
            raise ValueError('approval identity')
        return identity
    except (OSError,ValueError,TypeError) as error:
        raise GuestRefusal('VM mutation requires this boot approval') from error


def wait_result_receipt(descriptor: int, emit: Callable, result: dict) -> None:
    expected={'schema':1,'action':'result-received-'+result['scope'],
              'instance':result['instance'],'boot_id':result['boot_id']}
    deadline=time.monotonic()+30
    next_emit=0.0
    pending=b''
    while time.monotonic()<deadline:
        now=time.monotonic()
        if now>=next_emit:
            emit(result)
            next_emit=now+2
        if not select.select([descriptor],[],[],0.2)[0]:
            continue
        try:
            pending+=os.read(descriptor,1024)
        except BlockingIOError:
            continue
        if len(pending)>4096:
            raise RuntimeError('VM result receipt exceeded bound')
        while b'\n' in pending:
            line,_,pending=pending.partition(b'\n')
            if not line.startswith(b'PNM_VM_RECEIPT '):
                continue
            try:
                received=json.loads(line.removeprefix(b'PNM_VM_RECEIPT ').strip())
            except (ValueError,UnicodeError):
                continue
            if isinstance(received,dict) and type(received.get('schema')) is int and received==expected:
                return
    raise RuntimeError('VM result receipt was not received')


def main(*, action: Callable[[],dict] | None=None, scope: str='boot-only',
         power_action: str='poweroff', require_result_ack: bool=False) -> None:
    identity=require_vm()
    if (scope not in ('boot-only','pnm-lifecycle','pnm-reboot','deployment-abrupt','deployment-recovery')
            or (action is None)!=(scope=='boot-only') or power_action not in ('poweroff','reboot')):
        raise GuestRefusal('VM action scope is invalid')
    # The identity guard above must remain before every serial/power operation.
    descriptor=None
    emit=None
    result={'schema':1,'kind':'boot-result','instance':identity.instance,
            'boot_id':identity.boot_id,'passed':False,'scope':scope}
    trace_fd=os.open('/var/tmp/pnm-vm-trace-'+identity.boot_id,
                     os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    def trace(label: str) -> None:
        try:
            os.write(trace_fd,(label+'\n').encode('ascii'))
            os.fsync(trace_fd)
        except OSError:
            pass  # Temporary diagnostics must not change guest power/control flow.
    stage='serial setup'
    try:
        trace('serial_setup')
        serial='/dev/ttyS0' if platform.machine()=='x86_64' else '/dev/ttyAMA0'
        serial_device=(4,64) if platform.machine()=='x86_64' else (204,64)
        descriptor=os.open(serial,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK|os.O_NOFOLLOW)
        info=os.fstat(descriptor)
        if not stat.S_ISCHR(info.st_mode) or (os.major(info.st_rdev),os.minor(info.st_rdev))!=serial_device:
            raise RuntimeError('unexpected guest serial device')
        attributes=termios.tcgetattr(descriptor)
        attributes[0]&=~(termios.ICRNL|termios.INLCR|termios.IGNCR)
        attributes[3]&=~(termios.ECHO|termios.ICANON|termios.ISIG|termios.IEXTEN)
        attributes[6][termios.VMIN]=0
        attributes[6][termios.VTIME]=0
        termios.tcsetattr(descriptor,termios.TCSANOW,attributes)

        def emit(record: dict) -> None:
            message=('\nPNM_VM '+json.dumps(record,sort_keys=True)+'\n').encode()
            if len(message)>2048:
                raise RuntimeError('bounded VM protocol record exceeded')
            deadline=time.monotonic()+3
            while message:
                if time.monotonic()>=deadline:
                    raise RuntimeError('VM serial write timed out')
                _,writable,_=select.select([],[descriptor],[],0.2)
                if writable:
                    try:
                        sent=os.write(descriptor,message)
                        message=message[sent:]
                    except BlockingIOError:
                        pass
            termios.tcdrain(descriptor)

        stage='fresh managed-resource absence'
        absent=not any(Path(name).exists() or Path(name).is_symlink()
                       for name in ('/etc/pnm','/usr/local/bin/xray','/usr/local/bin/hysteria'))
        if absent!=(scope not in ('pnm-reboot','deployment-recovery')):
            raise RuntimeError('guest managed-resource baseline differs from scope')
        stage='supported operating-system identity'
        os_id,os_version=guest_operating_system()
        stage='independent hypervisor detection'
        detected=subprocess.run(['systemd-detect-virt','--vm'],capture_output=True,text=True,timeout=10)
        if detected.returncode or detected.stdout.strip() not in ('kvm','qemu'):
            raise RuntimeError('independent guest hypervisor not detected')
        stage='service manager readiness'
        deadline=time.monotonic()+30
        manager='starting'
        while time.monotonic()<deadline:
            probe=subprocess.run(['systemctl','is-system-running'],capture_output=True,text=True,timeout=5)
            manager=probe.stdout.strip()
            if manager=='running':
                break
            time.sleep(0.2)
        if manager!='running':
            raise RuntimeError('independent guest manager did not reach running')
        stage='machine identity isolation'
        machine_id=hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()
        if machine_id==identity.host_machine_id_sha256:
            raise RuntimeError('guest reused host machine identity')
        ready={'schema':1,'kind':'boot-ready','instance':identity.instance,'boot_id':identity.boot_id,
               'kernel_release':identity.kernel_release,'root_uuid':identity.root_uuid,'architecture':platform.machine(),
               'os_id':os_id,'os_version':os_version,'vm_detected':detected.stdout.strip(),
               'manager_state':manager,'network_only_loopback':True,'pnm_absent':absent,'scope':scope,
               'machine_id_differs_from_host':True}
        trace('ready')
        stage='host approval'
        pending=bytearray()
        approved=False
        deadline=time.monotonic()+60
        next_emit=0.0
        approval={'schema':1,'action':'approve-'+scope,'instance':identity.instance,
                  'boot_id':identity.boot_id}
        while time.monotonic()<deadline and not approved:
            now=time.monotonic()
            if now>=next_emit:
                emit(ready)
                next_emit=now+2
            readable,_,_=select.select([descriptor],[],[],0.2)
            if not readable:
                continue
            try:
                pending.extend(os.read(descriptor,1024))
            except BlockingIOError:
                continue
            if len(pending)>4096:
                raise RuntimeError('VM approval protocol exceeded bound')
            while b'\n' in pending:
                line,_,remainder=pending.partition(b'\n')
                pending=bytearray(remainder)
                if not line.startswith(b'PNM_VM_APPROVE '):
                    continue
                try:
                    candidate=json.loads(line.removeprefix(b'PNM_VM_APPROVE ').strip())
                    approved=(isinstance(candidate,dict) and type(candidate.get('schema')) is int
                              and candidate==approval)
                except (ValueError,UnicodeError):
                    continue
        if not approved:
            raise RuntimeError('VM boot approval was not received')
        trace('approved')
        if action is not None:
            stage='approved PNM acceptance'
            proof={'schema':1,'instance':identity.instance,'boot_id':identity.boot_id,
                   'scope':'pnm-lifecycle'}
            descriptor_proof=os.open('/run/pnm-vm-approved.json',
                os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_WRONLY,0o600)
            with os.fdopen(descriptor_proof,'w') as stream:
                json.dump(proof,stream)
                stream.flush()
                os.fsync(stream.fileno())
            trace('action_begin')
            result['acceptance']=action()
            trace('action_done')
        result.update({'passed':True,'host_approval_seen':True,'kernel_release':identity.kernel_release,
            'root_uuid':identity.root_uuid,'manager_state':manager,'network_only_loopback':True,
            'pnm_absent':absent,'independent_boot_id':True,'machine_id_differs_from_host':True})
    except Exception as error:
        result.update({'stage':stage,'error_class':type(error).__name__})
        if isinstance(error,OSError) and type(error.errno) is int:
            result['errno']=error.errno
    finally:
        # This block is reachable only after the independent-guest guard passed.
        trace('persist_begin')
        path=Path('/var/tmp/pnm-vm-'+('boot' if scope=='boot-only' else scope)+'-result.json')
        try:
            output=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            with os.fdopen(output,'w') as stream:
                json.dump(result,stream,sort_keys=True)
                stream.flush()
                os.fsync(stream.fileno())
            directory=os.open('/var/tmp',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
            trace('persist_done')
        except OSError as error:
            trace('persist_error')
            result.update({'passed':False,'stage':'boot evidence persistence',
                           'error_class':type(error).__name__})
        finally:
            try:
                if emit is not None:
                    try:
                        trace('emit_begin')
                        if require_result_ack:
                            wait_result_receipt(descriptor,emit,result)
                        else:
                            emit(result)
                        trace('emit_done')
                    except (OSError,RuntimeError) as error:
                        trace('emit_error')
                        result['passed']=False
                        print('PNM_VM_EMIT_ERROR '+type(error).__name__,file=sys.stderr,flush=True)
            finally:
                try:
                    if descriptor is not None:
                        os.close(descriptor)
                finally:
                    trace('power_begin')
                    subprocess.run(['systemctl','--no-block',power_action if result.get('passed') else 'poweroff'],
                                   capture_output=True,timeout=10)


if __name__=='__main__':
    try:
        main()
    except GuestRefusal:
        raise SystemExit(77) from None
