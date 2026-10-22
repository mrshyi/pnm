# PNM Current Tasks

**Last reconciled:** 2026-10-23 (A-03/A-04 main-flow continuation; Debian 13 WSL `make check` passes 219 tests; systemd/production acceptance remains open)

**Current increment baseline:** branch `dev`, HEAD `686328f134f5f19af8dd86b9779f0b661c476019`, VERSION `0.16.0-rc.1`.

This page is a status snapshot, not a test report. Status must be refreshed from current source, test output, or host evidence before it is changed. Historical Phase 2 analysis is preserved in [PHASE2_GAP_ANALYSIS.md](PHASE2_GAP_ANALYSIS.md).

## Active phase

**Phase 3 — existing defect fixes and acceptance.** Phase 4 has not started. Following the approved safety/main-flow work and the user's instruction to continue, the working tree implements the G-02 deployment owner and commit boundary. Local filesystem/mock tests pass; real systemd, reboot and client acceptance remain open.

Current review artifacts (2026-10-22):

- [Implementation and goal assessment](IMPLEMENTATION_ASSESSMENT.md): current source findings, refreshed G-01–G-06 interpretation, and additional A-01–A-05 findings.
- [Deployment transaction design](DEPLOYMENT_TRANSACTION_DESIGN.md): accepted direction with a dated working-tree scope and remaining differences from the original proposal.
- [Acceptance plan](ACCEPTANCE_PLAN.md): layered evidence and fault-injection matrix; not an executed test report.

Source review confirms listener health gates, symmetric Core runtime reporting, transactional previous-binary/metadata publication, staged restore validation, dependency checks, and HY2 TLS access checks already exist. Their systemd acceptance remains open. The prior increment addressed generic file UID/GID/mode recovery, sandbox directory compensation (A-02), ancestor-symlink rejection (A-05), and deployment-wide late failure compensation (A-01/G-02). The current increment repairs persisted-port preflight (A-03) and applied-evidence maintenance after explicit restart/update/rollback (A-04), with local filesystem/mock evidence below. Prioritize real lifecycle acceptance and the remaining G-03 through G-06 fault matrix before extending capabilities.

## Safety prerequisite slice — working-tree implementation

- New filesystem transactions use schema 2: file snapshots retain numeric UID/GID
  and mode; recovery sets ownership before final mode, publishes atomically and
  verifies the restored result. Schema 1 records remain inspectable; legacy or
  unknown schemas cannot perform filesystem recovery writes. This slice does not
  implement the proposed durable deployment commit marker.
- Sandbox directory changes record intent, baseline metadata and directory identity.
  Failure restores existing directories and removes new empty paths in reverse order.
  Foreign contents, replacement directories and metadata drift stop compensation and
  retain recovery evidence. Files restore before service-account/directory removal.
- Managed-path validation rejects symlink ancestors before mkdir/chmod or transactional
  writes. This assumes protected parents; it does not claim race-free path resolution
  against an actor concurrently replacing privileged ancestors.
- The file/directory inspector accepts verified compensation after an APPLIED receipt
  append fails and handles multiple files restored in reverse order. Short octal stat
  modes, including `0` and `40`, remain parseable.

Validation environment: local Debian 13.5 WSL, UID/GID 0, Linux temporary source
copies (not NTFS permission emulation); services and accounts remain mocked. Commands:
`make syntax security-scan shellcheck`, `bash tests/unit/test_transaction.sh`,
`bash tests/unit/test_host_apply.sh`, `bash tests/unit/test_sandbox_install.sh`, and
`make check`. Syntax, security scan and ShellCheck pass; transaction tests pass
25/25 and host tests 14/14. All 12 added regression cases pass, including the sandbox
directory failure/retry case. Independent source review found two receipt/mode edge
cases, both reproduced with failing tests and fixed before the final rerun.

The initial safety-slice `make check` exited 2: nine assertion failures plus early
node/deployment suite exits also reproduced on unmodified HEAD `7a8dfe1`. These
baseline test defects are now repaired as described below; that earlier failed run
is historical evidence, not the current working-tree result.

This slice does not establish whole-deployment rollback, cross-process crash recovery,
complete backup/restore caller migration, real systemd recovery, reboot behavior, or
external connectivity. Those remain G-02/G-03/G-04 and Linux acceptance work. No
production operation, version change, staging, commit, push or release was performed.

## Main-flow regressions — working-tree implementation

Root causes were reproduced in a fresh Linux temporary copy before correction:

- Cases shared flags and replaced functions across tests. A leftover dry-run flag
  produced exit 64 in the repeat-install case; a leftover recovery mock made the
  deployment suite exit before its summary. Cases now run in isolated subshells;
  parent-owned fixture cleanup and result counters remain in the suite process.
- The runner explicitly invokes Bash, so the HY2 suite runs even without its Git
  executable bit. Two harness regressions cover state isolation and fixture lifetime.
- A node fixture passed an undeclared array to the configuration loader. It now
  declares its output correctly. The loader also rejects scalar/indexed/readonly
  output targets before clearing them or interpreting a key as an arithmetic index;
  a regression confirms scalar/indexed targets are rejected without mutation.
