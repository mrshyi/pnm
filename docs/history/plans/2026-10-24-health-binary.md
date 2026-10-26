# Managed Xray health executable

Real guest installation with PATH=/usr/sbin:/usr/bin:/sbin:/bin starts Xray but
fails post-health. The same renderer-fixed source installs successfully with
normal root PATH. Version discovery uses PNM_XRAY_BIN, but configuration health
uses bare xray. Besides false failures, another executable in PATH can be tested
instead of the managed Core.

Use the existing configured binary path for the configuration test; preserve
arguments, exit propagation and health gates. Do not change PATH globally.

- [x] Reproduce absent and competing PATH xray with focused regressions.
- [x] Change only the health config-test executable; check other Core call sites.
- [x] Run focused/default checks, syntax/security/ShellCheck.
- [x] Repeat actual installation with the original minimal PATH in a fresh guest.
- [x] Independently review the implementation and regressions.
- [x] Record the final default-suite result for the local commit.

Red `/var/tmp/pnm-health-red.puatxss1`: 13 pass, both new cases fail. Green
`/var/tmp/pnm-health-green.hni1ico0`: focused 15/15, syntax/security/ShellCheck
exit 0. Default `make check` exits 0: 31 suites / 361 tests pass.

Fresh `/var/tmp/pnm-install-guest.i84_5clp/boot-result.json` records all eight
actual installation/account/process/applied/link/health checks passing with the
original minimal PATH. Boundary approval, normal nspawn exit 0, unchanged host
databases, absent scope and no remaining fixture mounts also pass. This is
offline-cache private-guest integration; no time-sync diagnostic, traffic,
network acquisition, reboot or external connectivity acceptance is claimed.
