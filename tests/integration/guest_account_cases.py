"""Real preexisting identities in a guarded disposable native guest."""
from pathlib import Path
import grp
import pwd
import subprocess

from guest_start_fault import require, require_guest
from guest_recovery_cases import fingerprint


def nss_state() -> dict:
    return {str(path):fingerprint(path)[:4] for path in
            (Path('/etc')/name for name in ('passwd','group','shadow','gshadow'))}


def prepare_accounts() -> dict:
    require_guest()
    for name in ('xray','hysteria'):
        for lookup in (pwd.getpwnam,grp.getgrnam):
            try:
                lookup(name)
            except KeyError:
                pass
            else:
                raise RuntimeError('unexpected identity before account reuse fixture')
    for name in ('xray','hysteria'):
        subprocess.run(['groupadd','--system',name],check=True,capture_output=True,timeout=10)
        subprocess.run(['useradd','--system','--gid',name,'--home-dir','/nonexistent',
                        '--shell','/usr/sbin/nologin','--no-create-home',name],
                       check=True,capture_output=True,timeout=10)
        user=pwd.getpwnam(name)
        group=grp.getgrnam(name)
        require(user.pw_uid>0 and user.pw_gid==group.gr_gid>0
                and user.pw_dir=='/nonexistent' and user.pw_shell=='/usr/sbin/nologin',
                'preexisting service identity does not match policy')
    require(pwd.getpwnam('xray').pw_uid!=pwd.getpwnam('hysteria').pw_uid,
            'preexisting service identities overlap')
    return nss_state()


def require_preserved(baseline: dict) -> None:
    require_guest()
    require(len(baseline)==4 and nss_state()==baseline,'PNM changed preexisting NSS identities')
    # Existing identities must never enter the transaction's created-account
    # ledger, including the deployment that already completed compensation.
    for receipt in Path('/var/lib/pnm/transactions').glob('*/accounts.tsv'):
        require(receipt.is_file() and not receipt.is_symlink() and receipt.stat().st_size==0,
                'PNM claimed a preexisting identity as a created resource')
