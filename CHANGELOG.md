# Changelog

Notable changes are recorded here for each release.

## Unreleased

- Add installed-node `dual`, `reality` and `hy2` Profile switching through the
  existing transaction model, retaining Core files/credentials and unchanged peers.
  Initial provisioning continues to prepare both Cores.
- Make Core operations, links, diagnostics and trusted restore follow the desired
  Profile, with separate desired and actual service observations.
- Add configured ports/Profile selection to status and optional memory, Swap,
  load and cumulative system OOM observations through `check --resources`.
- Add root-only, sanitized `recovery list|inspect` diagnostics while retaining
  pending-transaction write guards and private recovery evidence.
- Accept paired external TLS certificate/key inputs in the installation CLI/menu,
  and remove unused legacy command/host-diagnostic helpers.
- Extend the Ubuntu22.04/24.04 CI configuration to run existing Profile/recovery
  fixtures as root. This configuration is not evidence of a completed CI run.

These changes retain manual firewall management and do not add automatic recovery
replay or encrypted-backup key management. Current tests and remaining real
deployment/reboot/client acceptance are recorded in [TASKS](docs/TASKS.md).
VERSION remains `0.16.0-rc.1`; this section is not a published release.

## 0.16.0-rc.1 - 2026-09-29

- Focus the supported CLI on Xray and Hysteria2 lifecycle operations.
- Add per-core status, restart, logs, configuration apply, update/rollback, backup/restore, and uninstall operations.
- Keep broad host acceptance and remote access-plane operations out of the supported CLI.
- Add archive validation and rollback coverage for the core lifecycle.
- Add a root installer for one-command PNM CLI deployment to a VPS.
- Support Debian 12/13 and Ubuntu 22.04/24.04 amd64 platform preflight checks.
- Add transactional single-node initialization, change, show, and validation commands.
- Use latest stable Core release metadata and official checksums as interactive `node init` defaults while persisting concrete pins.
- Add explicit client share-link output for VLESS + REALITY and Hysteria2 after installation.
- Allow the non-root Xray service to bind TCP/443 with only `CAP_NET_BIND_SERVICE`.
- Expand the VPS installation and first-use instructions.

This is a release candidate. Production readiness requires the live deployment and external protocol checks in [RELEASING.md](docs/RELEASING.md).
