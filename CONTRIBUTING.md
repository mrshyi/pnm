# Contributing

Keep changes within the Xray and Hysteria2 lifecycle scope. Do not add remote access-plane management or unrelated host-maintenance commands without an explicit project decision.

Before opening a pull request, run from the project root:

```bash
make check
make shellcheck
make release-check
```

Do not commit node configuration, credentials, private keys, generated backups, or test logs. Add tests for behavior changes and include the observed command output when a gate cannot run.
