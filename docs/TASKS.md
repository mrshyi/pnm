# PNM Current Tasks

**Last reconciled:** 2026-10-23 (shared compensation verifies actual service state; Debian WSL `make check` passes 341 tests and isolated systemd harness passes 8/8; real Core/production acceptance remains open)

**Current increment baseline:** branch `dev`, HEAD `e48b1dd`, VERSION `0.16.0-rc.1`.

This page is a status snapshot, not a test report. Status must be refreshed from current source, test output, or host evidence before it is changed. Historical Phase 2 analysis is preserved in [PHASE2_GAP_ANALYSIS.md](PHASE2_GAP_ANALYSIS.md).

## Active phase

**Phase 3 — existing defect fixes and acceptance.** Phase 4 has not started. G-02, A-03/A-04, G-03/G-04 recovery, backup/input safety and G-06 access have local evidence in committed increments. The current continuation verifies compensation policy against real systemd stand-in services; actual Core, reboot and client acceptance remain open. The user has authorized consecutive local stages and commits, and confirmed Debian WSL is the only available test environment.

Current review artifacts (2026-10-22):

- [Implementation and goal assessment](IMPLEMENTATION_ASSESSMENT.md): current source findings, refreshed G-01–G-06 interpretation, and additional A-01–A-05 findings.
- [Deployment transaction design](DEPLOYMENT_TRANSACTION_DESIGN.md): accepted direction with a dated working-tree scope and remaining differences from the original proposal.
- [Acceptance plan](ACCEPTANCE_PLAN.md): layered evidence and fault-injection matrix; not an executed test report.

Source review confirms listener health gates, symmetric Core runtime reporting, transactional previous-binary/metadata publication, staged restore validation, dependency checks, and HY2 TLS access checks. Committed continuations repair generic recovery, deployment-wide compensation (A-01/G-02), directory/path safety (A-02/A-05), persisted ports (A-03), applied evidence (A-04), G-03 preparation/resources and G-04 filesystem compensation. The current stage extends restore dispatch and service/applied recovery with local filesystem/mocked-service evidence. Prioritize archive trust/resource limits, G-06 access cases and real lifecycle acceptance before extending capabilities.

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
| G-03 — Core update transaction | PARTIAL L1 PASS / Linux acceptance open | Local publication faults restore current/previous/version-metadata pairs; external edits and recovery failures are visible. Kernel flock tests now cover preparation, contention, unresolved deployments, reentrancy and cleanup errors. | Run the real systemd binary/metadata/service/concurrent-command/interruption matrix in a disposable VM. |
| G-04 — backup/restore safety | PARTIAL L1 PASS / Linux acceptance open | Locked backup snapshot/manifest, caller staging cleanup, parser budgets/file identity and mocked restore service/applied recovery have local evidence. | Verify unresolved standalone journal guards, then accept real systemd, interruption/reboot and concurrent commands before closure. |
| G-05 — dependency preflight | MOCK TESTS PASS / systemd acceptance open | Debian 13 WSL preflight suite passes 14/14, including configured ports, invalid-node refusal, repeat-install refusal and missing-tool checks. Mock results do not prove real systemd install ordering. | Verify missing tools before managed-resource mutation in a disposable systemd VM. |
| G-06 — HY2 TLS permissions | PARTIAL local DAC PASS / service integration open | Real root/nobody permission probes cover ownership/mode, ancestor denial and tool/metadata exceptions; account names/NSS are mapped. Privileged service identities are refused. | Verify the actual hysteria account, real TLS loading and systemd sandbox access in a disposable VM. |

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

## G-03 resources / G-04 archive continuation — 2026-10-23

G-03 root cause: current/previous binaries and `previous.env` used ordinary file
publication without explicit metadata enrollment. On a later failure, rollback
could overwrite an external chmod/chown while reporting recovery success. A failing
regression reproduced mode 0640 being replaced by the original 0755. All three
resources now use the existing required-metadata policy, and update/rollback verify
all published resources before commit. Intervening edits retain recovery evidence.

The lifecycle suite now passes 17/17 cases. Four added cases cover both Cores and
update/rollback: failures before/after each of three publications (24 combinations),
metadata edits to each slot, rejected candidate versions, and restart/recovery
failures. Publication recovery compares all slot hashes and numeric mode/UID/GID;
root runs use an actual 65534:65534 previous-slot baseline. Service/download/Core
validation remains simulated, and the peer Core is checked for isolation. These
are fixture combinations within four tests, not separate acceptance counts.

G-04 root causes: manifest size was not bounded, absolute paths were normalized
into accepted names, and root/directory placeholders could skip payload checks.
Parsing now stops after 64 visible members, bounds the manifest to 64 KiB, counts
it in the 512 MiB declared-resource limit, rejects absolute/traversing names and
nonzero directory payloads, and requires all 12 resources before validation. The
archive suite passes 2/2 cases: a complete package reaches an isolated validation
stub; 12 malformed-package scenarios stop before that stub. The fixtures contain
non-executable bytes and no candidate/host service operation runs.

