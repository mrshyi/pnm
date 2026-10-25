"""One real EROFS publication in an approved private native guest only."""
from contextlib import contextmanager
import errno
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import uuid

from guest_start_fault import require, require_guest

TARGETS={f'/var/lib/pnm/cores/{core}/{name}'
         for core in ('xray','hysteria2') for name in ('previous','previous.env','applied.env')}
TARGETS.add('/etc/hysteria/config.yaml')


def mounts():
    return [line.split() for line in Path('/proc/self/mountinfo').read_text().splitlines()]


def parent_identity(parent):
    require(parent.resolve()==parent,'publication parent contains a link')
    for path in (parent,*parent.parents):
        info=path.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid==0 and not info.st_mode & 0o022,
                'unprotected publication parent')
    info=parent.lstat()
    return [info.st_dev,info.st_ino]


def unmount_owned(parent, mount_id, identity, *, guard=None):
    guard=guard or require_guest
    guard()
    rows=[row for row in mounts() if row[4]==str(parent)]
    require(len(rows)==1 and int(rows[0][0])==mount_id and parent_identity(parent)==identity,
            'owned publication mount changed')
    subprocess.run(['/usr/bin/umount','--',str(parent)],check=True,capture_output=True,timeout=20)
    require(not any(row[4]==str(parent) for row in mounts()),'owned publication mount remains')


@contextmanager
def readonly_bind(parent, private, identity, parent_namespace, *, guard=None):
    guard=guard or require_guest
    guard()
    info=private.lstat()
    require(private.resolve()==private and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
            'private publication bind required')
    require(os.stat('/proc/self/ns/mnt').st_ino!=parent_namespace,
            'publication move did not enter a new mount namespace')
    require(parent_identity(parent)==identity,'publication parent identity changed')
    rows=mounts()
    require(not any(row[4]==str(parent) for row in rows),'publication parent is already mounted')
    covering=max((row for row in rows if str(parent).startswith(row[4].rstrip('/')+'/')),
                 key=lambda row:len(row[4]))
    require(not any(value.startswith(('shared:','master:'))
                    for value in covering[6:covering.index('-')]),'publication mount propagation is not private')
    mount_id=None
    observed={'private_namespace':True}
    try:
        subprocess.run(['/usr/bin/mount','--bind',str(parent),str(parent)],
                       check=True,capture_output=True,timeout=20)
        current=[row for row in mounts() if row[4]==str(parent)]
        require(len(current)==1 and current[0][0] not in {row[0] for row in rows},
                'new publication mount identity not confirmed')
        mount_id=int(current[0][0])
        (private/'mount-state.json').write_text(json.dumps({'id':mount_id,'identity':identity,
            'namespace':os.stat('/proc/self/ns/mnt').st_ino}))
        subprocess.run(['/usr/bin/mount','-o','remount,bind,ro',str(parent),str(parent)],
                       check=True,capture_output=True,timeout=20)
        current=[row for row in mounts() if row[4]==str(parent)]
        require(len(current)==1 and int(current[0][0])==mount_id and 'ro' in current[0][5].split(','),
                'publication bind is not read-only')
        probe=parent/('.pnm-ero-probe-'+private.name)
        try:
            descriptor=os.open(probe,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
        except OSError as error:
            require(error.errno==errno.EROFS,'publication probe did not observe kernel EROFS')
            observed['probe_errno']=error.errno
        else:
            identity_probe=os.fstat(descriptor)
            os.close(descriptor)
            require(probe.lstat().st_ino==identity_probe.st_ino,'unexpected writable probe replacement')
            probe.unlink()
            raise RuntimeError('publication bind unexpectedly allowed a write')
        yield observed
    finally:
        if mount_id is not None:
            unmount_owned(parent,mount_id,identity,guard=guard)
            observed['mount_removed']=True


def run_move(arguments, wrapper, *, isolated=False):
    require_guest()
    private=Path(wrapper).parent
    info=private.lstat()
    require(private.resolve()==private and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
            'private move launcher required')
    config=json.loads((private/'config.json').read_text())
    target=config['target']
    require(target in TARGETS,'unexpected publication target')
    if (len(arguments)!=4 or arguments[:2]!=['-f','--'] or arguments[-1]!=target
            or (private/'attempted').exists()):
        return subprocess.run(['/usr/bin/mv',*arguments],timeout=20).returncode
    source=Path(arguments[-2])
    parent=Path(target).parent
    require(source.parent==parent and source.name.startswith('.pnm-write.')
            and source.is_file() and not source.is_symlink(),'unexpected publication candidate')
    if not isolated:
        # Only the matching move gets a new private mount namespace.
        return subprocess.run(['/usr/bin/unshare','--mount','--propagation','private',
            '/usr/bin/python3','-B','/opt/guest_io_fault.py',wrapper,*arguments],timeout=90).returncode
    with (private/'attempted').open('x') as stream:
        stream.write('one owned attempt\n')
    with readonly_bind(parent,private,config['parent_identity'],config['mount_namespace']) as observed:
        result=subprocess.run(['/usr/bin/mv',*arguments],capture_output=True,timeout=20)
        observed.update({'move_rc':result.returncode,
                         'readonly_error':b'Read-only file system' in result.stderr})
    require(result is not None and result.returncode==1 and observed['readonly_error'],
            'real publication move did not fail with EROFS')
    (private/'result.json').write_text(json.dumps(observed))
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    return result.returncode


@contextmanager
def readonly_publication(logs, env, target):
    require_guest()
    require(target in TARGETS,'unexpected publication target')
    parent=Path(target).parent
    identity=parent_identity(parent)
    private=logs/('readonly-publication-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    config={'target':target,'parent_identity':identity,
            'mount_namespace':os.stat('/proc/self/ns/mnt').st_ino}
    original_mounts=[row for row in mounts() if row[4]==str(parent)]
    (private/'config.json').write_text(json.dumps(config))
    launcher=private/'mv'
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_io_fault import run_move\nraise SystemExit(run_move(sys.argv[1:],__file__))\n')
    launcher.chmod(0o700)
    original=env['PATH']
    observation={}
    completed=False
    try:
        env['PATH']=str(private)+':'+original
        yield observation
        completed=True
    finally:
        env['PATH']=original
        # The parent created no mount. Never replay a child namespace's mount
        # ID here; only that child may unmount its own recorded bind.
        require(os.stat('/proc/self/ns/mnt').st_ino==config['mount_namespace']
                and [row for row in mounts() if row[4]==str(parent)]==original_mounts,
                'publication fault changed parent namespace mounts')
        if completed:
            receipt=private/'result.json'
            require(receipt.is_file() and not receipt.is_symlink(),
                    'publication refusal receipt missing; inspect protected CLI error output')
            observation.update(json.loads(receipt.read_text()))
            require(observation=={'probe_errno':errno.EROFS,'move_rc':1,
                                  'readonly_error':True,'mount_removed':True,'private_namespace':True},
                    'publication refusal receipt is incomplete')


if __name__=='__main__':
    raise SystemExit(run_move(sys.argv[2:],sys.argv[1],isolated=True))
