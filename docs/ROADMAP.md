# PNM Roadmap

This is a planning document, not an implementation claim or authorization. Current source baseline, execution environment and acceptance blockers belong in [TASKS.md](TASKS.md). Historical gap IDs and rationale are in [the archived Phase 2 analysis](history/PHASE2_GAP_ANALYSIS.md); re-check the current code before starting an item.

## Phase status overview

| Phase | Goal | Status |
|---|---|---|
| Phase 1 | Targeted HY2 configuration/link consistency and TLS/SNI fixes | Source changes exist in current history; production/client verification is environment-specific and must not be inferred from unit tests |
| Phase 2 | Gap classification and minimal implementation plan | Completed as a read-only report in the historical archive; it records its own HEAD and findings |
| Phase 3 | Repair and accept existing defects G-01–G-06 | Repair scope frozen; bounded Ubuntu acceptance pending; see `TASKS.md` |
| Phase 4 | Desired-state deployment Profiles (`dual`, `reality`, `hy2`) | Installed-node main flow basically complete; real systemd acceptance pending |
| Phase 5 | Profile-aware health reporting, lightweight resource diagnostics, optional external checks | Local status/resources main flow basically complete; local gates pass; external checks deferred |
| Phase 6 | Verifiable firewall-rule ownership and additional recovery/secret protections | User-scoped recovery diagnostics developed; local gates pass; firewall remains manual and broader capabilities deferred |
| Phase 7 | Regression coverage, supported Linux VM acceptance, documentation and release readiness | Local preparation and current-runtime Ubuntu CI pass; full real acceptance pending; release separately authorized |

## Phase 3 — Existing defect closure

**Objective:** Close or explicitly disposition G-01 through G-06 without adding Profile behavior or changing the proxy architecture.

1. G-01: verify source identity on deployed nodes and keep node/runtime reporting symmetric and evidence-based.
2. G-02: make failed first deployment restore the pre-operation PNM-managed resources, not just service state.
3. G-03: prove Core binary and version metadata update/rollback consistency with failure injection.
4. G-04: prove staged backup/restore validation, permissions, and failure rollback.
5. G-05: prove required-tool preflight fails before managed resources change.
6. G-06: prove HY2 TLS certificate/key ownership, modes, and service-account readability checks.

Do not use production nodes for fault injection. The acceptance evidence must state which tests are mocks, Linux/systemd integration, or real host observations.

The 2026-10-27 closeout freezes Ubuntu work to
[U-01–U-08](ACCEPTANCE_PLAN.md#ubuntu-closeout). Development dispositions and
explicit deferrals are recorded once in TASKS. Missing environments or speculative
failure combinations do not create new hardening stages by default. Debian is
deferred; bounded Ubuntu acceptance and the residual dispositions must be recorded
before Phase3 closure. Closure does not authorize Phase4, deployment or release.

## Phase 4 — Deployment Profiles

**Current implementation:** `dual` (both cores), `reality` (Xray only), and `hy2`
(Hysteria2 only) select active services on an installed node. Initial provisioning
continues to prepare both Cores; use `pnm profile set NAME --yes` afterward.

The optional node.conf field, actual service observations and existing applied
records retain separate meanings; see D-011. Switching preserves binaries,
configuration, certificates and credentials through the existing transaction
model. Real supported-systemd switching/compensation and reboot acceptance remain
pending. Single-Core initial provisioning is separate work. No firewall automation
or Phase5 resource/remote diagnostics are included.

## Phase 5 — Lifecycle and health observability

The user authorized progression after assessing the bounded Phase4 installed-node
flow as basically complete. Existing Profile-aware SKIP/refusal behavior remains;
status now separates selection from actual service state and uses configured
ports. `check --resources` adds optional memory/Swap/load/cumulative OOM readings
through existing output and exit semantics. Missing evidence remains UNKNOWN;
these observations never establish external connectivity or per-Core OOM blame.
Optional external checks are deferred. No monitoring daemon, metrics store,
resource tuning or additional hardening campaign is part of this increment.

## Phase 6 — Firewall ownership and recovery security

The user explicitly selected manual firewall management and recovery diagnostics
for this increment. `pnm recovery list|inspect` reuses the existing parser/shared
lock to expose sanitized state even while pending evidence blocks ordinary reads.
It preserves all evidence and leaves the write guard in force. No automatic
rollback/replay, firewall ownership adoption, rule creation/deletion or encrypted
backup/key-management feature is included. These broader capabilities remain
deferred, not implicitly complete. Existing mode0600 backup protection and the
trusted-provenance restore requirement remain. See D-006, D-009 and D-012.

## Phase 7 — Regression and release readiness

The user authorized Phase7 after basic completion of the scoped Phase6 recovery
flow. Local preparation now extends the existing Ubuntu privileged CI step with
the Profile and recovery suites, records Unreleased changes, and aligns release
instructions with configured ports/Profiles and separate CLI/Core installation.
The runtime implementation and regression cases are unchanged in this increment.

Current runtime source32423be passes its committed Ubuntu22.04/24.04 CI; the
authorized disposable Ubuntu U-02–U-08 acceptance remains pending. Reuse existing cases rather than extending the fault
matrix. Record real Profile/service and external Xray/HY2 client results
separately. Debian remains deferred. Missing targets/assets do not trigger more
hardening or establish readiness. Release/version/tag/publishing/deployment
actions remain separately authorized under `RELEASING.md`.