Red/green logs: `/var/tmp/pnm-recovery-next.core-red.log`,
`/var/tmp/pnm-recovery-next.archive-red.log`,
`/var/tmp/pnm-recovery-final.root-red.log`,
`/var/tmp/pnm-recovery-final.core.log`, and
`/var/tmp/pnm-recovery-final.archive.log`. Source review found the root-placeholder
gap; its regression failed before repair and final static re-review confirmed the fix.

Final validation: Debian 13.5 WSL, UID/GID 0, isolated Linux copy
`/var/tmp/pnm-recovery-final`; `make check` **exit 0**, **24 suite summaries /
225 tests passed**, including syntax/security scan; `make shellcheck` **exit 0**.
The full log is `/var/tmp/pnm-recovery-final.check.log`. These are local
filesystem/mock results with the boundaries above, not real service acceptance.

At completion, that increment did not close G-03/G-04: mutable baseline reads before
transaction locking still needed concurrency work (addressed in the continuation
below); tar-internal PAX/GNU extension resource limits
are not accepted; staged binaries still require trusted provenance; full restore
write/directory/service/applied recovery and real systemd/reboot/client tests remain
open. The visible-member limits do not make arbitrary hostile archives safe.

## G-03 preparation lock continuation — 2026-10-23

Root cause: update/rollback cached mutable versions, current binary bytes and
service state before acquiring the transaction lock. Another cooperating writer
could complete between preparation and publication. A deterministic subprocess
writer reproduced rollback returning success with installed version 1.2.4 when
its cached target was 1.2.2, while replacing the previous slot with an older cached
current binary. Lock contention and unresolved deployments also occurred only
after preparation had already run.

Public entry points retain their argument/root checks, then use the existing
reentrant exclusive lock around preparation and the nested transaction. The
pending-deployment guard runs before preparation under that lock. Each wrapper
releases its own level on success or failure, preserving a caller's existing lock.
Downloads intentionally remain inside the global lock rather than adding an
optimistic preparation/revalidation mechanism. Transaction-close failures now
propagate instead of continuing to a success message; committed state may already
exist when this cleanup error is reported.

The Core suite passes 22/22 cases. Five added cases cover both Cores and both
commands: a real flock-protected subprocess writer at the transaction boundary,
another lock owner's refusal before staging, unresolved-deployment refusal before
staging, caller-owned reentrancy, and close-error propagation. Tests check binary/
previous/version pairing, peer-Core isolation, lock depth and actual reacquisition
with flock, not only mocked lock calls. Service state, assets and Core validation
remain simulated. The original three lock/baseline cases failed before repair;
the close-error case separately reproduced exit 0 instead of 70 before correction.

Focused logs: `/var/tmp/pnm-core-lock.red.log`,
`/var/tmp/pnm-core-lock.close-red.log`, and
`/var/tmp/pnm-core-lock-final.core.log`. Read-only source review found no further
concrete issue in this delta. Final checks in the isolated Debian 13 WSL copy
`/var/tmp/pnm-core-lock-final`: focused Core suite **exit 0, 22 passed**;
`make check` **exit 0, 24 suites / 230 passed / 0 failed**, including syntax and
security scan; `make shellcheck` **exit 0**. Full-check and lint log:
`/var/tmp/pnm-core-lock-final.check.log`.

This is local cooperating-writer evidence; full
parallel CLI/systemd/reboot/client acceptance and noncooperating privileged-writer
races are not established. G-04 restore-write recovery and archive-extension
resource limits remain open.

## G-04 filesystem compensation continuation — 2026-10-23

Root causes reproduced with real Linux files: the restore callback normalized
ownership/modes after restoring snapshots, changing `751:65534:65534` to
`640:0:0`; directory mode `711` remained at `755`, and newly created paths were
not removed. The original two regressions failed before repair and passed after.

Restore now uses existing directory receipts, enrolls every published file's
metadata, and verifies resources before commit. Existing private destination
directories with non-root ownership/group are refused before chmod. File owner
changes must match a fixed mode/numeric UID/GID tuple before metadata is recorded.
The metadata recorder's optional expected tuple checks its actual stat sample;
existing callers without that argument retain their behavior. This prevents a
post-publication/owner-change chmod from becoming an accepted new expectation.
Applied records and newly created record directories participate in compensation.
The callback trusts original snapshots instead of applying candidate ownership
again, and restores directories after files and service recovery. Close errors
propagate without a success message.

The focused suite passes **9/9** cases: original file metadata/content, existing/new
directories, final owner enrollment, publication metadata drift, partial chown
failure, drift during chown and during enrollment, symlink/foreign-owner refusal,
and applied-record/directory compensation. Fixtures use real numeric ownership
under WSL root; named service-account ownership and service calls are simulated.
Tests refuse filesystem mutations outside private fixtures. Two extra review
regressions first reproduced incorrect success before their fixes.

Focused logs: `/var/tmp/pnm-restore-next.red.log`,
`/var/tmp/pnm-restore-next.owner-red.log`,
`/var/tmp/pnm-restore-next.enroll-red.log`, and
`/var/tmp/pnm-restore-final.focused.log`.

