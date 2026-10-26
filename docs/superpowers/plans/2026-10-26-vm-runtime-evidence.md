# T-20/T-26 independent VM runtime evidence and consistency lock

Continue from `112cdd3`. Replay the existing `runtime-evidence` guest cases on
the approved independent Debian VM. Reuse the existing19-check scenario and
same-disk7-check reboot acceptance; do not introduce new product behavior.

- [x] Confirm the existing cases execute real systemctl restart, original CLI
      link/show/restart/apply, actual cross-process flock and post-lock retry.
- [x] Allow the existing scenario in the VM lifecycle result validator and
      require its exact14 mainflow+5 runtime-evidence check count.
- [x] Run fresh26 Python compilations,33 host guards and static checks.
- [x] Require both Cores' external/repeated unconfirmed restarts to withhold
      stale URIs without changing peer resources; validated apply reconfirms.
- [x] Require independent writer and sensitive reader CLI73 refusals while a
      real exclusive lock is held, no stdout/state/transaction mutation, then
      successful lock release/retry. Require7 same-disk reboot checks afterward.
- [x] Verify full encrypted2GiB readback and host/QEMU/loop cleanup, independently
      review, update current evidence and make the authorized local commit.

This reuses existing tests rather than adding assertions that merely mirror a
new allow-list. The product/unit source is unchanged; the full32-suite/399-test
baseline from `5d15ab6` remains inherited, not freshly executed. Other scheduling
interleavings, deployed identity, external clients and platform gates remain open.

Focused source copy `/var/tmp/pnm-inode-check.fv8hh3xb` passes26 integration
Python compilations,33 guards and syntax/security-scan/ShellCheck (exit0).

Fresh VM `/var/tmp/pnm-vm-boot-volume.md536vk0` passes14 normal+5 runtime/lock+7
same-disk reboot checks. Complete encrypted2GiB readback matches, QEMU exits0 and
is quiescent, the loop detaches, host databases are unchanged and cleanup is empty.
Independent read-only review finds no blocker in the selected coverage or wiring.
