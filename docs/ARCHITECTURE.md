# PNM Architecture

This document describes implemented behavior through the configured-port health repair on 2026-10-24. It is not a production deployment attestation. Verify behavior against source and tests when changing it.

**Port-health increment baseline:** branch `dev`, parent HEAD `dfd864d`, `VERSION` `0.16.0-rc.1` (checked 2026-10-24).

Config apply shares the guarded Core file writer with archive restore. Runtime
configuration metadata is required at publication, checked before ownership
normalization and re-enrolled only against the fixed intended tuple. External
permission drift cannot be normalized away or silently overwritten on failure.
The first ownership error remains authoritative; rejected metadata enrollment
leaves the previous receipt intact for safe compensation or retained uncertainty.

Applied publication uses existing directory receipts for standalone Core paths as
well as deployment/restore. Update prepares its previous-state destination after
transaction begin and callback registration. Core compensation restores files,
service policy and prior applied binding before reversing directory changes;
legacy install-state registers file recovery before directory recovery in execution
order. New directories are removed only when empty and still owned by the receipt;
foreign contents, metadata or identity drift retain recovery-required.

Shared lifecycle compensation validates its captured baseline before service
controls, then re-queries actual active/enabled state after daemon-reload.
Successful commands alone cannot close recovery: both queries must succeed and
match the original policy exactly, or the existing transaction remains uncertain.

Config apply captures previously confirmed applied evidence in local baseline
fields before mutation. Failed apply rebinds it to the recovered invocation only
after file/service verification. Unknown prior evidence is preserved; external
content or metadata edits retain recovery-required. Applied publication in the
two config transaction operations requires existing metadata receipts, without
requiring the new candidate digest to equal the old configuration digest.

Configuration and binary update/rollback compensation verify an active service
against its captured enable policy, accepting an originally disabled service
without enabling it. Failed state queries, unknown state and policy drift remain
recovery errors. Forward health checks still require enabled. Update compensation
continues to refresh only previously confirmed applied evidence after recovery.

Restart, configuration apply, uninstall and standalone lifecycle now share the same preparation-through-close exclusive lock as update/rollback/restore/backup. The existing helper lives in common code for lifecycle reuse; nested backup/transactions preserve the caller's lock level. Argument/root/confirmation checks precede this boundary. Configuration compensation restores snapshot ownership/mode without normalizing them afterwards. Success paths explicitly propagate close failures, including lifecycle dry-run bookkeeping; uninstall preparation preserves its primary failure across directory cleanup and retains staging when close fails.

The existing unresolved-deployment guard also inspects standalone Core, node-init, install-state and sandbox-install transactions. Writers and protected reads refuse interrupted, abandoned-after-attempt, invalid or recovery-required evidence. Valid committed/rolled-back receipts allow progress. A narrow schema-2 retry exception accepts protected empty receipts with only BEGIN, private SNAPSHOT and ABANDONED events, without any service/restore/commit baseline or attempted step. It does not replay recovery across processes or infer service safety from an empty file manifest.

Catchable EXIT/INT/TERM during an active standalone transaction uses the existing registered rollback callbacks and then closes its lock level. Persisted valid COMMIT/rollback receipts take precedence over an interrupted memory-flag update. Completed callbacks finish a missing completion receipt without repeating file/service recovery. Invalid or already uncertain journal evidence is retained for manual inspection; invalid evidence closes without appending to the rejected journal. Original failures/signals retain their exit status, and an unclosed uncommitted success becomes an error. Recovery defers subsequent INT/TERM for that attempt. This does not catch SIGKILL, perform cross-process replay or establish real systemd recovery.

Restore binds its initial root/mode check to a device/inode pair. The parser opens with `O_NOFOLLOW|O_NONBLOCK`, checks the descriptor is the same regular file with protected ownership/mode, and reads tar data from that descriptor. Replacement with another file, symlink or FIFO is refused before candidate validation. This does not prevent a privileged writer changing bytes in place, authenticate the archive or replace the trusted-provenance requirement.

Restore compensation stops both managed units before recovering files. If a
stopped unit still reports `failed`, it clears that unit's failure with
`reset-failed` and independently requires `inactive` before continuing. A failed
reset, failed query or any remaining non-inactive state retains recovery-required;
it cannot authorize file replacement or applied promotion. Original resources,
service policy and previously confirmed applied evidence are then restored by
the existing transaction callback.

Internal staging callers receive paths through `pnm_make_temp_dir variable`, retaining cleanup registration in the calling shell. The zero-argument stdout interface remains available. Creation refuses unsafe/unregistered roots and removes the empty new directory on permission, registration or output failure. EXIT cleanup tolerates missing paths and reports removal failures on stderr without replacing the original command status. Uninstall calls backup directly and reads its fixed internal result field, retaining nested staging registration. This does not establish signal/crash transaction recovery.