Final validation: isolated Linux copy `/var/tmp/pnm-restore-final` in Debian WSL;
focused suite **exit 0, 9 passed**; `make check` **exit 0, 25 suites / 239 passed /
0 failed**, including syntax/security scan; `make shellcheck` **exit 0**. Full log:
`/var/tmp/pnm-restore-final.check.log`. Read-only review confirmed the fixed-tuple
enrollment change and found no further concrete issue in this delta.

These tests call the real publication/compensation helpers and applied recorder;
they do not execute a staged Core or prove complete restore orchestration,
systemd state/invocation recovery, lock-before-baseline ordering, reboot, public
client connectivity, archive provenance or PAX/GNU resource limits. Those remain
the next stages. No production operation or version change is included.

## G-04 restore dispatch and recovery continuation — 2026-10-23

The real parser/dispatch regression initially passed 1/6 cases: preparation
preceded lock contention, files could be published while old processes were
running, unknown service baselines were accepted, late rollback left stale applied
InvocationIDs, and ineffective recovery was not detected/reported.

Restore now holds the existing write lock from staging through completion, takes
validated load/active/enabled and applied baselines under it, observes both old
processes stopped before publishing, and has one abort path reporting original
and recovery failures. Recovery stops/disables candidate services before restoring
files, verifies each original service policy and refreshes only previously
confirmed active applied evidence against the restored config/record baseline.
It preserves active-but-disabled, absent and inactive baselines; unknown evidence
is not promoted on failure. The shared applied recovery helper now checks active
state instead of the fresh-install requirement to be enabled. A root0600
`restore.env` retains service baseline data for manual inspection after interruption;
no automatic cross-process replay is introduced.

The 15-case dispatch suite additionally covers late write/applied/commit/health
faults, pending deployments, real flock contention/reentrancy/reacquisition,
cleanup errors, external original applied edits, live processes behind missing
units, ineffective stop/restart, and compensation of enable-created wants
directories. Review's missing-unit and wants-directory cases, plus an ineffective
stop case, reproduced 12 passed / 3 failed before correction. Static re-review
found no further concrete issue in this delta.

Only the two managed-destination helper boundaries are mapped into a private host
tree. Archive parsing, command dispatch, file/directory transactions, hashes,
applied records and kernel flock are real; staged Core execution, service state
and named service accounts are simulated. Non-root CI additionally simulates the
root ownership policy at those private boundaries; root runs use real numeric
ownership. This is not real systemd, reboot or client connectivity evidence.

Logs: `/var/tmp/pnm-restore-flow-next.red.log`,
`/var/tmp/pnm-restore-flow-next.review-red.log`,
`/var/tmp/pnm-restore-flow-next.focused.log`. Archive provenance/resource limits
and G-06 access validation remain the following local stages.

Final validation: Debian WSL isolated copy `/var/tmp/pnm-restore-flow-final`,
`make check` **exit 0, 26 suites / 254 passed / 0 failed**, including syntax and
security scan; `make shellcheck` **exit 0**. Log:
`/var/tmp/pnm-restore-flow-final.check.log`. The final test-only non-root boundary
adaptation was checked separately in `/var/tmp/pnm-restore-flow-portable`:
`bash tests/unit/test_restore_flow.sh` as root and
`runuser -u nobody -- bash tests/unit/test_restore_flow.sh` both **exit 0, 15/15**;
logs end in `.root.log` and `.nobody.log`. Production source was unchanged by this
test adaptation; root exercises actual UID/GID while non-root simulates root policy.

## G-06 service identity and TLS access continuation — 2026-10-23

Root cause: the existing service identity validator checked name, home, shell and
matching group IDs but accepted UID 0 (and a zero primary GID). That could allow
account provisioning/reuse to accept a privileged service identity. A regression
first reproduced `xray UID=0` returning 0 instead of 78 (6 passed / 1 failed).
The shared validator now requires nonzero numeric UID/GID and the fixed group name,
as well as the existing home/shell/GID checks. All 7 account tests pass, including
both Cores, invalid IDs/group names and no useradd/groupadd calls on refusal.

Eight new access cases run with WSL root and the existing nobody identity. No
host account/group is created or changed. NSS/name mapping presents that identity
as hysteria to the policy checker; actual file UID/GID/mode, ancestor access and
`runuser -u nobody -- test -r` are Linux permission checks. Cases cover successful
readability probes; a root0700 ancestor despite correct leaf metadata; wrong
certificate/key owner/group/mode, symlink or missing file; privileged NSS identity;
missing runuser; unavailable metadata; unconfigured/nonstatic TLS; and invalid
Secret metadata. Diagnostics leave TLS bytes/metadata unchanged and do not expose
the synthetic key/password. These are eight tests with table-driven scenarios.

The test suite explicitly skips with 0 executed cases when root/runuser/nobody
are unavailable. It does not claim real hysteria account provisioning, certificate
parsing/loading, SELinux/AppArmor/systemd sandbox access, daemon startup or client
handshake success. Those require the unavailable disposable systemd environment.
Static review found no concrete issue in this delta.

Focused logs: `/var/tmp/pnm-access-next.accounts-red.log`,
`/var/tmp/pnm-access-next.accounts-green.log`, and
`/var/tmp/pnm-access-next.tls.log`.

