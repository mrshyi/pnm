# Preserve active but disabled Core recovery policy

Scope: reproduce false recovery failures in existing update/rollback and config
compensation when the service baseline is active but disabled. Installation health
still requires enabled. Recovery must observe active state and the original enable
policy, without enabling a service or touching its peer.

- [x] Add regressions against the current callbacks; confirm failure before edits.
- [x] Replace install-only recovery predicates with exact baseline observations.
- [x] Run focused, full default checks and ShellCheck; extend the isolated systemd
  fixture with real callback recovery for the disabled baseline.
- [x] Review, document evidence boundaries and commit the minimal repair.

Private file fixtures and uniquely named nobody/sleep units only. No real Core,
accounts, network, reboot, production operations or new features.

Final evidence: `/var/tmp/pnm-recovery-policy-final`, default check exit 0
(31 suites / 331 passed), isolated systemd 7/7, ShellCheck exit 0, actual nobody
preparation 11/11 and evidence 23/23. Exact generated units are not-found/inactive
and removed. State-query errors with matching output were separately reproduced
before explicit return-code handling. Logs and remaining external prerequisites
are recorded in Tasks. Independent source review accepted the final predicates.
