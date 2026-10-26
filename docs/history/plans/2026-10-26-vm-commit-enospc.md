# T-15 real VM disk-space refusal and deployment recovery

After bounded publisher commits, a fresh Windows check reports about4GB free
on C. Reuse the existing independent2GiB VM operator with its exact private
Linux output path; recheck physical capacity before launch. Keep older evidence.

- [x] Host guard RED precedes the new VM-only disk-space fault helper.
- [x] Only this boot's approved VM, root ext4 /dev/vda and bounded2GiB filesystem
      may allocate an anonymous root0600 filler on the same filesystem as the
      actual publisher transaction. No container/host route is accepted.
- [x] At the original empty candidate FD, allocate only that owned anonymous file
      until actual ENOSPC with zero available blocks. Do not modify file APIs,
      publisher stdin, process limits or the original candidate.
- [x] Observe actual candidate ENOSPC/publisher73; close the anonymous filler and
      verify available space before recording evidence and letting the CLI recover.
- [x] Require CLI73, retained pending/no marker, full original resource/NSS/
      directory/unit/applied compensation and terminal rollback. No state repair
      may prepare the successful normal14-check lifecycle and7-check reboot.
- [x] Run guards/compilation/static checks, full encrypted disk readback and
      host/loop/QEMU cleanup checks; update status and locally commit.

This is real ENOSPC on a disposable virtual ext4 disk, not physical-media EIO,
all commit positions, deployed-source identity or external-client acceptance.

Evidence: RED `pnm-vm-space-red.ycn5vm3q`;29 guards/4 bounded regressions/
27 compilations/static gates `pnm-vm-space-preboot.3n5tg1w4`; actual VM
`pnm-vm-boot-volume.5nul5yug` passes1 ENOSPC recovery +14 lifecycle +7 reboot
checks and full2GiB encrypted readback, with quiescent QEMU, detached loop and
empty cleanup. No product Bash or VERSION change. Independent review remains
usage-limited; do not describe self-review/execution as independent approval.