Final validation: isolated Debian WSL copy `/var/tmp/pnm-access-final`,
`make check` **exit 0, 27 suites / 263 passed / 0 failed**, no root-run skipped
cases; syntax/security scan and `make shellcheck` **exit 0**. Log:
`/var/tmp/pnm-access-final.check.log`. Account suite as actual nobody **7/7,
exit 0**; the root-only TLS access suite explicitly skips **0 executed / exit 0**
under nobody. Logs: `/var/tmp/pnm-access-final.accounts-nobody.log` and
`/var/tmp/pnm-access-final.tls-nobody.log`. A final test-name/comment clarification
to "readability probes" was rerun **8/8, exit 0** without a production-source
change (`/var/tmp/pnm-access-next.tls-label-final.log`).

## G-04 archive parser budgets and trusted input — 2026-10-23

Root cause: tarfile consumes PAX/GNU internal extension records before yielding
members, so visible member/count/size checks did not bound their processing.
The pre-fix regression passed 3/5 cases: the parser retained the external test
launcher's 192 MiB/unlimited-CPU limits rather than imposing its own budget, and a
large hidden PAX payload produced an uncaught MemoryError traceback.

The parser now lowers its own RLIMIT_AS to 128 MiB and RLIMIT_CPU to 30 seconds
before opening the archive, preserving stricter inherited soft/hard limits.
It catches memory/overflow/recursion exceptions and returns parsing failure before
candidate validation. Existing 64-member, manifest and declared-size checks remain.
The five-case suite adds observed process-limit checks, stricter inherited
96 MiB/10-second limits, and large PAX/GNU/recursive-global-PAX cases. The fixture
producer streams small zero-filled chunks; the test launcher already limits the
old parser to 192 MiB to protect the WSL host. Candidates are not executed.

D-009 formalizes the already documented trusted-PNM-backup input policy. Restore
help and README state that candidate validation executes packaged Core programs
as root and that provenance is independently checked by the operator against a
separately retained trusted checksum. No new signing/key-management system or
backup/CLI format is introduced. Limits cover parser address space/CPU, not wall
time, candidate executable behavior or archive authenticity.

Red/green logs: `/var/tmp/pnm-archive-budget-next.red.log` and
`/var/tmp/pnm-archive-budget-next.green.log`. Read-only review found no concrete
issue or overstated trust guarantee in this delta.

Final validation: isolated Debian WSL copy `/var/tmp/pnm-archive-budget-final`,
`make check` **exit 0, 27 suites / 266 passed / 0 failed**, including syntax and
security scan; `make shellcheck` **exit 0**. Full log:
`/var/tmp/pnm-archive-budget-final.check.log`. Archive suite under actual nobody
also passes **5/5, exit 0** (`/var/tmp/pnm-archive-budget-final.nobody.log`).

Remaining source follow-up: backup currently copies mutable live files before
taking a lock, its manifest uses fixed default ports, and temporary cleanup
registration occurs inside command substitutions. Refresh these main-flow
boundaries before treating G-04 as locally complete. Real systemd/interruption,
VM reboot and external protocol acceptance remain open.

## G-04 temporary staging cleanup — 2026-10-23

Root cause: command substitutions around the nine direct `pnm_make_temp_dir`
calls registered private paths only in child shells. A restore candidate rejection
left its extracted staging directory after EXIT. The helper also lost registration
errors, and failed cleanup could replace the primary command error. Internal
callers now use scalar output arguments in the current shell; the existing stdout
interface remains compatible. Both output paths remove empty new directories on
publication failure. Missing registered paths are harmless, and failed removal
warns on stderr while preserving status.

The staging suite grew from three to ten cases, with real private filesystem and
child EXIT behavior. Initial red evidence was 3 passed / 4 failed; exit-handling
additions produced 7 passed / 2 failed. Independent review found the stdout failure
case, reproduced with `/dev/full` (9 passed / 1 failed) and fixed before final
checks. Review accepted the correction. No host services or accounts were changed.
Whole-operation backup capture inside uninstall remains the next stage, together
with snapshot locking and manifest ports.

Final verification: frozen Debian WSL Linux copy `/var/tmp/pnm-cleanup-final`,
`make check` **exit 0, 27 suites / 273 passed / 0 failed** (syntax/security scan
included), `make shellcheck` **exit 0**. Actual nobody staging suite **10/10,
exit 0**. Logs: `/var/tmp/pnm-cleanup-final.check.log`,
`/var/tmp/pnm-cleanup-final.lint.log`, `/var/tmp/pnm-cleanup-final.nobody.log`.
These checks cover private staging and mocked service/Core paths, not real
systemd interruption/reboot or external client connectivity.

## G-04 backup snapshot consistency — 2026-10-23

Root cause: backup copied live resources before any PNM lock, used fixed default
ports and queried live executables for the manifest. Uninstall captured the whole
backup function in a child shell, losing its staging cleanup registration.

Backup now reuses the exclusive Core-operation lock across preparation, snapshot
and publication. It checks pending deployment recovery before staging and validates
source/destination ancestors. Manifest ports and version probes use the staged
snapshot. Uninstall calls it directly, retains the result in `PNM_CORE_BACKUP_PATH`
and propagates errors. CLI stdout is unchanged. A same-filesystem private 0600
archive is hard-linked into place without replacing a late-created target;
ordinary creation failures remove the private partial output.

