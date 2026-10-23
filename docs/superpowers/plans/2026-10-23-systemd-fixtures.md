# Isolated systemd lifecycle evidence

Goal: supplement mock tests with actual systemd state, enable policy and
InvocationID observations on the available Debian WSL manager.

Use two newly created random `pnm-accept-<uuid>-*.service` units running sleep as
the existing nobody identity. Map only the two fixed Core names at the systemctl
adapter boundary; refuse all other unit names. Keep configuration/transaction and
applied-record fixtures in a private temporary directory. No real Core, production
unit, account, SSH, firewall or network configuration is modified. Manager
daemon-reload and enable/disable of these test units are explicit test effects.

The opt-in `make test-systemd` target is separate from `make check`. Setup refuses
existing names. Cleanup checks ownership/content, stops/disables only created
units, removes only their files, and preserves private evidence on failure.

- [x] Implement the gated harness and optional Make target.
- [x] Implement scenarios for real activation, peer-preserving restart and applied InvocationID,
  inactive/disabled and active/disabled failure compensation, and TERM recovery.
- [x] Run syntax, security scan and ShellCheck, obtain independent safety review.
- [x] Execute the test target through the normal approval path.
- [x] Verify cleanup and record exact evidence, update Tasks/acceptance boundaries,
  review the staged delta and commit.

These stand-in services do not establish actual Xray/Hysteria behavior, account
provisioning, TLS loading, reboot, external traffic or the supported-distribution
matrix. Those acceptance items remain open.

Execution attempt: WSL failed before Bash with exit 1 and
`Wsl/Service/CreateInstance/CreateVm/HCS/0x800705aa`; the read-only retry failed
identically. No service setup or assertion ran. Static checks passed exit 0
(`/var/tmp/pnm-systemd-review.lint-final.log`); independent review accepted the
script for execution. That attempt did not establish dynamic acceptance.

Continuation: WSL recovered; frozen copy `/var/tmp/pnm-systemd-continue` at
`ee88135` passed `make test-systemd` (exit 0, 5/5). Log:
`/var/tmp/pnm-systemd-continue.systemd.log`. Both exact random units were subsequently
not-found/inactive, without runtime files or enable links. This completes this
bounded fixture stage; the real Core/TLS/reboot/client items above remain open.
