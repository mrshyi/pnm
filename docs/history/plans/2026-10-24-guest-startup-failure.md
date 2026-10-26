# Real Core startup failure compensation

Use the existing verified guest/CLI/HTTPS fixture and official pinned binaries.
Only guest-owned transient drop-ins/programs are added; production functions,
transaction implementation, credentials and host services are unchanged.

- [x] Add a bounded guest-only one-shot ExecStartPre probe. Its loopback server
  rejects the first start and permits compensation start; Restart=no makes this
  deterministic. Preserve the service's user/capability/filesystem sandbox.
  Require exactly two probe executions, then retire owned sockets/thread/drop-in.
- [x] In core-update-failure, start from the prior pair. For each Core force a
  real update startup failure and rollback startup failure. Verify original
  error/cause, one terminal ROLLED_BACK transaction, full binary/previous metadata
  restoration, fresh confirmed applied evidence, active/enabled policy and peer
  preservation. Then finish the existing successful update/rollback trajectory.
- [x] In restore-failure, use an independently checksum-verified own archive,
  change/apply a target, then reject HY2 startup during restore after Xray starts.
  Require both old baselines/metadata/services/applied to recover, then retry the
  restore successfully after removing only the owned fault.
- [x] Add useful offline fixture cleanup checks, compile/static/real verification,
  independently review, record precise evidence and commit each completed slice.

A one-shot startup rejection is not a disk/commit fault, arbitrary concurrent
actor, uncatchable crash or VM/kernel reboot. Persistent recovery failure needs
its own retained-uncertainty case. All raw output remains protected.

Progress: the restore case reproduced a real compensation defect, repaired and
committed as `3c30512`; fresh guest `lood523m` passes16/16, focused tests12/12,
syntax/security/ShellCheck pass. The new full check exited2 with host EIO.
The initial update-failure run `ywce9pza` reached its final links check but hit
the old300-second overall limit. The enlarged600-second retry `771npvcc` stalled
in base restore while host executables also returned EIO, and was interrupted
through its verified owned driver. Its final report write failed with EROFS.
Do not count that scenario as passed. Eight offline guards passed before boot.
Remaining harness changes are retained uncommitted pending stable WSL execution,
full validation and the final independent review/commit. Do not remount/repair
the host filesystem, restart WSL or delete retained fixtures automatically.

Continuation: WSL is writable again, host true/df and owned temporary I/O pass,
and the interrupted scope/mounts are gone. New actual runs expose a Type=simple
listener readiness window, separately confirmed by delayed ExecStart in guest
`dpg_alxd`. The bounded existing-adapter repair passes native readiness16/16 in
`mkmrfpdx`; update/rollback one-shot failure recovery passes26/26 in `jkja5d_v`.
The initial natural post-health errors cannot independently prove their cause.
Final tool-error propagation and renderer-fixture corrections are covered by
focused25/25 and13/13; final static/guard/full validation and commits remain.

Completion: startup readiness repair is committed as `ce6713f`. Final frozen
`/var/tmp/pnm-startup-checked.gdpgk2ro` passes syntax/security/ShellCheck, eight
offline guards and31 suites/380 tests. Seven Python files compile. Independent
review's tool-status issue is reproduced, corrected and re-reviewed. The reusable
scenarios and this completed plan are committed together in the next test slice;
the separate recovery-required plan remains open.