After extracting only the fixed source-path boundary for private fixtures, the
old behavior passed 2/8 cases. Root and actual nobody runs now pass 9/9, including
real independent `flock` exclusion during copying, pending recovery, staged
manifest, symlink ancestor refusal, late destination preservation, tar failure,
same-shell uninstall dispatch and relative destination/stdout compatibility.
The relative-path regression was reproduced at 8 passed / 1 failed and repaired.
Independent review accepted the bounded delta after this compatibility fix.

Logs: `/var/tmp/pnm-backup-next.mapped-red.log`,
`/var/tmp/pnm-backup-next.relative-red.log`,
`/var/tmp/pnm-backup-next.relative-green.log`, `/var/tmp/pnm-backup-next.nobody.log`.
Final frozen copy `/var/tmp/pnm-backup-final`: `make check` **exit 0, 28 suites /
282 passed / 0 failed**, including syntax/security scan; `make shellcheck`
**exit 0**. Logs: `/var/tmp/pnm-backup-final.check.log` and
`/var/tmp/pnm-backup-final.lint.log`. Services/NSS are mocked and
only synthetic fixture binaries run. Protected parents and cooperating writers
remain assumptions; this does not authenticate archives or prove crash durability.
An uncatchable exit may leave a private hidden publication file. Restore input
identity and standalone catchable interruption remain source follow-ups, followed
by real systemd/reboot/client acceptance.

## G-04 restore archive file identity — 2026-10-23

Root cause: shell ownership/mode checks and Python tar parsing opened the archive
path separately. A replacement after the check could reach candidate validation;
a swapped FIFO could block waiting for a writer. The shell now records device and
inode in the same stat as mode/UID. Python opens without following a leaf symlink,
uses nonblocking open so fstat can reject FIFOs, validates the descriptor's regular
type/owner/mode/identity and reads that same descriptor through tarfile. ExitStack
closes both stream and parser on every parsing failure.

Four regressions replace the checked file with another regular file, symlink or
FIFO, or alter its mode to 0644. Original behavior: **5 passed / 4 failed** in the
nine-case archive suite (`/var/tmp/pnm-archive-identity-next.mode-red.log`); the
old FIFO path has a five-second test timeout. Synthetic candidates never execute.
Static independent review found no concrete issue in the fix. Nonroot test policy
substitutes only the shell root-UID predicate and retains real device/inode/mode;
the descriptor check uses the actual effective identity.

Final fixed copy `/var/tmp/pnm-archive-identity-final`: `make check` **exit 0,
28 suites / 286 passed / 0 failed**, including syntax/security scan;
`make shellcheck` **exit 0**. Actual nobody archive **9/9**, staging **10/10**
and restore dispatch **15/15**, all **exit 0**. Logs use that same prefix:
`.check.log`, `.lint.log`, `.nobody.log`, `.staging-nobody.log`,
`.restore-nobody.log`. This closes the checked/opened-object
window, not privileged in-place modification or trusted provenance. Standalone
transaction interruption and real systemd/reboot/client acceptance remain open.

## Standalone transaction catchable-exit recovery — 2026-10-23

Root cause: runtime EXIT compensated active deployments only. Standalone Core
transactions could leave candidate files/services after TERM, INT or unexpected
exit, despite having registered recovery callbacks. The original eight-case
engine regression passed 3 and failed 5. The runtime now calls an existing-engine
exit helper, defers repeated INT/TERM during recovery, invokes callbacks only for
valid interrupted evidence, closes the owned lock level and preserves the primary
error/signal. An unclosed uncommitted exit 0 becomes 70. Committed/completed work
is not compensated again; missing callbacks retain uncertainty.

Independent review found deterministic COMMIT-receipt/flag and rollback-receipt/flag
signal windows (10 passed / 2 failed). The helper now checks existing journal
authority in a child inspector without altering active receipt arrays. Completed
callbacks can finish their missing completion receipt. Earlier uncertainty remains
inspectable after ROLLBACK_COMPLETE, while COMMIT/ROLLED_BACK remain final. Invalid
or already uncertain evidence is not an automatic replay request. A journal-symlink
regression also proved close could write to rejected evidence (15 passed / 1 failed);
invalid close now skips journal writes while releasing memory/lock state.

Final ROLLED_BACK publication also has a signal-before-memory-cleanup regression
(16 passed / 1 failed before correction). A persisted completed recovery now
closes without appending a second terminal event.

The dedicated suite now has 17 cases; focused root/nobody runs both pass
17/17, with syntax/security scan/ShellCheck exit 0. Two actual restore dispatch
TERM cases exercise the existing file/directory/applied/service callbacks against
private files and mocked services: one verifies original resources, active/enable
policy and confirmed applied state; the other refuses file recovery if candidate
processes cannot be observed stopped, retaining RECOVERY_REQUIRED. Restore suite
17/17 also passed under actual nobody. No real systemd/Core execution is claimed.

