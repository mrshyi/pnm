# Recover confirmed applied evidence after config apply failure

Scope: existing config-apply failures restore files and restart the old runtime,
but do not rebind previously confirmed applied evidence to the new InvocationID.
Use existing capture/check/recover helpers, with a baseline local to each apply.
Never certify a missing, stale, damaged or externally changed prior record.

- [x] Reproduce full apply failure with real file transactions and mocked Core I/O.
- [x] Capture prior evidence before mutation and refresh it only after verified
  compensation; preserve the original failure and recovery-required behavior.
- [x] Cover both cores, multiple failure stages, unknown/external evidence,
  successful repeated apply and an isolated real systemd callback case.
- [x] Run focused/default checks and ShellCheck, review and commit.

No real Core/account/network/reboot changes. Real systemd uses only the existing
random fixture-unit boundary. Full real Core and external-client acceptance stays
separate.

Evidence: default 31 suites/336 tests and nobody evidence 28 tests pass (exit 0),
`/var/tmp/pnm-config-applied-final`. Systemd fixture 8 tests and complete static
checks pass (exit 0), `/var/tmp/pnm-config-applied-systemd-final`. Final case also
initializes CLI runtime and verifies registered staging cleanup. Review metadata
drift regression failed before enabling existing required metadata policy.
