# PNM Architecture

This document describes the source baseline plus safety/G-02, persisted-port, lifecycle-evidence and update/restore-input changes through 2026-10-23. It is not a production deployment attestation. Verify behavior against source and tests when changing it.

**Increment baseline:** branch `dev`, HEAD `f9b4117eb6418d425603991264189d48c73c4477`, `VERSION` `0.16.0-rc.1` (checked 2026-10-23).

## System boundary

PNM is a Bash management CLI for one Debian or Ubuntu VPS. It manages two independent proxy cores and is not in their data path:

| Core | Protocol | Default listener | systemd unit | Binary/configuration |
|---|---|---|---|---|
| Xray | VLESS + REALITY | TCP/443 | `xray.service` | `/usr/local/bin/xray`; `/usr/local/etc/xray/config.json` |
| Official Hysteria2 | Hysteria2 over QUIC | UDP/8443 | `hysteria-server.service` | `/usr/local/bin/hysteria`; `/etc/hysteria/config.yaml` |

The Core units and service accounts are separate. Xray runs as `xray`; Hysteria2 runs as `hysteria`. Xray's generated unit grants only `CAP_NET_BIND_SERVICE` for TCP/443 while retaining non-root execution. See `lib/service.sh` and its unit tests. These are source-level facts; a host's installed units still require direct verification.

## CLI and module boundaries

The entry point is `bin/pnm`; `lib/common.sh` parses global options and routes top-level commands. Current top-level command families are:

- `help`, `version`, `status`, `check`
- `node` (initialization/change, show, links, validation; aliases are documented in `README.md`)
- `install`
- Core operations: `restart`, `log`, `apply`, `update`, `rollback`, `backup`, `restore`, `uninstall`

Core operation dispatch is implemented in `lib/core-ops.sh`; node management and client links are in `lib/node.sh`; runtime rendering/comparison is in `lib/render.sh`; status and health checks are in `lib/status.sh` and `lib/check.sh`. The README is the user-facing command reference; check dispatch and argument validation in source before documenting interface changes.

Platform, systemd, network, and asset adapters are under `adapters/`. The CLI sources the libraries explicitly in `bin/pnm`.

## Configuration and state

The implementation distinguishes several state sources:

| State | Location / evidence | Purpose |
|---|---|---|
| Desired node settings | `/etc/pnm/node.conf` | Node identity, ports, REALITY target/SNI, HY2 TLS mode and TLS name, configured marker |
| Approved core versions | `/etc/pnm/versions.conf` | Concrete versions and SHA-256 pins |
| Core credentials | `/etc/pnm/secrets/` (`reality.env`, `hysteria.env`) | Private keys and authentication secrets; generated securely and reused when valid |
| Applied evidence | `/var/lib/pnm/cores/<core>/applied.env` | Runtime config digest and systemd invocation identifier recorded by PNM |
| Runtime configuration | Xray JSON and Hysteria2 YAML paths above | Configuration files consumed by the respective Core |
| Actual service state | systemd unit state, invocation, and local listener checks | Runtime observations; these do not by themselves prove external reachability |

Configuration parsing and schema checks are in `lib/config.sh`; node initialization and reporting are in `lib/node.sh`. Secrets are not part of the ordinary node configuration. Client link generation checks per-Core service/config/applied state and can omit an unsafe Core link without changing the other Core's configuration (`lib/render.sh`, `lib/node.sh`).

Xray and HY2 have distinct TLS/SNI semantics. `XRAY_SERVER_NAME` and `XRAY_TARGET` configure REALITY; `HY2_TLS_SERVER_NAME` is validated against the configured HY2 certificate and is used for HY2 link/config behavior. Existing valid credentials are reused rather than silently rotated.

## Install and apply flow

The public install path is `lib/install.sh` → preflight → `lib/apply-gate.sh` → `lib/deploy.sh`. The gate holds the exclusive lock through final health/deadline checks. Explicit sandbox, lifecycle and node/applied-state participants share one `deployment` transaction. Standalone sandbox and per-Core lifecycle wrappers retain independent transactions; arbitrary implicit transaction nesting is rejected.

Preflight probes the validated persisted `XRAY_PORT` and `HY2_PORT`. Invalid or missing node state produces an UNKNOWN port check alongside the configuration failure, without probing fallback ports. Recovery listener attribution uses the same configured protocol/port pair and retains its ownership checks.

`lib/transaction.sh` provides schema-2 file snapshots with numeric UID/GID/mode, directory identity/metadata receipts, rollback callbacks and inspection; schema-1 records remain inspectable. `lib/deployment-state.sh` extends that engine with protected deployment baselines and a durable resource-bound marker. Deployment progress journals and gate receipts are derived; standalone operations keep their existing journal commit convention.

