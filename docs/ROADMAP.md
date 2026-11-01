# PNM scope and roadmap

This document distinguishes implemented scope from possible future work. It is
not authorization to implement features or a record of completed acceptance.

## Implemented scope

- Independent Xray VLESS + REALITY and official Hysteria2 lifecycle management.
- Transactional single-node configuration, installation, per-Core apply/restart,
  pinned updates and rollback, trusted backups/restores, and per-Core uninstall.
- Installed-node Profiles (`dual`, `reality`, `hy2`) that retain configurations,
  binaries and credentials; initial provisioning prepares both Cores.
- Profile-aware health checks, optional resource observations, and read-only
  recovery diagnostics. Firewall rules and recovery intervention remain manual.
- Debian 12/13 and Ubuntu 22.04/24.04 compatibility for amd64 and arm64.

See [Architecture](ARCHITECTURE.md) for behavior and boundaries. Implementation
support is separate from completed validation on a particular OS/architecture.

## Release priorities

Use the finite [acceptance plan](ACCEPTANCE_PLAN.md#platform-closeout) and
[release checklist](RELEASING.md). Validate the selected candidate's installation,
Profiles, independent Core lifecycle, recovery, native services and true reboot
on each claimed platform, then verify both protocols from external clients.
Missing environments remain unverified; they do not expand the test scope.

## Deferred capabilities

Single-Core initial provisioning, automated firewall management, automatic
cross-process recovery, encrypted-backup key management, cross-architecture
restore and additional protocols are outside the current scope. Each needs an
explicit scope decision before implementation. No new phase starts automatically.