Logs: `/var/tmp/pnm-interruption.red.log`, `.receipt-red.log`, `.retained-red.log`,
`.invalid-red.log`, `.symlink-red.log`, `.symlink-green.log`, `.symlink-nobody.log`
(all latter suffixes share `/var/tmp/pnm-interruption`);
`/var/tmp/pnm-interruption-final-v2.restore-nobody.log`,
`/var/tmp/pnm-interruption.close-red.log`, `.close-green.log`, `.close-nobody.log`.
Final fixed copy `/var/tmp/pnm-interruption-final-v4`: `make check` **exit 0,
29 suites / 305 passed / 0 failed**, including syntax/security scan;
`make shellcheck` **exit 0**. Logs: `.check.log` and `.lint.log` under that prefix.
v1-v3 were intermediate checks before the final boundary fix.
SIGKILL and unresolved standalone journal guards remain the next source stage;
automatic cross-process recovery remains outside scope.

## Unresolved standalone transaction guard — 2026-10-23

Root cause: pending-state guards considered deployment operations only. A real
private child process killed by SIGKILL could leave changed bytes and INTERRUPTED
Core receipts while a later writer or protected reader was allowed through.
Recovery-required, service-only interruption, damaged metadata and abandoned
service attempts had the same gap. The original suite passed 2 and failed 6.

The existing guard now covers standalone Core, node-init, install-state and
sandbox-install evidence through the existing inspector. Only valid committed or
rolled-back records permit progress. Damaged metadata with journal/resource or
service evidence is rejected. A strict empty-abandonment exception permits retry
only for protected schema-2 metadata, empty file/directory/account receipts, no
service/restore/deployment/commit baselines, and an exact BEGIN / optional private
SNAPSHOT / ABANDONED journal. Attempted service steps cannot masquerade as empty.
No journal is evaluated as shell code or automatically replayed.

Review found parseable-but-incomplete metadata, unknown-operation skipping and a
missing file-attributes receipt check. Added regressions failed 3/12 before the
fix. The guard now validates required metadata structure, inspects unknown
producers for valid terminal evidence, and refuses the empty-abandonment exception
whenever a publication attributes receipt exists. Focused root/nobody suites pass
12/12 with syntax/security scan/ShellCheck exit 0. A further dangling-baseline
regression failed 1/13; both paths now share the same existence check, including
ordinary and dangling service/commit/attributes receipts. Final focused root and
nobody suites both pass **13/13, exit 0**, including valid unknown-producer terminal
records (`/var/tmp/pnm-pending-core.compatibility.log`, `.compatibility-nobody.log`).
Real SIGKILL targets only the test's own child; production services are untouched.
Logs: `/var/tmp/pnm-pending-core.red.log`, `.extended-green.log`, `.nobody.log`,
`.extended-lint.log` (all suffixes share `/var/tmp/pnm-pending-core`).
Review regression logs: `/var/tmp/pnm-pending-core.review-red.log`,
`.review-green.log`, `.review-nobody.log`, `.review-lint.log` under that prefix.
Final fixed copy `/var/tmp/pnm-pending-core-final-v3`: `make check` **exit 0,
30 suites / 318 passed / 0 failed**, including syntax/security scan;
`make shellcheck` **exit 0**. Logs: `.check.log` and `.lint.log` under that prefix.
This is persisted-state refusal,
not reboot recovery or real Core/systemd acceptance.

Read-only environment refresh also confirms Debian WSL PID 1 is systemd and
`systemctl is-system-running` reports `running`. No systemd integration test has
yet run. An independent disposable VM and real Core/client/reboot evidence remain
unavailable; uniquely named test services can provide a narrower future check.

## Remaining Core preparation and configuration compensation — 2026-10-23

Root cause: restart/apply/uninstall/lifecycle read mutable preparation state before
transaction locking; config compensation normalized ownership/mode after restoring
the original snapshot. The first four regressions all failed. These paths now
reuse the existing exclusive write helper from common code, before preparation
through close. Nested backup/transaction lock levels remain reentrant. Compensation
retains the verified original numeric ownership/mode without a second normalization.

Review identified success paths swallowing close errors in conditional callback
context: uninstall/dry-run regressions failed 2/7, apply failed 1/14 and Core evidence
failed 1/22. Additional preparation injection confirmed uninstall snapshot/begin
errors became success after rmdir. Success close and dry-run bookkeeping now
propagate errors; preparation cleanup preserves the primary error. A close failure
retains private uninstall staging. Private chmod and post-commit stage cleanup also
propagate failure explicitly.

Focused suites pass preparation **8/8**, apply/CLI **14/14**, lifecycle evidence
**22/22**, and lifecycle **3/3**; syntax/security scan/ShellCheck exit 0. The tests
use real independent flock and filesystem metadata, with service/NSS boundaries
mapped into fixtures. Uninstall fault tests never move host files or call host
services. Independent review accepted the corrected delta. Red/green logs share
`/var/tmp/pnm-core-preparation`: `.red.log`, `.errors-red.log`, `.errors-green.log`,
`.apply-red.log`, `.apply-green.log`, `.restart-red.log`, `.restart-green.log`.
Final fixed copy `/var/tmp/pnm-core-preparation-final`: `make check` **exit 0,
31 suites / 327 passed / 0 failed**, including syntax/security scan;
`make shellcheck` **exit 0**. Actual nobody preparation **8/8** and apply **14/14**,
both **exit 0**. Logs: `.check.log`, `.lint.log`, `.nobody.log`,
`.apply-nobody.log` under that prefix. Real systemd/Core/client/reboot acceptance
remains distinct.