- Health checks load their JSON output dependency. Node/link fixtures explicitly
  provide their configuration, real runtime hashes and applied records, plus mocked
  service invocation/listener observations. Drift assertions follow current statuses,
  and runtime fixtures remain present for both text and JSON checks.
- The external-CA fixture declares the DNS name in its certificate SAN. TLS expiry
  uses a real generated certificate and a controlled current time at its expiry
  boundary, replacing the invalid `openssl req -days 0` test input.
- The fresh-install link case now executes the real applied-record/node-state commit
  against its final sandbox configuration before requesting links. Certificate/SNI,
  configuration comparison and applied-evidence gates remain enabled.

Validation at completion of this earlier increment: Debian 13.5 WSL, root, temporary copy
`/var/tmp/pnm-mainflow.LKsphdp0`; real filesystem/crypto tools, mocked services and
listeners. `make check` **exit 0**, all **20 suite summaries / 184 tests passed**;
`make syntax security-scan shellcheck` **exit 0**. The full regression log is
`/var/tmp/pnm-mainflow.LKsphdp0.full.log`. Independent read-only review found no
actionable issue in this increment. This is local source/mock evidence; it does
not close G-02 or prove systemd recovery, reboot or public client connectivity.

| Item | Current status | Evidence / blocker | Next action |
|---|---|---|---|
| G-01 — runtime/config/link state | BLOCKED for production acceptance | Current `lib/node.sh` source prints an HY2 runtime row. Prior production output reportedly omitted it despite the same VERSION; deployed executable/source identity has not been verified in this session. | On an authorized host, perform read-only path/version/source-hash comparison; do not apply or upgrade as diagnosis. |
| G-02 — complete deployment rollback | IMPLEMENTED / local filesystem and mock checks PASS; systemd acceptance open | One deployment transaction now spans resources, lifecycle, applied/node state and final outer checks; durable marker and unresolved-deployment guards are tested. | Run the disposable-systemd/interrupt/reboot matrix in [the acceptance plan](ACCEPTANCE_PLAN.md); do not infer production readiness. |
| G-03 — Core update transaction | NOT TESTED for Phase 3 acceptance | Source contains update/rollback transactions in `lib/core-ops.sh`; the required failure-injection acceptance evidence is not present in this workspace. | Test binary, metadata, service, and rollback consistency in mocks and Linux VM. |
| G-04 — backup/restore safety | NOT TESTED for Phase 3 acceptance | Restore staging/validation code exists; bad archive, permission, TLS, and complete failure-recovery matrix lacks current acceptance evidence. | Run isolated restore failure tests; never restore an untrusted archive on production. |
| G-05 — dependency preflight | MOCK TESTS PASS / systemd acceptance open | Debian 13 WSL preflight suite passes 14/14, including configured ports, invalid-node refusal, repeat-install refusal and missing-tool checks. Mock results do not prove real systemd install ordering. | Verify missing tools before managed-resource mutation in a disposable systemd VM. |
| G-06 — HY2 TLS permissions | NOT TESTED for exception paths | Check and TLS permission code exists; wrong owner/mode and service-account readability cases have not been verified in Debian/systemd. | Exercise certificate/key ownership and access cases in a disposable VM. |

## G-02 deployment transaction — working-tree implementation

Root cause: sandbox/lifecycle/node-state participants previously committed separately,
before the apply gate's last health/deadline checks. The gate could report failure
after resources and `PNM_CONFIGURED=yes` had already been committed.

The gate now finishes one existing transaction only after its final checks. Explicit
participants cannot commit or close it. Compensation stops affected services,
restores files and metadata, reloads units, verifies each service's original
load/active/enabled policy, then compensates created accounts and directories.
Previously confirmed applied evidence is refreshed for the restored invocation;
unknown evidence remains unknown, and external edits are retained for recovery.

Deployment `commit.env` binds the protected resource receipts and snapshots.
Publication first persists an uncertainty record, then syncs resources and marker;
an uncertain publication blocks subsequent writes and protected reads. Derived
progress-log failures after a durable commit return success with warnings.
Interrupted or incomplete recovery is retained rather than automatically replayed.
Existing Core resources require verified ownership before service stop or overwrite.

Root `check`, `node show` and links use a shared lock and reject unresolved deployments.
Non-root `check` remains diagnostic, reports deployment state UNKNOWN and cannot
claim configuration/runtime readiness; `node show` and links require root, while
link help stays available. No lock-file permission widening was introduced.

G-02 increment validation (2026-10-23): Debian 13.5 WSL, UID/GID 0, Linux temporary copy
`/var/tmp/pnm-deployment.VpZmpc6r`. `make check` **exit 0**, **22 suite summaries /
202 tests passed**, no skipped cases; syntax/security scan (included in `make check`)
and `make shellcheck` **exit 0**. Deployment
fault tests pass **15/15**, real sandbox-participant suite **12/12**, and a real
non-root UID diagnostic boundary **1/1**. Systemd, accounts and listeners are mocked;
filesystem/crypto tools are real. Full log:
`/var/tmp/pnm-deployment.VpZmpc6r.precommit-final.log`.

