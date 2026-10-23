# Real Core evidence on Debian WSL

Goal: supplement stand-in tests with fixed official Core binaries, actual generated
configuration validation, startup/TLS and local protocol traffic. This does not
replace disposable VM/reboot, actual service-account provisioning or an external
client on a separate host.

Design: root orchestrates private fixtures and randomly named transient systemd
units. Existing nobody runs each Core without capabilities, with NoNewPrivileges,
ProtectSystem/ProtectHome and PrivateNetwork. Clients and a fixture-only HTTP
origin enter that unit's network namespace, drop to nobody and bind loopback only.
No managed Core unit, installation path, account, firewall, host interface or route
is changed. Units have a runtime deadline and cleanup targets only owned names and
child processes. A host-loopback-only design offers weaker isolation; a disposable
VM is not currently available. The selected namespace design uses existing WSL.

Assets: [Xray v26.10.21](https://github.com/XTLS/Xray-core/releases/tag/v26.10.21)
and [Hysteria v2.13.0](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.13.0).
`tests/integration/real_core_versions.json` pins the official release API SHA-256
digests and sizes fetched on 2026-10-23. Check exact archive/binary bytes before
extracting or executing; binaries run as nobody. These test pins do not change
PNM VERSION, managed versions.conf or production approval. Logs/configuration
containing generated credentials stay in protected temporary files and are never
printed in ordinary output.

Stages:

- [x] Verify namespace prerequisites, validate the manifest and commit the reviewed
  test-only official metadata pins/plan.
- [ ] Download and verify the exact pinned assets privately before any execution.
- [ ] Implement an explicit opt-in real-Core test entry. Reuse production renderers,
  validate Xray config, then observe both real startup and HY2 TLS loading.
- [ ] Verify local client traffic through each Core where the namespace supports
  it, including authentication/TLS rejection; preserve the external-client boundary.
- [ ] Run static checks and independent safety review before service execution;
  verify owned-unit/child cleanup, document evidence and commit each complete stage.

The default make check target never downloads assets or starts these units.
Any unsupported namespace or missing verified asset fails before service setup.

Prerequisite evidence: Debian WSL PID 1 systemd, manager running, and
`unshare --net true` exit 0. Official release API metadata and manifest JSON parsed
successfully. The first release-URL connection timed out; standard official asset
API transfers are in progress. No downloaded executable or new Core unit has run.
