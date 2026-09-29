# Release checklist

## Source release

1. Confirm the intended files are committed and the working tree is clean.
2. Update `VERSION` and `CHANGELOG.md` to the same version.
3. Run `make check`, `make shellcheck`, and `make release-check`.
4. Review the staged diff for credentials, private keys, backups, logs, and generated artifacts.
5. Enable GitHub private vulnerability reporting and confirm repository security settings.
6. Create an annotated version tag and publish the source from that tag. Do not attach an old workspace archive.

## Production readiness

A source release or passing local tests alone does not make a node production-ready. On a disposable Debian 13 VPS:

1. Install PNM and both pinned Cores; apply Reality and Hysteria2 configuration.
2. Run `pnm check`, reboot, reconnect through the intended management path, and run `pnm check` again.
3. Confirm TCP/443, UDP/8443, and SSH listeners; both Core services and required system units are active and enabled.
4. Test VLESS REALITY and Hysteria2 from external clients.
5. Record sanitized evidence and the exact PNM/Core versions. Never publish node secrets or backup archives.