Deployment publishes a durable uncertainty record before its marker. Uncertain publication or incomplete recovery retains evidence and blocks later writes and protected reads. Before commit, one recovery callback stops affected services, restores resource bytes/metadata and units, verifies each original service policy, then compensates created accounts and directories. Originally absent units remain absent; active-but-disabled baselines are preserved. Recovery refreshes applied InvocationID only for a previously confirmed, hash-matching runtime and unchanged original applied record.

Loaded units and existing Core resources require established PNM ownership receipts before replacement. Valid existing credentials are reused. INT/TERM/EXIT attempt in-process compensation; SIGKILL/reboot detection blocks further changes but does not implement automatic cross-process replay. These behaviors have local filesystem/mock evidence only; real systemd/reboot recovery remains G-02 acceptance work in `docs/TASKS.md`.

## Core lifecycle, health, and recovery

`pnm status` reports service state and detected Core versions. Root `pnm check`, `node show` and links take a shared lock and reject unresolved deployment state. Non-root `check` retains diagnostics with UNKNOWN deployment/configuration-readiness results; `node show` and links require root (link help remains public). Local listening is not a proof of public reachability or successful client handshakes. There is no implemented Profile model; installation targets both cores.

The Core operations include per-Core restart/log/apply/update/rollback and backup/restore/uninstall routes (`lib/core-ops.sh`). Updates use pinned versions and checksums. Restore stages and validates archive contents before applying. Feature presence in source is not by itself proof that every rollback/failure path is verified; consult `docs/TASKS.md` for current acceptance status.

Update/rollback retain the existing exclusive PNM lock from preparation through transaction completion and compensation. Argument validation/root checks precede this boundary; pending deployments are checked under the lock before preparation. Version pins, service state, current/previous binaries and configuration baselines are then read while cooperating PNM writers are excluded. The existing transaction lock is reentrant, and each wrapper releases only its own lock level, including early failures. Asset download remains inside this global boundary, so other writers and consistency-sensitive readers may report contention during preparation. This does not coordinate arbitrary privileged writers that ignore the PNM lock.

Update/rollback explicitly enroll metadata for the current binary, previous binary and `previous.env`, and verify all published transaction resources before commit. Compensation preserves an intervening content or metadata edit and reports recovery required. Transaction-close errors propagate without a success message, even if the commit already completed; outer lock cleanup still runs.

Restore parsing enumerates at most 64 visible members, rejects absolute/traversing names and payload-bearing directory entries, bounds the manifest to 64 KiB and declared resource totals to 512 MiB, and requires the complete 12-resource set before candidate validation. These are member-level checks; internal tar PAX/GNU extension parsing and complete hostile-archive resource exhaustion are not accepted. Candidate validation executes the staged Core binaries, so file ownership/mode checks do not establish archive provenance or make untrusted executables safe.

Restore enrolls file metadata and directory preparation in the existing transaction. Private destination directories must already be root-owned with root group; foreign ownership is refused rather than silently changed. File ownership normalization records only its fixed expected numeric UID/GID/mode, so intervening metadata edits cannot become a new expected state. Applied records and their directories participate in the same compensation. Recovery restores original file bytes/metadata without applying candidate ownership again, then compensates directory changes after service recovery. Resource verification precedes commit, and transaction-close errors suppress the success message. Full service/invocation recovery and concurrency acceptance remain separate work in `docs/TASKS.md`.

Restart/update/rollback carry forward only previously confirmed applied evidence. Under the transaction lock they capture the record, configuration digest and metadata; after health checks they publish the new invocation against that fixed digest through the existing transaction. Missing, changed or damaged evidence is retained without promotion. Compensation restores resource bytes and the service baseline before refreshing a previously confirmed active invocation; an inactive baseline keeps its original record. These applied writes explicitly enroll metadata before post-publication receipts, so external content/metadata drift retains recovery evidence rather than being silently overwritten. This does not implement automatic reboot reconciliation or race-free coordination with arbitrary privileged writers.

## Security boundaries

- PNM does not configure SSH, Tailscale, UFW, OCI security groups, or cloud firewalls as part of normal installation.
- Managed service identities are validated and reused where policy permits. Rollback must not remove pre-existing accounts.
- Secret-bearing backup archives and client share links are sensitive. File modes and redacted diagnostics are part of the security model.
- Unknown port occupants must not be terminated automatically.

## Verification boundary

Automated tests live in `tests/unit/` and are invoked through `tests/run.sh` / the Makefile. Mock-based tests validate command logic and rollback behavior only within their fixtures. Debian 13/systemd behavior, reboot persistence, public firewall reachability, and external client protocol handshakes require an isolated Linux VM or explicitly authorized production read-only validation. Current outstanding verification is tracked in `docs/TASKS.md`.
