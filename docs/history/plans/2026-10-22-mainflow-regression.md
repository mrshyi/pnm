# Main-flow regression repair

Scope: continue Phase 3 by repairing the reproduced check, node, deployment,
preflight, TLS and link test failures. Keep CLI behavior, certificate/name checks,
applied-evidence gates and independent Core boundaries intact. No production action,
commit, version bump or G-02 transaction-owner redesign is included.

- [x] Reproduce the existing failures in a fresh Debian 13 WSL temporary copy.
- [x] Isolate test variable/function state and invoke Bash suites explicitly;
  retain parent fixture cleanup and report every suite result.
- [x] Make the configuration loader reject non-associative output targets before
  mutation; declare the node test's missing associative array.
- [x] Repair check fixtures, deterministic TLS time tests, external-CA SAN input,
  and link fixtures with real applied records plus mocked runtime observations.
- [x] Run focused red/green tests, complete `make check` and `make shellcheck`,
  independently review changes, and update `docs/TASKS.md` with exact evidence.

Result: Debian 13.5 WSL temporary copy, `make check` exit 0 (20 suites / 184 tests),
syntax/security scan/ShellCheck exit 0. Independent source review found no blocker.
Systemd integration, G-02 recovery and external connectivity remain unverified.
