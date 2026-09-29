# Changelog

Notable changes are recorded here for each release.

## 0.16.0-rc.1 - 2026-09-29

- Focus the supported CLI on Xray and Hysteria2 lifecycle operations.
- Add per-core status, restart, logs, configuration apply, update/rollback, backup/restore, and uninstall operations.
- Keep broad host acceptance and remote access-plane operations out of the supported CLI.
- Add archive validation and rollback coverage for the core lifecycle.
- Add a root installer for one-command PNM CLI deployment to a VPS.
- Support Debian 12/13 and Ubuntu 22.04/24.04 amd64 platform preflight checks.

This is a release candidate. Production readiness requires the live deployment and external protocol checks in [RELEASING.md](docs/RELEASING.md).