## System boundary

PNM is a Bash management CLI for one Debian or Ubuntu VPS. It manages two independent proxy cores and is not in their data path:

| Core | Protocol | Default listener | systemd unit | Binary/configuration |
|---|---|---|---|---|
| Xray | VLESS + REALITY | TCP/443 | `xray.service` | `/usr/local/bin/xray`; `/usr/local/etc/xray/config.json` |
| Official Hysteria2 | Hysteria2 over QUIC | UDP/8443 | `hysteria-server.service` | `/usr/local/bin/hysteria`; `/etc/hysteria/config.yaml` |

The Core units and service accounts are separate. Xray runs as `xray`; Hysteria2 runs as `hysteria`. Xray's generated unit grants only `CAP_NET_BIND_SERVICE` for TCP/443 while retaining non-root execution. See `lib/service.sh` and its unit tests. These are source-level facts; a host's installed units still require direct verification.

Service-account provisioning/reuse validates a nonzero numeric UID and primary GID, the fixed home/shell policy, and the expected group name/GID. A service name or `nologin` shell alone is insufficient evidence of an unprivileged identity. TLS permission diagnostics validate leaf file ownership/modes and, when run as root, use the service identity's `test -r` probes to include ancestor traversal. This is an effective readability check, not proof that the Core successfully loaded a real certificate/key or passed its systemd sandbox restrictions.

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

`HY2_TLS_PIN_SHA256` retains its existing internal SPKI/base64 representation.
Selfsigned-pin client links derive `pinSHA256` from the configured leaf certificate's
full DER SHA-256 fingerprint in lowercase hex, as required by the official Hysteria
client. Failure to obtain this fingerprint suppresses only the HY2 link; a ready
Xray link remains available. Link generation does not migrate stored credentials.

## Install and apply flow

The public install path is `lib/install.sh` → preflight → `lib/apply-gate.sh` → `lib/deploy.sh`. The gate holds the exclusive lock through final health/deadline checks. Explicit sandbox, lifecycle and node/applied-state participants share one `deployment` transaction. Standalone sandbox and per-Core lifecycle wrappers retain independent transactions; arbitrary implicit transaction nesting is rejected.

Preflight probes the validated persisted `XRAY_PORT` and `HY2_PORT`. Invalid or missing node state produces an UNKNOWN port check alongside the configuration failure, without probing fallback ports. Preflight recovery listener attribution uses the same configured protocol/port pair and retains its ownership checks.

Forward Core health also probes validated persisted ports; unknown ports cannot
fall back to 443/8443 or borrow unrelated listeners. During recovered-applied
verification, desired ports may differ from the recovered generation. After the
runtime hash matches its captured baseline, the existing JSON/YAML parsers supply
the recovered port; Xray must use TCP and HY2 must retain the supported listen
form. Invalid runtime fields leave recovery unconfirmed rather than refreshing
applied evidence. Node initialization still defaults to TCP443/UDP8443.

`lib/transaction.sh` provides schema-2 file snapshots with numeric UID/GID/mode, directory identity/metadata receipts, rollback callbacks and inspection; schema-1 records remain inspectable. `lib/deployment-state.sh` extends that engine with protected deployment baselines and a durable resource-bound marker. Deployment progress journals and gate receipts are derived; standalone operations keep their existing journal commit convention.

Deployment publishes a durable uncertainty record before its marker. Uncertain publication or incomplete recovery retains evidence and blocks later writes and protected reads. Before commit, one recovery callback stops affected services, restores resource bytes/metadata and units, verifies each original service policy, then compensates created accounts and directories. Originally absent units remain absent; active-but-disabled baselines are preserved. Recovery refreshes applied InvocationID only for a previously confirmed, hash-matching runtime and unchanged original applied record.

Loaded units and existing Core resources require established PNM ownership receipts before replacement. Valid existing credentials are reused. INT/TERM/EXIT attempt in-process compensation; SIGKILL/reboot detection blocks further changes but does not implement automatic cross-process replay. These behaviors have local filesystem/mock evidence only; real systemd/reboot recovery remains G-02 acceptance work in `docs/TASKS.md`.

## Core lifecycle, health, and recovery

`pnm status` reports service state and detected Core versions. Root `pnm check`, `node show` and links take a shared lock and reject unresolved deployment state. Non-root `check` retains diagnostics with UNKNOWN deployment/configuration-readiness results; `node show` and links require root (link help remains public). Local listening is not a proof of public reachability or successful client handshakes. There is no implemented Profile model; installation targets both cores.

The Core operations include per-Core restart/log/apply/update/rollback and backup/restore/uninstall routes (`lib/core-ops.sh`). Updates use pinned versions and checksums. Restore stages and validates archive contents before applying. Feature presence in source is not by itself proof that every rollback/failure path is verified; consult `docs/TASKS.md` for current acceptance status.

