# PNM Roadmap

This is a planning document, not an implementation claim or authorization. Current source baseline, execution environment and acceptance blockers belong in [TASKS.md](TASKS.md). Historical gap IDs and rationale are in [the archived Phase 2 analysis](history/PHASE2_GAP_ANALYSIS.md); re-check the current code before starting an item.

## Phase status overview

| Phase | Goal | Status |
|---|---|---|
| Phase 1 | Targeted HY2 configuration/link consistency and TLS/SNI fixes | Source changes exist in current history; production/client verification is environment-specific and must not be inferred from unit tests |
| Phase 2 | Gap classification and minimal implementation plan | Completed as a read-only report in the historical archive; it records its own HEAD and findings |
| Phase 3 | Repair and accept existing defects G-01–G-06 | In progress / acceptance incomplete; see `TASKS.md` |
| Phase 4 | Desired-state deployment Profiles (`dual`, `reality`, `hy2`) | Planned; not implemented in this baseline |
| Phase 5 | Profile-aware health reporting, lightweight resource diagnostics, optional external checks | Planned; dependency on Phase 4 state semantics |
| Phase 6 | Verifiable firewall-rule ownership and additional recovery/secret protections | Design and ownership decisions required before any automatic rule deletion; planned |
| Phase 7 | Regression coverage, supported Linux VM acceptance, documentation and release readiness | Ongoing cross-phase work; release remains separately authorized |

## Phase 3 — Existing defect closure

**Objective:** Close or explicitly disposition G-01 through G-06 without adding Profile behavior or changing the proxy architecture.

1. G-01: verify source identity on deployed nodes and keep node/runtime reporting symmetric and evidence-based.
2. G-02: make failed first deployment restore the pre-operation PNM-managed resources, not just service state.
3. G-03: prove Core binary and version metadata update/rollback consistency with failure injection.
4. G-04: prove staged backup/restore validation, permissions, and failure rollback.
5. G-05: prove required-tool preflight fails before managed resources change.
6. G-06: prove HY2 TLS certificate/key ownership, modes, and service-account readability checks.

Do not use production nodes for fault injection. The acceptance evidence must state which tests are mocks, Linux/systemd integration, or real host observations.

## Phase 4 — Deployment Profiles

**Proposed capability:** `dual` (both cores), `reality` (Xray only), and `hy2` (Hysteria2 only), with `dual` as the new-install recommendation.

Before implementation, confirm that the existing node/deployment state can represent Desired State, Actual State, and PNM-managed resources without introducing a parallel state store. Switching must preserve binaries, configuration, certificates, and credentials; it is not an uninstall/reinstall. Do not automatically remove firewall rules without independently verifiable ownership. Public CLI syntax remains a design decision until compatibility is assessed.

## Phase 5 — Lifecycle and health observability

After Profile state semantics are approved, consider Profile-aware `SKIP` results for intentionally disabled cores, lightweight memory/swap/load/OOM observations using existing system interfaces, and optional external checks. Local unit/listener state must never be labeled external connectivity success. Preserve existing commands and exit-code semantics.

## Phase 6 — Firewall ownership and recovery security

First define and test how PNM proves a firewall rule is its own. Until that exists, do not automatically delete rules. Separately evaluate transaction recovery, secret-bearing backup protection, and recovery rehearsal needs. Do not add an encryption key-management system before the key custody and restore requirements are decided.

## Phase 7 — Regression and release readiness

Extend the existing `tests/unit/` suite and run repository gates (`make check`, `make shellcheck`, `make release-check`) where available. Run disposable Debian 13/systemd validation for unit, permission, reboot, and rollback behavior. Record external Xray/HY2 client results separately. Release/version/tag actions require explicit authorization and the release checklist in `RELEASING.md`.
