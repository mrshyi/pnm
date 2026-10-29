# PNM Technical Decisions

This file records durable decisions supported by current project rules and implementation. It distinguishes decisions encoded in source from planning proposals. It is not a substitute for checking current code.

## D-001 — Keep two independent proxy cores

**Decision:** PNM manages Xray VLESS + REALITY and official Hysteria2 over QUIC as separate services; PNM is not part of the proxy data path.

**Reason:** Preserve transport choice and per-Core operational isolation without coupling one Core's lifecycle to the other.

**Evidence/status:** Project rule in `AGENTS.md`; separate unit/config/lifecycle paths in `lib/service.sh`, `lib/lifecycle.sh`, and `lib/core-ops.sh`. Implemented in source; integration behavior still requires Linux/systemd validation.

## D-002 — Keep `pnm` and existing interfaces stable

**Decision:** `pnm` is the CLI name. Existing command semantics, node configuration, and client URI formats are compatibility boundaries.

**Reason:** Existing scripts and installed nodes depend on them; changes should be incremental.

**Evidence/status:** `AGENTS.md`, `bin/pnm`, `lib/common.sh`, and README. Existing commands are retained; the additive Profile interface is described in D-011.

## D-003 — Separate desired settings, versions, secrets, applied evidence, and runtime observations

**Decision:** Keep node settings, approved Core version/checksum pins, credentials, applied-config evidence, and observed systemd/runtime state distinct.

**Reason:** Avoid treating configuration intent as proof that a service loaded it, and avoid exposing secrets in ordinary node reports.

**Evidence/status:** Paths and parsing in `lib/config.sh`, `lib/node.sh`, `lib/render.sh`, `lib/check.sh`, and `lib/core-ops.sh`. Implemented in source; complete deployment transaction consistency remains an open issue in `TASKS.md`.

## D-004 — Client links require verified applied configuration

**Decision:** Do not silently generate a Core link from stale desired state when runtime configuration or PNM applied evidence disagrees. Diagnose each Core independently and do not disclose private credentials except as necessary in an explicitly requested share link.

**Reason:** A syntactically valid but stale link can fail clients; independent gates preserve a working peer Core.

**Evidence/status:** `pnm_node_core_link_status` in `lib/render.sh`, node show/link paths in `lib/node.sh`, tests in `tests/unit/test_node.sh`. Implemented at source/test level; host behavior depends on deployed source identity.

