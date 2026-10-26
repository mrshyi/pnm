# Verify actual state after lifecycle compensation

Scope: shared lifecycle restore currently trusts successful control commands,
without observing final active/enabled state before declaring rollback complete.
Retain the existing transaction and service adapter. Validate the captured baseline
before controls and require successful final observations matching it exactly.

- [x] Reproduce no-effect control success, final query failure and invalid baseline.
- [x] Add final baseline observations, preserving command/query failure statuses.
- [x] Verify all supported policy pairs and recovery-required transaction behavior.
- [x] Run focused/default checks, existing isolated systemd suite and ShellCheck;
  review evidence, update status and commit.

Tests use private fake-systemctl state or existing random nobody/sleep units.
No real Core, host account, network, reboot or production operations.

Final copy `/var/tmp/pnm-lifecycle-verify-final`: check exit 0 (31 suites / 341
passed), root/nobody lifecycle each 8/8, isolated systemd 8/8, static checks exit 0.
The exact generated units were confirmed not-found/inactive and their files and
enable links absent. Independent source review accepted the final predicate.
