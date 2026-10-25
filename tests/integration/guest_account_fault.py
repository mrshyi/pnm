"""Real shadow account creation refusal in a private child mount namespace."""
from contextlib import contextmanager
import errno
import grp
import json
import os
from pathlib import Path
import pwd
import stat
import subprocess
import sys
import uuid

from guest_start_fault import require, require_guest
from guest_io_fault import mounts, parent_identity, readonly_bind


ARGUMENTS={
    'groupadd':['--system','hysteria'],
    'useradd':['--system','--gid','hysteria','--home-dir','/nonexistent',
               '--shell','/usr/sbin/nologin','--no-create-home','hysteria'],
}


def run_account_tool(arguments, wrapper, *, isolated=False):
    require_guest()
    private=Path(wrapper).parent
    info=private.lstat()
    require(private.resolve()==private and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
            'private account launcher required')
    program=Path(wrapper).name
    require(program in ARGUMENTS,'unexpected account creation tool')
    if arguments!=ARGUMENTS[program] or (private/'attempted').exists():
        return subprocess.run(['/usr/sbin/'+program,*arguments],timeout=20).returncode
    config=json.loads((private/'config.json').read_text())
    require(config['program']==program and pwd.getpwnam('xray').pw_uid>0
            and grp.getgrnam('xray').gr_gid>0,'account failure lacks prior real Xray identity')
    try:
        pwd.getpwnam('hysteria')
    except KeyError:
        pass
    else:
        raise RuntimeError('refusal target already exists')
    try:
        target_group=grp.getgrnam('hysteria')
    except KeyError:
        require(program=='groupadd','user creation target group is missing')
    else:
        require(program=='useradd' and target_group.gr_gid>0,
                'group creation target already exists')
    if not isolated:
        require(os.stat('/proc/self/ns/mnt').st_ino==config['mount_namespace'],
                'account launcher parent namespace changed')
        return subprocess.run(['/usr/bin/unshare','--mount','--propagation','private',
            '/usr/bin/python3','-B','/opt/guest_account_fault.py',wrapper,*arguments],timeout=50).returncode
    with (private/'attempted').open('x') as stream:
        stream.write('one real shadow tool\n')
    with readonly_bind(Path('/etc'),private,config['parent_identity'],config['mount_namespace']) as observed:
        result=subprocess.run(['/usr/sbin/'+program,*arguments],capture_output=True,timeout=20)
        require(result.returncode>0 and not result.stdout and result.stderr,
                'real shadow tool did not refuse under read-only etc')
        observed.update({'tool_rc':result.returncode,'prior_xray_identity':True})
    (private/'result.json').write_text(json.dumps(observed))
    sys.stderr.buffer.write(result.stderr)
    return result.returncode


@contextmanager
def readonly_account_creation(logs, env, program):
    require_guest()
    require(program in ARGUMENTS,'unexpected account creation tool')
    private=logs/('readonly-account-'+uuid.uuid4().hex)
    private.mkdir(mode=0o700)
    namespace=os.stat('/proc/self/ns/mnt').st_ino
    baseline=[row for row in mounts() if row[4]=='/etc']
    (private/'config.json').write_text(json.dumps({'program':program,
        'mount_namespace':namespace,'parent_identity':parent_identity(Path('/etc'))}))
    launcher=private/program
    launcher.write_text('#!/usr/bin/python3 -B\nimport sys\nsys.path.insert(0,\'/opt\')\n'
        'from guest_account_fault import run_account_tool\nraise SystemExit(run_account_tool(sys.argv[1:],__file__))\n')
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
        require(os.stat('/proc/self/ns/mnt').st_ino==namespace
                and [row for row in mounts() if row[4]=='/etc']==baseline,
                'account refusal changed parent namespace or mounts')
        if completed:
            observation.update(json.loads((private/'result.json').read_text()))
            require(observation['private_namespace'] and observation['probe_errno']==errno.EROFS
                    and observation['mount_removed'] and observation['tool_rc']>0
                    and observation['prior_xray_identity'],'account refusal receipt incomplete')


if __name__=='__main__':
    raise SystemExit(run_account_tool(sys.argv[2:],sys.argv[1],isolated=True))
