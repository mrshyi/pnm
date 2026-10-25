"""Anonymous-file ENOSPC only on the approved disposable VM's bounded disk."""
import errno
import os
from pathlib import Path
import stat
import tempfile
import time

from guest_start_fault import require
from guest_vm_boot import require_approved_vm


class SpaceFault:
    def __init__(self, transaction: Path, private: Path, parent_namespace=None):
        require_approved_vm()  # Must precede all path/allocation operations.
        require(os.stat('/proc/self/ns/mnt').st_ino!=parent_namespace and parent_namespace is not None,
                'disk-space publisher requires its private namespace')
        root=[row.split() for row in Path('/proc/self/mountinfo').read_text().splitlines()
              if row.split()[4]=='/']
        require(len(root)==1 and root[0][root[0].index('-')+1:root[0].index('-')+3]==['ext4','/dev/vda'],
                'disk-space fault requires the disposable VM root disk')
        info=private.lstat()
        require(private.resolve()==private and stat.S_ISDIR(info.st_mode)
                and info.st_uid==0 and stat.S_IMODE(info.st_mode)==0o700,
                'disk-space evidence directory is unprotected')
        require(private.stat().st_dev==transaction.stat().st_dev==Path('/').stat().st_dev,
                'disk-space filler and transaction filesystems differ')
        space=os.statvfs(transaction)
        self.bound=space.f_blocks*space.f_frsize
        require(space.f_frsize==4096 and 0<self.bound<=2*1024**3 and space.f_bavail>0,
                'disk-space filesystem bounds differ')
        self.transaction=transaction
        self.file=tempfile.TemporaryFile(dir=private)
        try:
            info=os.fstat(self.file.fileno())
            require(stat.S_ISREG(info.st_mode) and info.st_uid==0 and info.st_nlink==0
                    and stat.S_IMODE(info.st_mode)==0o600 and info.st_dev==transaction.stat().st_dev,
                    'disk-space filler is not an owned anonymous regular file')
        except BaseException:
            self.file.close()
            raise

    def fill(self) -> dict:
        require_approved_vm()
        offset=0
        deadline=time.monotonic()+20
        # Coarse allocations are cheap unwritten extents. Finish at the actual
        # filesystem block size, with a hard disk-size and monotonic-time bound.
        for step in (1024**2,4096):
            while offset+step<=self.bound:
                require(time.monotonic()<deadline,'disk-space allocation deadline expired')
                try:
                    os.posix_fallocate(self.file.fileno(),offset,step)
                except OSError as error:
                    require(error.errno==errno.ENOSPC,'disk-space allocation has a different cause')
                    break
                offset+=step
        require(offset>0 and os.statvfs(self.transaction).f_bavail==0,
                'anonymous filler did not exhaust available VM blocks')
        return {'private_namespace':True,'fill_errno':errno.ENOSPC}

    def release(self) -> None:
        self.file.close()
        require(os.statvfs(self.transaction).f_bavail>0,'VM space was not recovered after filler close')