Selfsigned-pin HY2 links use the configured leaf certificate's DER/hex SHA-256,
while the persisted SPKI/base64 field remains compatible with existing nodes.
The [official client implementation](https://github.com/HyNetworks/hysteria/blob/app/v2.13.0/app/cmd/client.go)
hashes the full end-entity certificate. The former SPKI wire value was rejected
in isolated real-client testing after a successful CA control. Fingerprint errors
omit only HY2, consistent with this decision's independent-Core gates.

## D-005 — Never silently rotate valid node credentials

**Decision:** Reuse valid existing REALITY/HY2 credentials; reject invalid existing credentials rather than replacing them silently.

**Reason:** Rotation can invalidate clients and make retries destructive.

**Evidence/status:** `lib/sandbox-install.sh`, `lib/config.sh`, and sandbox tests. Implemented at source/test level.

## D-006 — Keep host access and firewall management outside normal PNM install

**Decision:** Normal PNM install does not configure SSH, Tailscale, UFW, or cloud security groups; do not delete rules by port number or reset firewall state.

**Reason:** These are independent management-plane resources and automatic changes can lock out operators or remove user-owned rules.

**Evidence/status:** `AGENTS.md`, README, `lib/install.sh`, and release/security checks. Current policy is to leave these resources alone. Any future ownership-aware firewall feature requires separate approval and design.

## D-007 — Do not replace failures or uncertain evidence with success claims

**Decision:** Report mock tests, source inspection, Linux/systemd tests, VPS observations, and external client tests as distinct evidence classes.

**Reason:** Each proves a different boundary; mocks cannot establish systemd, reboot, network, or client behavior.

**Evidence/status:** Project instructions, `docs/RELEASING.md`, and `tests/`. This remains the required reporting policy.

## D-008 — Phase 3 deployment rollback must use the existing transaction model

**Decision status:** Accepted for the continued G-02 task; implemented in the 2026-10-22 working tree. Real systemd/reboot acceptance remains open.

**Decision:** Extend the existing transaction mechanism across one first-install deployment, with explicit participants and final commit owned by the outer gate. Preserve independent standalone Core operations. Include content, numeric ownership, permissions, service state and absence/presence in recovery evidence; reject unproven resource ownership before replacement.

**Reason:** Earlier component commits prevented full compensation after a late outer health/deadline failure. A single existing transaction avoids a second recovery engine and conflicting success criteria.

**Evidence:** `lib/apply-gate.sh`, `lib/deploy.sh`, `lib/sandbox-install.sh`, `lib/lifecycle.sh`, `lib/transaction.sh` and its `deployment-state.sh` helpers; local fault tests in `test_deployment_transaction.sh` and sandbox integration. Only deployment operations use the durable marker plus publication-uncertainty receipt; standalone schema-2 transactions retain journal authority. Incomplete recovery blocks further writes and protected reads; automatic cross-process recovery remains out of scope. Current results and boundaries are in `docs/TASKS.md`.

## D-009 — Restore requires independently verified trusted backup provenance

**Decision:** Preserve the existing trusted-PNM-backup input contract described in the [historical implementation assessment](history/IMPLEMENTATION_ASSESSMENT.md): the operator verifies origin and a separately retained trusted archive checksum before restore. Candidate validation runs the archive's Core executables as root. Root ownership, mode 0600, an embedded manifest or self-declared approved versions do not authenticate executable provenance. CLI commands and backup formats remain unchanged; signature/key-management infrastructure is outside this increment.

**Reason:** Tar member checks and parser budgets constrain parsing; they do not isolate or establish trust in programs executed after extraction. Automatically treating an archive's own approval/hash data as an independent trust anchor would give a false guarantee.

**Evidence/status:** `lib/core-ops.sh` applies 128 MiB address-space and 30-second CPU limits before tar parsing, preserves stricter inherited limits and handles resource-exhaustion exceptions. `lib/output.sh` and README state the trusted-input boundary. Local archive tests exercise resource limits and hidden PAX/GNU processing without executing candidates. Real Core/systemd/reboot/client acceptance remains separately recorded in `TASKS.md`.

## D-010 — Host install must preserve the approved binary/version pair

**Decision:** After checksum verification and staging, real-host installation
compares both Core programs' reported versions to the validated approved manifest
before publishing either managed binary, using the existing update parser.
Mismatch or an unparseable/failed version query returns78 through the existing
deployment rollback. No command, manifest format or standalone Core behavior changes.

**Reason:** An older authentic binary can match its explicitly approved checksum
while the manifest mistakenly labels it as a newer version. Hash verification
and version consistency prove separate properties; install and update must not
quietly enforce different desired-version boundaries.

**Evidence/status:** `pnm_sandbox_step_assets` in `lib/sandbox-install.sh`, the
version adapter in `adapters/network.sh`, and the targeted
`test_install_asset_versions.sh` regression. Programs remain trusted executable
inputs after explicit hash approval; reported version is not authenticity or
arbitrary-code sandboxing. Current automated/VM results are in `TASKS.md`.

## D-011 — Profiles select service policy without deleting managed resources

**Decision:** Store an optional `PNM_PROFILE=dual|reality|hy2` in the existing
schema-1 node configuration, interpreting absence as dual. The initial workflow
provisions both Cores, then `pnm profile set NAME --yes` selects active services.
Keep desired selection separate from actual active/enabled observations and
applied evidence. Switching uses the existing transaction and locks, retains
binaries/configuration/accounts/TLS/credentials, and leaves an unchanged Core's
process running. Trusted restore respects the archived selection.

**Reason:** This delivers profile switching without a parallel state store,
uninstall/reinstall cycle or new provisioning framework. Single-Core initial
provisioning and extended observability remain separate work; profile switching
does not imply completion of outstanding Phase3 deployment/reboot acceptance.

**Evidence/status:** `lib/profile.sh`, configuration validation, Core write guards,
link/check selection and restore flow; temporary-fixture tests cover normal
switches, unchanged peers and compensation. Real systemd acceptance is separate.

## D-012 — Recovery diagnostics inspect pending state without clearing it

**Decision:** Provide root-only `pnm recovery list|inspect` through the existing
shared lock and transaction parser. Diagnostics are an explicit exception to
pending-transaction read refusal; they report the guard's result and a bounded
record summary, without snapshots, private paths, journal details or credentials.
They do not modify evidence, replay callbacks or allow other readers/writers to
bypass the guard. File/directory counts are parser observations, not service or
account recovery proof. Unsafe stores and invalid evidence refuse success.

**Reason:** Operators need a usable diagnostic entry point precisely when pending
evidence prevents ordinary commands. Reusing the parser and lock avoids another
recovery engine. D-006 remains binding: firewall management is manual; there is
no automatic rule creation/deletion/adoption. D-009's trusted backup boundary
remains unchanged; encryption/key custody and cross-process replay are deferred.

**Evidence/status:** `lib/recovery.sh`, the transaction guard's diagnostic hint,
CLI/menu routing and private-fixture tests for blocked-state access, redaction,
evidence preservation, invalid input/store refusal and lock release.
