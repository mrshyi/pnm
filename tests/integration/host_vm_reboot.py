"""Owned native KVM disk/serial controller for the existing two-boot guest worker."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import select
import shutil
import stat
import subprocess
import time
import uuid


def require(condition, label):
    if not condition:
        raise RuntimeError(label)


def approve_ready(record, expected, instance, host_boot, previous_boot):
    scope='pnm-reboot' if previous_boot else 'pnm-lifecycle'
    require(record.get('schema')==1 and record.get('kind')=='boot-ready'
            and record.get('instance')==instance, 'VM serial identity differs')
    received=record.get('scope') if record.get('scope') in ('pnm-lifecycle','pnm-reboot','boot-only') else 'other'
    require(received==scope,'VM serial scope differs: expected='+scope+' received='+received)
    boot=record.get('boot_id','')
    require(re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',boot) and boot not in (host_boot,previous_boot),
            'VM did not establish a new independent kernel boot')
    for name,value in expected.items():
        require(record.get(name)==value,'VM readiness differs from approved metadata')
    require(record.get('network_only_loopback') is True
            and record.get('machine_id_differs_from_host') is True
            and record.get('pnm_absent') is (previous_boot is None)
            and record.get('vm_detected') in ('kvm','qemu')
            and record.get('manager_state')=='running','VM readiness guard failed')
    return {'schema':1,'action':'approve-'+scope,'instance':instance,'boot_id':boot}


def run_vm(root, work):
    require(os.geteuid()==0 and os.environ.get('PNM_RUN_VM_TESTS')=='1'
            and os.environ.get('GITHUB_ACTIONS')=='true'
            and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted',
            'VM preparation requires opted-in disposable CI root')
    machine=platform.machine()
    require(machine in ('x86_64','aarch64'),'unsupported native VM architecture')
    require(root==root.resolve() and root.is_dir() and work==work.resolve()
            and stat.S_IMODE(work.stat().st_mode)==0o700 and work.stat().st_uid==0,
            'private owned VM paths required')
    with open('/dev/kvm','r+b',buffering=0) as kvm:
        require(fcntl.ioctl(kvm,0xAE00)==12,'KVM API unavailable')
        descriptor=fcntl.ioctl(kvm,0xAE01,0)
        os.close(descriptor)
    qemu=Path(shutil.which('qemu-system-x86_64' if machine=='x86_64' else 'qemu-system-aarch64') or '')
    require(qemu.is_file(),'native QEMU executable missing')
    qemu=qemu.resolve()
    require(qemu.stat().st_uid==0 and not qemu.stat().st_mode & 0o022,'untrusted QEMU executable')
    kernels=sorted((root/'boot').glob('vmlinuz-*'))
    require(len(kernels)==1,'one package-verified guest kernel required')
    release=kernels[0].name.removeprefix('vmlinuz-');kernel=kernels[0].resolve()
    initrd=(root/'boot'/('initrd.img-'+release)).resolve()
    require(kernel.is_relative_to(root) and initrd.is_relative_to(root)
            and kernel.is_file() and initrd.is_file(),'guest kernel/initrd missing')
    root_uuid=str(uuid.uuid4());instance=uuid.uuid4().hex
    host_boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    repo=Path(__file__).resolve().parents[2]
    for name in ('guest_vm_boot.py','guest_vm_lifecycle.py'):
        target=root/'opt'/name
        require(not target.exists() and not target.is_symlink(),'VM worker destination occupied')
        shutil.copyfile(repo/'tests/integration'/name,target)
        target.chmod(0o700)
    expected={'schema':1,'backend':'qemu-kvm','architecture':machine,'kernel_release':release,
              'root_uuid':root_uuid,'worker_sha256':hashlib.sha256((root/'opt/guest_vm_boot.py').read_bytes()).hexdigest(),
              'host_machine_id_sha256':hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()}
    record=root/'opt/pnm-vm-expected.json'
    with record.open('x') as stream: json.dump(expected,stream)
    record.chmod(0o600)
    unit=root/'etc/systemd/system/pnm-boot-probe.service'
    require(unit.is_file() and not unit.is_symlink(),'owned VM probe unit missing')
    unit.write_text('[Unit]\nDescription=PNM independent VM acceptance\nAfter=basic.target\n'
                    '[Service]\nExecStart=/usr/bin/python3 -B /opt/guest_vm_lifecycle.py\n'
                    'RuntimeMaxSec=1200\nStandardError=tty\nTTYPath=/dev/'+('ttyS0' if machine=='x86_64' else 'ttyAMA0')+
                    '\n[Install]\nWantedBy=multi-user.target\n')
    for serial in ('ttyS0','ttyAMA0'):
        mask=root/'etc/systemd/system'/('serial-getty@'+serial+'.service')
        require(not mask.exists() and not mask.is_symlink(),'VM console mask occupied')
        mask.symlink_to('/dev/null')
    modules=root/'etc/modules-load.d'
    modules.mkdir(exist_ok=True)
    require(modules.resolve()==modules,'unsafe VM modules directory')
    with (modules/'pnm-fwcfg.conf').open('x') as stream: stream.write('qemu_fw_cfg\n')
    disk=work/'owned-vm.raw'
    fd=os.open(disk,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        os.ftruncate(fd,2*1024**3)
        subprocess.run(['mkfs.ext4','-q','-F','-U',root_uuid,'-d',str(root),str(disk)],check=True,timeout=180)
        info=os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_uid==0 and info.st_nlink==1
                and info.st_size==2*1024**3,'owned disk identity changed')
        console='ttyS0' if machine=='x86_64' else 'ttyAMA0'
        board='q35' if machine=='x86_64' else 'virt,gic-version=host'
        args=[str(qemu),'-nodefaults','-no-user-config','-machine',board+',accel=kvm,dump-guest-core=off',
              '-cpu','host','-m','1024','-smp','2','-display','none','-monitor','none','-serial','stdio',
              '-nic','none','-kernel',str(kernel),'-initrd',str(initrd),'-append',
              'root=UUID='+root_uuid+' rootfstype=ext4 rw console='+console+' quiet loglevel=3 systemd.show_status=no',
              '-add-fd',f'fd={fd},set=1,opaque=pnm-{instance}',
              '-blockdev','driver=file,filename=/dev/fdset/1,node-name=pnm-file,read-only=off,auto-read-only=off',
              '-blockdev','driver=raw,file=pnm-file,node-name=pnm-disk',
              '-device','virtio-blk-pci,drive=pnm-disk']
        for name,value in (('instance',instance),('host-boot-id',host_boot),('root-uuid',root_uuid)):
            args+=['-fw_cfg','name=opt/pnm/'+name+',string='+value]
        databases={p:hashlib.sha256(Path(p).read_bytes()).digest()
                   for p in ('/etc/passwd','/etc/group','/etc/shadow','/etc/gshadow','/var/lib/dpkg/status')}
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
        result=[];approved=set();pending=b'';previous_boot=None;written=0
        os_file=(root/'etc/os-release').resolve()
        require(os_file.is_relative_to(root),'unsafe VM OS metadata')
        os_release=dict(line.split('=',1) for line in os_file.read_text().splitlines() if '=' in line)
        expected_ready={'kernel_release':release,'root_uuid':root_uuid,'architecture':machine,
                        'os_id':os_release['ID'].strip(chr(34)),'os_version':os_release['VERSION_ID'].strip(chr(34))}
        with (work/'vm-serial.private.log').open('xb') as log, subprocess.Popen(
                args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                pass_fds=(fd,),start_new_session=True,bufsize=0) as process:
            start_identity=Path(f'/proc/{process.pid}/stat').read_text().rsplit(')',1)[1].split()[19]
            try:
                deadline=time.monotonic()+1500
                while time.monotonic()<deadline:
                    ready,_,_=select.select([process.stdout],[],[],0.5)
                    if not ready:
                        if process.poll() is not None: break
                        continue
                    data=os.read(process.stdout.fileno(),4096)
                    if not data: break
                    written+=len(data);require(written<=16*1024**2,'VM serial output exceeded bound')
                    log.write(data);pending+=data
                    while b'\n' in pending:
                        line,_,pending=pending.partition(b'\n')
                        if not line.startswith(b'PNM_VM '):
                            if line.strip() in (b'PNM_VM_EMIT_ERROR OSError',b'PNM_VM_EMIT_ERROR RuntimeError'):
                                print(line.strip().decode('ascii'),flush=True)
                            if b'PNM_VM ' in line:
                                print(json.dumps({'vm_protocol_frame_with_console_prefix':True}),flush=True)
                            continue
                        message=json.loads(line[7:].strip())
                        require(message.get('instance')==instance,'foreign VM serial message')
                        if message.get('kind')=='boot-ready' and message['boot_id'] not in approved:
                            require(Path(f'/proc/{process.pid}/stat').read_text().rsplit(')',1)[1].split()[19]==start_identity,
                                    'QEMU process identity changed')
                            require(Path(f'/proc/{process.pid}/exe').resolve()==qemu,'QEMU executable changed')
                            require(Path(f'/proc/{process.pid}/cmdline').read_bytes().split(b'\0')[:-1]==[os.fsencode(a) for a in args],
                                    'QEMU command/drive identity changed')
                            disk_seen=False
                            for entry in Path(f'/proc/{process.pid}/fd').iterdir():
                                try: candidate=entry.stat()
                                except FileNotFoundError: continue
                                disk_seen |= (candidate.st_dev,candidate.st_ino)==(info.st_dev,info.st_ino)
                            require(disk_seen,'QEMU does not own approved disk')
                            print(json.dumps({'vm_ready':True,'approved_boots':len(approved),'results':len(result),
                                'scope':message.get('scope') if message.get('scope') in ('pnm-lifecycle','pnm-reboot','boot-only') else 'other'}),flush=True)
                            approval=approve_ready(message,expected_ready,instance,host_boot,previous_boot)
                            process.stdin.write(b'PNM_VM_APPROVE '+json.dumps(approval).encode()+b'\n')
                            approved.add(message['boot_id'])
                        elif message.get('kind')=='boot-result':
                            print(json.dumps({'vm_boot_result':True,'passed':message.get('passed') is True,
                                'host_approval_seen':message.get('host_approval_seen') is True,
                                'scope':message.get('scope') if message.get('scope') in ('pnm-lifecycle','pnm-reboot') else 'other',
                                'stage':message.get('stage') if message.get('stage') in ('serial setup','host approval','approved PNM acceptance','boot evidence persistence') else 'other',
                                'error_class':message.get('error_class') if message.get('error_class') in ('RuntimeError','GuestRefusal','OSError','TimeoutExpired') else 'other'}),flush=True)
                            require(message.get('passed') is True and message.get('host_approval_seen') is True
                                    and message.get('boot_id') in approved,'VM acceptance failed; private evidence retained')
                            prior=next((item for item in result if item['boot_id']==message['boot_id']),None)
                            if prior is not None:
                                require(message==prior,'repeated VM result differs')
                            else:
                                require(message.get('scope')==('pnm-lifecycle' if not result else 'pnm-reboot'), 'VM result scope differs')
                                result.append(message)
                                previous_boot=message['boot_id']
                            receipt={'schema':1,'action':'result-received-'+message['scope'],
                                     'instance':instance,'boot_id':message['boot_id']}
                            process.stdin.write(b'PNM_VM_RECEIPT '+json.dumps(receipt).encode()+b'\n')
                    require(len(pending)<65536,'VM serial line exceeded bound')
                process.wait(timeout=30)
                require(process.returncode==0 and len(result)==2 and len(approved)==2,'VM did not complete two verified boots')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill();process.wait(timeout=5)
                if len(result)!=2:
                    current=disk.stat()
                    require((current.st_dev,current.st_ino)==(info.st_dev,info.st_ino), 'owned diagnostic disk changed')
                    replay=subprocess.run(['e2fsck','-p','-E','journal_only',str(disk)],capture_output=True,timeout=30)
                    print(json.dumps({'vm_owned_disk_journal_replay_exit':replay.returncode}),flush=True)
                    for boot in sorted(approved):
                        probe=subprocess.run(['debugfs','-R','cat /var/tmp/pnm-vm-trace-'+boot,str(disk)],
                                             capture_output=True,timeout=10)
                        labels={'serial_setup','ready','approved','action_begin','action_done','persist_begin',
                                'persist_done','persist_error','emit_begin','emit_done','emit_error','power_begin'}
                        print(json.dumps({'vm_worker_stages':[n for n in probe.stdout.decode('ascii',errors='replace').splitlines() if n in labels]}),flush=True)
                    for scope in ('pnm-lifecycle','pnm-reboot'):
                        probe=subprocess.run(['debugfs','-R','cat /var/tmp/pnm-vm-'+scope+'-result.json',str(disk)],
                            capture_output=True,timeout=10)
                        try:
                            persisted=json.loads(probe.stdout)
                        except (ValueError,UnicodeError):
                            print(json.dumps({'vm_persisted_result':scope,'present':False,'bytes':len(probe.stdout),
                                'read_exit':probe.returncode,'lookup_missing':b'File not found' in probe.stderr}),flush=True)
                            continue
                        print(json.dumps({'vm_persisted_result':scope,'present':True,
                            'passed':persisted.get('passed') is True,
                            'stage':persisted.get('stage') if persisted.get('stage') in ('host approval','approved PNM acceptance','boot evidence persistence') else 'other',
                            'error_class':persisted.get('error_class') if persisted.get('error_class') in ('RuntimeError','GuestRefusal','OSError','TimeoutExpired','FileNotFoundError') else 'other',
                            'acceptance_present':isinstance(persisted.get('acceptance'),dict)}),flush=True)
                    log.flush()
                    raw=(work/'vm-serial.private.log').read_bytes()
                    print(json.dumps({'qemu_exit_code':process.returncode,
                        'qemu_error_categories':[label for label,marker in (
                            ('kvm_run',b'KVM internal error'),('kvm_entry',b'KVM entry failed'),
                            ('disk_io',b'Input/output error'),('no_space',b'No space left on device'),
                            ('signal',b'terminating on signal'),('guest_poweroff',b'Power down'),
                            ('guest_reboot',b'Restarting system')) if marker in raw],
                        'vm_serial_has_result':b'boot-result' in raw,
                        'vm_serial_has_emit_error':b'PNM_VM_EMIT_ERROR' in raw,
                        'vm_worker_exception_lines':[int(n) for n in re.findall(rb'File "/opt/guest_vm_boot.py", line ([0-9]+)',raw)],
                        'vm_exception_classes':sorted({n.decode('ascii') for n in re.findall(
                            rb'\b(NameError|TypeError|ValueError|FileNotFoundError|UnboundLocalError|RuntimeError|PermissionError):',raw)})}),flush=True)
                require(all(hashlib.sha256(Path(p).read_bytes()).digest()==v for p,v in databases.items()),
                        'VM test changed host account/package databases')
        public={'passed':True,'backend':'qemu-kvm','architecture':machine,'independent_boots':2,
                'lifecycle_checks':result[0]['acceptance']['mainflow_checks'],
                'reboot_checks':result[1]['acceptance']['reboot_checks'],'host_databases_unchanged':True}
        (work/'vm-result.json').write_text(json.dumps(public,indent=2)+'\n')
        print(json.dumps(public),flush=True)
        return public
    finally:
        os.close(fd)
