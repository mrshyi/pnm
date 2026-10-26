# Backup consistency implementation plan

Goal: preserve the existing backup/uninstall CLI while excluding cooperating PNM
writers throughout snapshot preparation and retaining staging cleanup in the caller.
Existing consecutive-stage authorization covers this defect repair and local commit.

Design: reuse `pnm_core_with_write_lock`, rather than introducing a reader lock
upgrade or another transaction system. Copy the existing twelve resources into
private staging through a small source-path boundary; validate paths before reads.
Read ports and binary versions from that snapshot. Keep stdout for CLI callers and
retain a fixed internal result field for uninstall, avoiding a new output API.
Publish a completed mode-0600 archive
without overwriting an existing destination. No services are changed by backup.
This coordinates PNM writers; arbitrary privileged external writers and crash
recovery require separate evidence. All fixtures remain outside managed host paths.

Files: `lib/core-ops.sh`, new `tests/unit/test_backup_flow.sh`, `tests/run.sh`,
`docs/ARCHITECTURE.md`, `docs/TASKS.md`, `docs/ACCEPTANCE_PLAN.md`.

- [x] Add regressions for lock contention, pending recovery, snapshot manifest,
  unsafe paths, failure/no-overwrite publication and same-shell uninstall dispatch.
- [x] Run the focused suite against the old implementation and record failures.
- [x] Implement the smallest repair using existing lock/config/temp primitives.
- [x] Run focused root/nobody checks, then frozen-copy `make check` and ShellCheck.
- [x] Obtain independent review, resolve concrete findings, refresh evidence docs,
  inspect staged/unstaged changes and commit the exact stage files.

Alternatives: a shared backup lock would require changing existing reentrancy rules;
reading live metadata after copying retains inconsistent snapshots. Both add risk
without improving this bounded repair. Real systemd/VPS acceptance remains open.
