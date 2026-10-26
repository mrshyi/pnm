# T-15 uncertainty creation with real VM inode exhaustion

Follow candidate-inode increment `5d15ab6`. Reuse its approved VM-only inode
filler and observe the original publisher before `commit-uncertain.env` creation.
This earlier position must leave no pending file; the later candidate position
must continue retaining its already-persisted uncertainty record.

- [x] Extend the focused observer regression with the original publisher's
      pending-create frame and show that only the new position fails without
      an observed receipt before implementation.
- [x] Arm only for the exact unpublished transaction and pending path, within
      the existing approved VM/private-namespace/2GiB/inode/deadline bounds.
- [x] Observe the original os.open ENOSPC, retire the exact filler files, and
      require absent pending/commit markers and recovered inodes/data space.
- [x] Extend host refusal, event/errno/cleanup checks and sequential scenario
      wiring; preserve the existing late-candidate pending-retention assertions.
- [x] Run fresh compilation,32 guards and static checks. The product source and
      unit tests are unchanged; retain the preceding fresh32-suite/399-test
      full-check result as inherited evidence, not a new full-suite execution.
- [x] Execute both inode refusals, full compensation,14 normal lifecycle checks
      and7 same-disk reboot checks in a new VM without product-state repair.
- [x] Verify full encrypted archive readback, host/QEMU/loop cleanup and review;
      refresh current evidence and make the authorized local commit.

Other storage positions, physical-media behavior, other platforms, deployed
source identity and external-client traffic remain separate acceptance items.

Focused evidence: `/var/tmp/pnm-inode-check.w0islkam` passes26 integration Python
compilations, all32 guards (including both observer-frame subcases), syntax,
security-scan and ShellCheck. Independent read-only review found no blocker.

VM evidence: `/var/tmp/pnm-vm-boot-volume.63tmj7gv` passes both real inode
refusals,14 lifecycle and7 reboot checks. Full encrypted2GiB readback matches,
host databases are unchanged, QEMU is quiescent, the loop is detached and cleanup
errors are empty. Physical C availability afterward is approximately8.59GiB.
