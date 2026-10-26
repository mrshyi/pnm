# T-15 uncertainty write with real VM block exhaustion

Continue from `5141e7a`. Reuse the approved VM-only anonymous block filler;
exercise the original uncertainty stream's write/flush with zero available ext4
blocks before the existing candidate-write refusal. Do not change publisher
stdin, file APIs, product code or transaction semantics in the VM.

- [x] Reproduce missing pending-write observation in a focused guard.
- [x] Bind arming to the exact empty pending FD and inode, original module frame,
      protected transaction and approved VM/private namespace/2GiB bounds.
- [x] Keep the anonymous filler through buffered stream close; release at
      publisher atexit, then require available space and empty pending bytes.
- [x] Extend VM-only host refusal and exact event/errno/cleanup receipt checks.
- [x] Run Python compilation, all33 guards, syntax/security scan/ShellCheck.
- [x] Run both actual block ENOSPC positions with original CLI73, full resource/
      NSS/directory/unit/applied compensation, retained empty/complete pending
      respectively, no marker, then14 normal lifecycle+7 same-disk reboot checks.
- [x] Require complete encrypted2GiB archive readback, host/QEMU/loop cleanup,
      review, current-status update and an authorized local commit.

The unchanged product/unit source retains the32-suite/399-test baseline from
`5d15ab6`; this is not a new full-suite execution. Physical media, every storage
position, other platforms, deployed identity and external clients remain separate.

Focused evidence: `/var/tmp/pnm-inode-check.mp5xks2t` passes26 integration Python
compilations,33 guards and all static gates (exit0). The pending-write observer
regression first fails for missing receipt, then passes with cleanup timing checked.

VM evidence: `/var/tmp/pnm-vm-boot-volume.kbazwzch` passes2 original ENOSPC73
refusals,14 lifecycle+7 same-disk reboot checks without product-state repair.
Complete encrypted2GiB readback matches, host databases are unchanged, QEMU exits0
and is quiescent, the loop detaches and cleanup errors are empty. Independent
read-only review finds no blocker.
