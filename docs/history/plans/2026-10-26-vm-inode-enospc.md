# T-15 real VM inode exhaustion and deployment recovery

Extend the existing approved independent Debian VM storage fixture. Keep the
product publisher and filesystem APIs unchanged during VM execution; only the
new VM's protected root ext4 may be filled. Preserve all earlier evidence.

- [x] Reproduce the missing VM-only guard before adding the inode fault helper.
- [x] Restrict allocation to the approved boot, a private child mount namespace,
      root ext4 `/dev/vda`, a filesystem no larger than2GiB, and at most262144
      free inodes at admission. Use a new private directory and exact owned
      empty0600 files, with a120-second monotonic deadline.
- [x] Require zero available inodes while data blocks remain, then observe the
      original `tempfile._mkstemp_inner` candidate-create ENOSPC. A focused
      regression must use the publisher's `<stdin>` entry frame.
- [x] Retire only the exact filler files before recording the refusal receipt
      and returning to the parent CLI. Verify that inodes and data space recover.
- [x] Require publisher/CLI73, persisted pending/no commit marker, and complete
      original resources/NSS/directories/units/applied-record compensation.
- [x] Require the normal14-check lifecycle and7-check same-disk reboot afterward,
      without fixture repair of product state.
- [x] Complete Python compilation, all32 guest guards, full project checks and
      ShellCheck. Verify the complete encrypted2GiB archive readback, host database
      baseline, QEMU quiescence, detached loop and empty cleanup errors.
- [x] Refresh the current status and T-15 matrix, review the actual diff, and
      create the authorized local commit.

The earlier `t97gd6w0` run reproduced the missing internal tempfile trace receipt.
The later `9ns5elu_` run reached the real inode refusal but exposed incomplete
variant receipt validation. Both remain failed evidence, with verified retained
encrypted archives and detached loops. Only a fresh complete run can close this
slice. This does not establish physical-media behavior, every storage position,
other platform acceptance, deployed-source identity or external-client traffic.

Final evidence: `pnm-vm-boot-volume.vwj_tucv` passes1 refusal+14 lifecycle+7
reboot checks and complete encrypted2GiB readback/cleanup. Final source copy
`pnm-inode-check.2iexfm3t` passes26 integration Python compilations,32 guest
guards, `make check` (32 suites/399 tests, exit0) and ShellCheck (exit0).
Independent read-only review found no blocker; the minor guide wording is fixed.
