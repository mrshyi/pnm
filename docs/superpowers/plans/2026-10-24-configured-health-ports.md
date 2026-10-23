# Existing configured-port health consistency

T-04 and the existing node init flags accept persisted XRAY_PORT/HY2_PORT;
rendering, client URIs and preflight already use them. check.sh still requires
443/8443 and probes those defaults. deploy.sh's recovered-applied verification
also probes defaults instead of the hash-verified recovered runtime configuration.
These assumptions can reject valid nodes or attribute an unrelated default
listener to the managed Core.

- [x] Reproduce desired custom-port health and missing/invalid-port refusal in
  focused tests. Keep default CLI output/ports and compatibility intact.
- [x] Probe validated persisted ports during forward health; never guess a default
  when its value is unknown. During recovered-applied verification, derive the
  listener from the already hash-verified recovered Core configuration, not a
  potentially different desired node. Reuse existing JSON/YAML parsers.
- [x] Add actual custom-port guest scenario: configured-port occupancy refuses
  before write; unrelated default listeners remain untouched; install, links,
  health, per-Core restart/apply and trusted restore use actual custom listeners.
- [x] Run focused/default/static checks and real guest cases. Independently review
  minimal production repair separately from the reusable test scenario increment.

No new port option, protocol, firewall automation, alias or state store is added.
External reachability, kernel reboot and broader fault positions remain separate.

Initial focused red `/var/tmp/pnm-port-health-red.o9e06_3g`: check15 pass/3 fail,
deployment15 pass/2 fail. Real guest9s3b0ftl installs and emits valid custom-port
links but check rejects configuration, reproducing the user-visible mismatch.
The default ports are occupied by unrelated owned sockets throughout this case.
An added Xray non-TCP recovery case fails before its transport gate, then passes;
both Core negative groups also cover malformed/invalid ports and no applied edit.

Final frozen `/var/tmp/pnm-port-health-green.erfo3wso` passes focused check18/18,
deployment19/19 and static checks. Full `make check` exits0,31 suites/370 tests
pass. Actual final
guest e59hkntn passes16/16, including configured occupancy refusal, actual10443/
18443 listeners and URI ports, lifecycle/restore and preserved unrelated443/8443
sockets. Host databases remain unchanged, nspawn exits0, scope is not-found and
no fixture mounts remain. Independent review found no blocking source issue.