## Opt-in real systemd fixture harness — 2026-10-23

`make test-systemd` explicitly enables a root-only integration script, separate
from `make check`. It maps the two Core unit names into two newly generated
`pnm-accept-<uuid>-*.service` names running sleep as existing nobody. Only these
owned units are enabled, started, restarted, stopped and removed. Private config,
applied-record and transaction fixtures do not replace actual Core paths.
Five scenarios cover activation, restart InvocationID/peer isolation, both
inactive/disabled and active/disabled compensation, and TERM recovery/lock release.
These are implemented scenarios, not executed acceptance results.

`make syntax security-scan shellcheck` plus explicit ShellCheck of the integration
script passed **exit 0** in `/var/tmp/pnm-systemd-review`; log:
`/var/tmp/pnm-systemd-review.lint-final.log`. Independent static safety review found
no blocking issue. Default unit checks remain the prior **31 suites / 327 passed**;
they were not rerun for this test-only increment.

The attempted fresh-copy `make test-systemd` never reached Bash: WSL returned
**exit 1**, `Wsl/Service/CreateInstance/CreateVm/HCS/0x800705aa` (insufficient
system resources). A separate read-only Bash/PID-1/systemd probe returned the
same failure. No fixture service was created, and no dynamic assertion ran.
Do not interpret this as a harness pass or a source regression. No WSL restart
or user-process termination was attempted. Retry `sudo make test-systemd` after
Debian WSL becomes available; inspect failures and retained private evidence
before repeating. Actual Core/TLS/account provisioning/reboot/client checks remain
open even if these stand-in service tests later pass.

Continuation after WSL recovered: Debian **13.5**, kernel
`5.15.167.4-microsoft-standard-WSL2`, systemd **257.13-1~deb13u1**, PID 1 systemd,
manager running. Frozen source copy `/var/tmp/pnm-systemd-continue` at `ee88135`:
`make test-systemd` **exit 0, 5 passed / 0 failed**; log
`/var/tmp/pnm-systemd-continue.systemd.log`. Actual service operations and
InvocationID observations passed for the two isolated nobody/sleep units.
Post-cleanup read-only checks found both exact units `LoadState=not-found`,
`ActiveState=inactive`, with no runtime unit files or enable symlinks remaining
(`pnm-accept-7dd05f94-fc0e-488e-ae42-fbfa9f891be2-{xray,hy2}.service`).
The earlier HCS failure is historical, not the current blocker. This adds real
systemd stand-in lifecycle evidence only; it does not establish actual Core
configuration loading, TLS, provisioning, reboot, listener or external traffic.

## Core compensation preserves disabled policy — 2026-10-23

Root cause: config and binary update/rollback compensation reused install health,
which requires enabled. A service originally active but disabled was restored
correctly yet marked recovery-required; binary recovery also stopped before
refreshing its prior confirmed applied InvocationID. Before the repair, preparation
tests reported **8 passed / 1 failed**, evidence tests **22 passed / 1 failed**, and
the extended actual systemd fixture **5 passed / 2 failed**.

The two callbacks now require successful state queries, active runtime and the
captured original enable policy. They do not enable a disabled service. Forward
health policy is unchanged. A further regression reproduced the matching-stdout
but failed-query edge (**10 passed / 1 failed**); explicit assignment/error checks
retain failure instead of accepting output alone. Unknown/inactive states and
changed enable policy also remain recovery errors. Independent source review
accepted both corrections.

Final frozen copy `/var/tmp/pnm-recovery-policy-final`: focused preparation
**11/11** and real systemd fixture **7/7** passed. The two added systemd cases run
actual config/update compensation callbacks and file transactions against the
isolated sleep services; only the update case tests refreshed applied binding.
They do not establish complete config-apply applied recovery or actual Core load.
`make check` **exit 0, 31 suites / 331 passed / 0 failed**, including syntax and
security scan. `make shellcheck` plus explicit integration-script ShellCheck
**exit 0**. Real nobody preparation **11/11** and evidence **23/23**, both **exit 0**.
The final two exact test units (`pnm-accept-e2dc3807-5ee3-41cf-8490-7302ad90b629-`
plus `xray.service` / `hy2.service`) are both not-found/inactive after cleanup;
no runtime unit file or enable-link remains. The earlier red-run private fixture
`/var/tmp/pnm-systemd.QI0Hf1Lk` is intentionally retained as mode-0700 evidence;
its two services were also removed. No real Core or production service changed.
Logs use `/var/tmp/pnm-recovery-policy-final` with `.preparation.log`, `.systemd.log`,
`.check.log`, `.lint.log`, `.preparation-nobody.log` and `.evidence-nobody.log`.
Red/initial green logs share `/var/tmp/pnm-recovery-policy`.

## Failed config apply retains confirmed evidence — 2026-10-23