Independent source review found ownership, enable-policy, baseline-publication,
commit-uncertainty and CLI-IFS edge cases. They were reproduced/fixed before the
final rerun; that review found no remaining blocker. The 2026-10-23 manual pre-commit
review additionally found that reused host self-signed TLS files were absent from
the transaction's written-resource list: later ownership recording failed, and
ownership changes lacked a recovery baseline. Host reuse now enrolls the same
certificate/key bytes before ownership normalization. A regression first failed
(11 passed / 1 failed), then passed (12/12), checking byte preservation and actual
numeric UID/GID/mode recovery inside a disposable filesystem. Focused logs:
`/var/tmp/pnm-deployment.VpZmpc6r.tls-before.log` and
`/var/tmp/pnm-deployment.VpZmpc6r.tls-after.log`.
No real systemd, power-loss,
reboot or external-client result is claimed. A-03/A-04 standalone lifecycle issues
remain outside this increment; G-03 through G-06 still need their acceptance matrix.

## A-03/A-04 main-flow continuation — 2026-10-23

- A-03 root cause: collection and recovery dispatch used TCP/443 and UDP/8443
  literals instead of validated persisted ports. Both now use node configuration;
  invalid/missing node state reports UNKNOWN ports without probing defaults. Four
  new regression cases first failed, then passed; the preflight suite passes 14/14.
- A-04 root cause: explicit restart/update/rollback changed systemd InvocationID
  without updating previously confirmed applied evidence. These operations now
  capture the original record/digest/metadata under the transaction lock and
  publish the new invocation through the same transaction after health checks.
  Publication is constrained to the captured digest. Missing, changed or damaged
  evidence is left as-is; explicit configuration apply remains the confirmation path.
- Compensation restores original bytes and service state, then refreshes only an
  originally active, confirmed invocation. An inactive baseline remains stopped
  with its original record. External configuration/record/metadata edits are
  retained with recovery required. Applied-file metadata is explicitly enrolled
  inside publication, before APPLIED/WRITE receipts; failed enrollment retains a
  PENDING expectation so uncertain recovery cannot overwrite the resource.
- The 13-case lifecycle suite exercises both Cores and all three commands using
  real file transactions, hashes, numeric metadata and version parsing, with
  simulated services/downloads/Core validation. It passes 13/13, including
  health, applied-write, commit and post-publication receipt failures; capture-
  and publication-stage configuration edits; metadata drift; inactive recovery;
  unconfirmed evidence and unchanged peer-Core state. Reported cases contain
  multiple command/Core combinations, rather than claiming each as a separate test.
- Read-only review found capture/publication digest and metadata-enrollment timing
  gaps. Failing regressions reproduced them before repair; final source re-review
  found no additional concrete issue. Focused red/green logs are retained under
  `/var/tmp/pnm-mainflow-next.*.log`; final full-check output is
  `/var/tmp/pnm-mainflow-next.final-check.log`.

Final validation: Debian 13.5 WSL, UID/GID 0, isolated Linux copy
`/var/tmp/pnm-mainflow-next`. `make check` **exit 0**, all **23 suite summaries /
219 tests passed**, no skipped cases; syntax and security scan are included.
`make shellcheck` **exit 0**. Earlier red/green checks and the final source review
are local evidence; service/download/Core validation boundaries remain as above.

This increment does not establish real systemd/service startup ordering, reboot
reconciliation, real download/Core validation, or client connectivity. The existing
applied/link guards remain enabled; reboot and external service restarts still
require separate acceptance and evidence reconciliation work. Filesystem checks
do not promise race-free coordination with arbitrary concurrent privileged writers.

## Verification already reported (historical host evidence)

A prior user-provided `proxy-tokyo` read-only report stated that PNM 0.16.0-rc.1, both Core services/listeners, `pnm check`, and selected permissions were healthy, and that public client connections had succeeded. This report is historical and was not independently refreshed in this documentation task. It does not close the local failure-injection gaps above or prove the current installed source matches this HEAD.

## Immediate next steps

1. Confirm deployed PNM source identity for G-01 using read-only checks.
2. Accept the repaired A-03/A-04 paths in a disposable systemd VM, including explicit commands versus reboot/external restart; do not treat local results as completed Phase 3 acceptance.
3. Use a disposable Debian 13 systemd VM for real lifecycle/recovery acceptance. The local WSL environment already provides Bash, make, ShellCheck, Python, ripgrep, zip/unzip, flock and OpenSSL for source and mock tests.
4. Extend the passing G-02 local fault tests to real systemd, then G-03 through G-06 acceptance; record exact commands, exits, and environment.
5. Reassess Phase 3 completion. Do not start Phase 4 automatically.

## Boundaries

The user explicitly requested review and a local Git commit, reconfirmed by continuing the task on 2026-10-23. Production apply/update/restore, SSH/Tailscale/UFW/cloud firewall changes, version changes, push, tags and releases remain outside this task's authorization.