Update/rollback retain the existing exclusive PNM lock from preparation through transaction completion and compensation. Argument validation/root checks precede this boundary; pending deployments are checked under the lock before preparation. Version pins, service state, current/previous binaries and configuration baselines are then read while cooperating PNM writers are excluded. The existing transaction lock is reentrant, and each wrapper releases only its own lock level, including early failures. Asset download remains inside this global boundary, so other writers and consistency-sensitive readers may report contention during preparation. This does not coordinate arbitrary privileged writers that ignore the PNM lock.

Update/rollback explicitly enroll metadata for the current binary, previous binary and `previous.env`, and verify all published transaction resources before commit. Compensation preserves an intervening content or metadata edit and reports recovery required. Transaction-close errors propagate without a success message, even if the commit already completed; outer lock cleanup still runs.

Restore parsing enumerates at most 64 visible members, rejects absolute/traversing names and payload-bearing directory entries, bounds the manifest to 64 KiB and declared resource totals to 512 MiB, and requires the complete 12-resource set before candidate validation. Before opening tar data, the parser lowers its own address-space budget to 128 MiB and CPU budget to 30 seconds, retaining stricter inherited soft/hard limits. This includes hidden PAX/GNU processing that occurs before a visible member is yielded. Memory/overflow/recursion exhaustion returns a parsing failure without candidate execution. CPU time is not a wall-clock deadline, and the budgets apply only to parsing. Candidate validation executes staged Core binaries as root; the operator must establish trusted PNM backup provenance using a separately retained trusted checksum. Root/mode/embedded approval data do not authenticate it. See D-009 in `docs/DECISIONS.md`.

Restore retains the same reentrant exclusive lock across archive staging, service/applied baselines and its transaction. Unknown load/active/enable states, including a missing unit with a live process, are refused before mutation. Both old processes must be observed stopped before runtime files are published. Protected `restore.env` stores the service baseline for manual recovery; it is never sourced or automatically replayed.

Restore enrolls file metadata and directory preparation in the existing transaction, including the directory created by service enable. Private destination directories must already be root-owned with root group; foreign ownership is refused rather than silently changed. File ownership normalization records only its fixed expected numeric UID/GID/mode, so intervening metadata edits cannot become a new expected state. Applied records and their directories participate in the same compensation. Recovery observes candidate processes stopped, restores original file bytes/metadata and service load/active/enable policy, and refreshes InvocationID only for originally confirmed, active evidence whose original record/configuration still match. Active-but-disabled baselines remain disabled; inactive/unconfirmed records retain their original bytes. Directory compensation follows service recovery. Resource verification precedes commit, and transaction-close errors suppress the success message. Failures report whether compensation succeeded and retain evidence when it did not. These paths have local filesystem/mocked-service evidence; real systemd, reboot and client acceptance remain open in `docs/TASKS.md`.

Restart/update/rollback carry forward only previously confirmed applied evidence. Under the transaction lock they capture the record, configuration digest and metadata; after health checks they publish the new invocation against that fixed digest through the existing transaction. Missing, changed or damaged evidence is retained without promotion. Compensation restores resource bytes and the service baseline before refreshing a previously confirmed active invocation; an inactive baseline keeps its original record. These applied writes explicitly enroll metadata before post-publication receipts, so external content/metadata drift retains recovery evidence rather than being silently overwritten. This does not implement automatic reboot reconciliation or race-free coordination with arbitrary privileged writers.

## Security boundaries

Backup holds the existing exclusive reentrant PNM lock before destination preparation and all twelve resource reads. It refuses pending deployment recovery and unsafe source/destination path components. Manifest ports come from the staged node configuration; Core versions are queried from staged executable copies, with `unknown` retained when probing fails. A private mode-0600 temporary archive on the destination filesystem is linked into place without replacing an existing target. CLI stdout and ordinary relative destinations remain compatible. Cooperating PNM writers are excluded; arbitrary privileged writers and runtime state changes outside PNM remain outside this guarantee. An uncatchable exit can leave the private hidden publication file; this is not an authenticated or crash-durable backup protocol.

- PNM does not configure SSH, Tailscale, UFW, OCI security groups, or cloud firewalls as part of normal installation.
- Managed service identities are validated and reused where policy permits. Rollback must not remove pre-existing accounts.
- Secret-bearing backup archives and client share links are sensitive. File modes and redacted diagnostics are part of the security model.
- Unknown port occupants must not be terminated automatically.

## Verification boundary

Automated tests live in `tests/unit/` and are invoked through `tests/run.sh` / the Makefile. Mock-based tests validate command logic and rollback behavior only within their fixtures. Debian 13/systemd behavior, reboot persistence, public firewall reachability, and external client protocol handshakes require an isolated Linux VM or explicitly authorized production read-only validation. Current outstanding verification is tracked in `docs/TASKS.md`.
