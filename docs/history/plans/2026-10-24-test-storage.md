# Private test storage for remaining native cases

Completed with retained evidence. C fell below the2GiB guest-copy gate; D had
approximately20.7GiB available. No earlier fixture was deleted.

A Windows-only ACL did not isolate Linux users: a non-secret probe was readable
by nobody. Therefore no plaintext guest image was retained by pathname on DrvFS.
A new anonymous TemporaryFile on D has link count0 and is accessible only through
root's existing FD. DrvFS cannot reopen/truncate that unlinked file; existing-FD
I/O and an atomic loop attachment are used instead.

The one-time operator worker runs under `unshare --mount --propagation private`.
Only its new anonymous2GiB regular FD is attached using the
[Linux loop UAPI](https://raw.githubusercontent.com/torvalds/linux/v6.6/include/uapi/linux/loop.h).
It verifies major7, inode identity and AUTOCLEAR before formatting that mapping;
no physical disk or preexisting mapping is formatted. The root-owned0700 ext4
directory passes the existing driver guards. Nobody cannot read the raw root FD;
mounts remain private. `PNM_GUEST_WORK_DIR` is optional and canonical/root0700;
the default is unchanged. Nine offline guards pass.

The first two native runs passed assertions but export exceeded180 seconds,
so `bc2v5730` is not final retained acceptance evidence. An8MiB benchmark measured
1.033s at4KiB writes and0.124s at1MiB writes. Buffered1MiB writes, gzip1, OpenSSL
1MiB buffers and600-second export/readback limits repair this storage bottleneck.
Native operations themselves retain their existing limits.

Final control directory: `/var/tmp/pnm-test-volume.cky4eb0a` (root0700). Retain its
result/audit JSON and key (root0600), together with the D archive in the ignored
`.test-tmp/native-pool-05dfee1bf09343519c14a4cca956a0bc/` directory. Archive filename:
`pnm-test-volume.cky4eb0a.ext4.gz.enc` (808675120 bytes). AES256-CBC/PBKDF2 protects
the archive; trusted ciphertext hashes are computed from the producer pipe before
writing, and an independent raw-image hash stays in the protected control folder.
Cipher verification and full decrypt/decompress raw-hash readback pass. Never
mount or execute restored contents before those trusted checks succeed.

The image contains HY2 `btg1m7ba`24/24 and restore `fzm8pblq`16/16. Each records
nspawn0, unchanged host databases, not-found scope and no guest mounts. The outer
storage mount is separately unmounted; its loop association is gone and cleanup
errors are empty. No host service/account/firewall/WSL registration is changed.
This is neither VM reboot nor L3 evidence.

Independent review caught an unused error-path detach fallback in the executed
operator worker. That run had reached verified AUTOCLEAR=True with its
configuration FD closed, so the fallback was unreachable in its successful
remaining path. Do not reuse that archived operator source. Reviewed fixed source:
`/var/tmp/pnm-test-volume-fixed.useg_da0/worker.py`. It removes unowned detach,
clears a closed FD, and verifies no shared/master propagation. An actual
pre-configuration refusal leaves loop associations byte-for-byte unchanged and
reports no cleanup error. Copy that source into a fresh private control directory
for future runs. The repository driver contains no loop or encryption machinery.