Root cause: config compensation restored the old files and restarted the service,
but left its previously confirmed applied record bound to the old InvocationID.
The first regressions reproduced confirmed becoming changed and an external old
record edit not causing recovery-required: **25 passed / 2 failed**. Apply now
captures the existing evidence in operation-local fields before mutation and uses
the existing guarded recovery helper after successful service compensation.
Missing/stale/damaged records are preserved; external edits stop recovery rather
than being certified. The original operation error is retained.

Independent review found applied publication did not require metadata receipts in
config transactions. A commit failure after external chmod was reproduced
(**27 passed / 1 failed**). The two exact config transaction operations now use
the existing required metadata policy; no old digest constrains a new candidate.
Post-publication content or mode edits remain untouched with recovery-required.

Frozen copy `/var/tmp/pnm-config-applied-final`: `make check` **exit 0,
31 suites / 336 passed / 0 failed**, including syntax/security scan; actual nobody
evidence **28/28, exit 0**. New cases cover both cores, restart/health/record/commit
failures, unknown prior evidence, external edits and repeated successful apply.
Logs: `.check.log`, `.evidence-nobody.log` under that prefix.

The final integration-only refinement initializes standard runtime cleanup and
asserts registered staging paths are removed. Copy
`/var/tmp/pnm-config-applied-systemd-final`: `make test-systemd` **8/8, exit 0**;
`make syntax security-scan shellcheck` plus explicit integration ShellCheck
**exit 0**. Logs: `.log` and `.lint.log`. The added case runs complete apply
failure dispatch, real file compensation and actual InvocationID rebinding;
Core validation/identity/ownership remain fixture stubs. Both final random units
`pnm-accept-d05b6a7e-6971-4905-8c68-2663e983bbc0-{xray,hy2}.service` are
not-found/inactive after cleanup, without runtime files or enable links. The
initial eight-case run's units were separately checked removed as well.
This is not real Core configuration loading, TLS or external-client acceptance.

## Shared lifecycle compensation verifies actual state — 2026-10-23

Root cause: shared lifecycle restore accepted successful control/daemon-reload
commands without observing whether the captured service policy actually returned.
No-effect success could therefore append ROLLBACK_COMPLETE despite an enabled or
running service remaining different. Invalid baseline data also reached controls.
The new regressions reproduced **4 passed / 4 failed** before source changes.

The helper now validates the two baseline state domains before any I/O, retains
command failures, and requires successful final active/enabled queries matching
the baseline exactly. A failed query cannot be accepted solely for matching
stdout. Existing rollback failure handling retains recovery-required instead of
writing completion. Service control order and forward health policy are unchanged.

Frozen copy `/var/tmp/pnm-lifecycle-verify-final`: root lifecycle **8/8**, actual
nobody lifecycle **8/8**, existing isolated systemd **8/8**, all **exit 0**.
Syntax, security scan and ShellCheck, including explicit unit/integration script
checks, **exit 0**. Independent static review found no blocking issue. Both exact
test units `pnm-accept-3338fc20-7adb-4c4d-8e92-f73bf8e40848-{xray,hy2}.service`
are not-found/inactive after cleanup, without runtime files or enable links.
`make check` **exit 0, 31 suites / 341 passed / 0 failed**. Logs under that prefix:
`.check.log`, `.lifecycle.log`, `.lifecycle-nobody.log`, `.systemd.log`, `.lint.log`.
The injected ineffective controls are mocks; the real systemd suite verifies
compatibility with normal fixture recovery, not actual Core startup or reboot.

## Verification already reported (historical host evidence)

A prior user-provided `proxy-tokyo` read-only report stated that PNM 0.16.0-rc.1, both Core services/listeners, `pnm check`, and selected permissions were healthy, and that public client connections had succeeded. This report is historical and was not independently refreshed in this documentation task. It does not close the local failure-injection gaps above or prove the current installed source matches this HEAD.

## Immediate next steps

1. Confirm deployed PNM source identity for G-01 using read-only checks.
2. Accept the repaired A-03/A-04 paths in a disposable systemd VM, including explicit commands versus reboot/external restart; do not treat local results as completed Phase 3 acceptance.
3. Use a disposable Debian 13 systemd VM for real lifecycle/recovery acceptance. The local WSL environment already provides Bash, make, ShellCheck, Python, ripgrep, zip/unzip, flock and OpenSSL for source and mock tests.
4. Isolated WSL systemd lifecycle checks now pass 8/8, including failed apply dispatch/applied recovery and config/update callbacks with disabled baseline. Accept real service-account/TLS/Core/reboot/client behavior separately.
5. Reassess Phase 3 completion. Do not start Phase 4 automatically.

Remaining acceptance needs external prerequisites: an authorized deployed source
identity for G-01, a disposable target for actual Core/account/TLS loading and
reboot/fault injection, and external clients for dual-protocol traffic. Only Debian
WSL is currently available. The stand-in service results do not close these items;
Phase 3 remains incomplete and release work has not started.

## Boundaries

The user explicitly requested review and a local Git commit, reconfirmed by continuing the task on 2026-10-23. Production apply/update/restore, SSH/Tailscale/UFW/cloud firewall changes, version changes, push, tags and releases remain outside this task's authorization.
