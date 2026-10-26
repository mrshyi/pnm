# PNM Current Tasks

**Last reconciled:** 2026-10-26 (bounded publisher tmpfs ENOSPC checks added; independent Debian lifecycle/update/reboot and selected abrupt-VM recovery remain recorded; broader storage/platform and external acceptance are unverified)

**Current increment baseline:** branch `dev`, parent HEAD `b81600d`, VERSION `0.16.0-rc.1`.

**Environment recheck:** the earlier host EIO/EROFS/CreateInstance failure is no
longer reproduced: Debian root is writable, real `true`/`df` execute successfully
and an owned temporary file passes write/read/removal. The interrupted `771npvcc`
scope is now not-found and no fixture mounts remain. Its interrupted run remains
invalid evidence. The initial resume recheck measured approximately6.3GiB free
on C; capacity is rechecked before another retained guest and only one runs at
a time. Fresh `/var/tmp/pnm-resume-full.tqz8e8l2` passes syntax/security/
ShellCheck, eight offline guards and `make check` (31 suites/373 tests, exit0).
Startup-failure acceptance is completed below. No host remount, disk repair,
WSL restart or retained-fixture deletion was performed. New test storage was
mounted only in a private mount namespace and is now unmounted.

This page is a status snapshot, not a test report. Status must be refreshed from current source, test output, or host evidence before it is changed. Historical Phase 2 analysis is preserved in [PHASE2_GAP_ANALYSIS.md](PHASE2_GAP_ANALYSIS.md).

## Active phase

**Phase 3 — existing defect fixes and acceptance.** Phase 4 has not started. Local evidence includes real managed-account installation, per-Core lifecycle, trusted backup/restore, native fault/recovery slices, independent-kernel VM lifecycle/update/reboot and selected abrupt-VM pending-deployment recovery, plus earlier private real-Core/client checks. Remaining storage/commit positions, deployed-source identity, other platforms and external clients are unverified. The user has authorized consecutive local stages and commits; Debian WSL remains the host of the private KVM guest.

Current review artifacts (2026-10-22):

- [Implementation and goal assessment](IMPLEMENTATION_ASSESSMENT.md): current source findings, refreshed G-01–G-06 interpretation, and additional A-01–A-05 findings.
- [Deployment transaction design](DEPLOYMENT_TRANSACTION_DESIGN.md): accepted direction with a dated working-tree scope and remaining differences from the original proposal.
- [Acceptance plan](ACCEPTANCE_PLAN.md): layered evidence and fault-injection matrix; not an executed test report.

Source review confirms listener health gates, symmetric Core reporting, transactional publication/recovery, trusted-input policy and archive resource limits, unresolved-journal guards and HY2 TLS access checks. Actual guest testing additionally repaired renderer scope, managed health executable selection and Xray candidate format. Remaining acceptance includes the unexecuted storage/commit positions, upstream acquisition, other platforms, deployed identity and external clients. Detailed chronological increments below retain their original evidence boundaries; the table and final next steps summarize current work.

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
| G-02 — complete deployment rollback | Native fault, independent VM lifecycle/reboot and selected abrupt recovery PASS / broader storage matrix open | Native startup/post-health/deadline/TERM compensate and retry. Publisher EROFS compensates; unknown marker observation forbids blind rollback. Actual QEMU post-rename SIGKILL preserves uncertainty across a new kernel and blocks4 fresh commands even with torn progress rows. | Remaining marker/storage positions and external acceptance; do not infer production readiness. |
| G-03 — Core update transaction | Native fault and independent VM distinct-version/update/reboot slices PASS / broader matrix open | Both official Cores retain paired current/previous state and peer evidence through actual checksum refusal/update/rollback/swap and subsequent VM reboot. Native startup/publication/interruption faults retain recovery or compensate. Curl uses a private HTTPS transport fixture. | Remaining commit/storage positions and upstream acquisition stay separate. |
| G-04 — backup/restore safety | Native restore fault slices and independent VM trusted restore/reboot PASS / broader matrix open | Actual trusted round trip, partial-write EROFS, TERM/SIGKILL and failed compensation verify bytes/metadata/NSS/applied recovery or retained uncertainty with protected-command refusal. Independent VM mainflow includes trusted restore; the subsequent reboot preserves persisted resources and withholds stale bindings. | Remaining abrupt/storage/client boundaries; do not equate trusted archive validation with arbitrary executable safety. |
| G-05 — dependency preflight | Actual Debian guest19-tool refusal and repeat refusal PASS | A private PATH individually hides all19 declared preflight prerequisites. Actual JSON install returns2 with the matching FAIL class and preserves authority/NSS fingerprints, PNM inventory/transactions and absent Core/service/account state; normal lifecycle then passes. | Upstream acquisition failures, other distributions and remaining fault positions stay separate. |
| G-06 — HY2 TLS permissions | Native TLS/reuse/account faults and independent VM positive lifecycle PASS | Actual service TLS access and permission gates pass; preexisting identities are preserved. Real creation refusal compensates prior identities; deletion refusal retains precise unfinished ownership. Positive managed TLS/Core loading also passes on the independent kernel. | Other NSS/platform/fault behavior and external clients remain separate; do not infer external reachability. |

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

## Core state-directory resources participate in recovery — 2026-10-23

Root cause: standalone applied publication normalized state-directory permissions
without directory receipts; update also created/normalized its previous-state
directory before transaction begin. Failed operations could leave new directories
or changed permissions and fail to report foreign directory contents/metadata.
Five regressions failed before correction (**28 passed / 5 failed**).

Publication now uses the existing directory preparation facility for these paths.
Update preparation occurs after begin and rollback registration; its failures keep
the original error. Restart/config/update callbacks restore files, service and
applied state first, then reverse directory changes. New empty paths are removed;
foreign contents or directory drift stop recovery instead of being overwritten.
The Core focused suite passed **33/33** and apply/CLI **14/14** before final review.

Shared-caller review found the legacy install-state branch also needed directory
compensation. Its two regressions reproduced **33 passed / 2 failed**. It now
registers directory recovery before file recovery so reverse execution restores
files first. The primary deployment callback already performs that ordering.
Independent static review accepted the Core and legacy changes.

The first full run in `/var/tmp/pnm-core-directories-final` was interrupted by
server restart/Hangup and is not passing evidence. Final source is frozen in
`/var/tmp/pnm-core-directories-final-v2`: `make check` **exit 0, 31 suites /
348 passed / 0 failed**; actual nobody evidence **35/35, exit 0**. Existing
isolated systemd **8/8, exit 0** and syntax,
security scan/ShellCheck (including explicit evidence/integration scripts) pass.
The evidence test's SC1090 annotation documents its trusted checkout function
aliases/sources; production ShellCheck diagnostics remain enabled.
Final logs use `.check.log`, `.systemd.log`, `.lint.log`, `.evidence-nobody.log`
under that prefix; red/initial green logs share `/var/tmp/pnm-core-directories`.
Both final exact units
`pnm-accept-f91670d0-1196-4604-a0b5-5c960a9fa1ae-{xray,hy2}.service` are
not-found/inactive after cleanup, with no runtime files or enable links remaining.
Directory fault injection uses real files and metadata with mocked services/NSS;
the systemd suite uses separate nobody/sleep units, not actual Core/TLS/reboot/L3.

## Runtime config publication protects metadata — 2026-10-23

Root cause: config apply used optional file metadata and a separate ownership
normalizer. External chmod after publication could be overwritten on rollback;
drift before normalization could also be accepted as success. Correctly scoped
red regressions reported **35 passed / 2 failed** (`/var/tmp/pnm-config-metadata.red-v2.log`):
0660 became original 0644, and pre-owner drift returned success.

Apply now reuses the existing guarded Core writer: required metadata at publish,
receipt verification before chown, then fixed expected UID/GID/mode enrollment.
The redundant private normalizer is removed. Independent review reproduced a
shared-helper error boundary (**37 passed / 1 failed**, `.review-red.log`): failed
chown with a different intended group returned 70 instead of original 77. The
helper now preserves the first ownership error without adopting a mismatched
metadata sample. A no-effect ownership failure can use its intact old receipt;
additional drift remains untouched with recovery-required.

Tests opt into fixed service-name mappings to the runner's actual UID/primary GID;
numeric snapshot ownership is passed through to real chown. Both cores exercise
the real publisher, transaction and metadata guards without account creation.
The different-target-group fault is injected without attempting host ownership
changes. Existing CLI mock tests continue to map transaction I/O explicitly.

Final copy `/var/tmp/pnm-config-metadata-final`: evidence suite **38/38** in the
default run and actual nobody **38/38**, focused restore **9/9**, isolated systemd
**8/8**, all **exit 0**, plus syntax/security scan/ShellCheck **exit 0**.
`make check` **exit 0, 31 suites / 351 passed / 0 failed**. Logs under that prefix:
`.check.log`, `.evidence-nobody.log`,
`.restore-focused.log`, `.systemd.log`, `.lint.log`. Both final units
`pnm-accept-8a1be1cb-4dde-4ff8-84a0-cac8edc77598-{xray,hy2}.service` are
not-found/inactive, with no runtime files or enable links after cleanup.
These results do not prove actual xray/hysteria account provisioning, Core/TLS
loading, reboot or external traffic.

## Real Core WSL acceptance preparation — 2026-10-23

The user reiterated continuous stages/commits. WSL systemd remains running and
`unshare --net true` passes (exit 0), enabling a narrower real-Core test design
without host network exposure. Test-only pins are in
`tests/integration/real_core_versions.json`: official release metadata supplies
fixed SHA-256/size for Xray v26.10.21 and Hysteria v2.13.0. Manifest JSON validates.
These are integration-test assets, not managed versions.conf or production approval.
The design/sequence is [real Core WSL plan](superpowers/plans/2026-10-23-real-core-wsl.md).

The official asset API transfers completed; exact sizes and SHA-256 match the pins.
The opt-in `make test-real-cores` now passes **5/5** in the frozen Linux source copy
`/var/tmp/pnm-realcore-positive-v6`, with sanitized `.run.log` and `.lint.log` beside
it. Syntax/security/ShellCheck, explicit fixture ShellCheck and Python compilation
also pass. Production renderers supply the server configurations; actual Xray
config validation, both real unprivileged Core startups and both local proxy
client transfers pass. All seven owned transient units and the success fixture
were cleaned. No account, production service or host network was changed.

The final probe uses a fixture-only address on lo inside a verified non-host
namespace containing only lo. Earlier loopback attempts were blocked by the pinned
Xray's default private-destination policy, confirmed in isolated diagnostic logs
and official source; the final test does not weaken production configuration.
HY2's initial positive test uses CA verification. The follow-up below verifies and
repairs share-link fingerprint compatibility. Cause-qualified authentication/TLS rejection,
actual account provisioning, reboot, external clients and deployed identity remain
open; this positive stage does not close Phase 3.

## HY2 share-link certificate fingerprint repair — 2026-10-23

Root cause: `node links` copied the internal SPKI/base64 hash into `pinSHA256`,
but the official client hashes the complete leaf certificate DER and compares hex.
In `/var/tmp/pnm-realcore-pin-red`, both normal protocol/CA controls passed, then
the PNM URI pin was rejected with the specific certificate-fingerprint mismatch;
all eight owned units were cleaned. New focused TLS/link regressions also failed
before the repair (`pnm-pin-unit-red` logs).

The small repair computes a validated lowercase 64-hex leaf-certificate hash only
for selfsigned-pin links. Existing persisted schema/SPKI values and credentials
remain unchanged. Missing/invalid certificates or tool/output failures suppress
only HY2 while retaining a ready Xray link. Ordinary diagnostics contain no link,
password or private key. TLS focused tests pass 5/5 and node tests pass 30/30.

Real evidence: `/var/tmp/pnm-pin-real-final.real.log`, **6/6**, including the complete
PNM-generated HY2 URI imported directly by the official client and actual fixture
transfer after the CA-positive control. The URI fixture maps service readiness,
so this verifies URI/client compatibility, not full PNM readiness. All eight owned
units and success fixtures were cleaned. Production source/default tests match
the frozen `pnm-pin-final` copy; final opt-in file creation also uses private umask
and explicitly restores required directory traversal for nobody.
Syntax/security/ShellCheck, fixture ShellCheck and Python compilation pass.
Full default `make check` exits 0, **31 suites / 354 tests passed**, with output
in `/var/tmp/pnm-pin-final.full.log`. The first full attempt exposed an old SPKI
wire expectation and an overly private source-copy parent; the final SNI regression
independently checks DER and unchanged persisted Secret, and the public source copy
allows real non-root traversal. Private fixture/evidence parents remain protected.
Rejection cases and external/reboot/account acceptance remain open.

## Real Core refusal and recovery evidence — 2026-10-23

The frozen `/var/tmp/pnm-rejection-final` source passes opt-in
`make test-real-cores`: **10/10**, with the sanitized result in
`/var/tmp/pnm-rejection-final.real.log`. Syntax/security/ShellCheck and Python
compilation exit 0. The preceding offline guard passes all four safety-failure
subcases; it first failed against the former broad exception catch, then passed
after only an observed post-exec candidate exit became tolerable. Manager, UID,
privilege and namespace assertion failures cannot become refusal success.

Real Xray validates both negative client configs before execution. A wrong VLESS
UUID produces its exact server refusal; a wrong REALITY short ID produces the
explicit unverified-connection cause with process-local fixture CA trust. Each
candidate is retired through the same guarded ownership/stop path as final cleanup,
then the correct client transfers again. The single-connection TLS fixture had
blocked later handshakes while the invalid client's fallback spider was alive;
the final result proves refusal and recovery after candidate exit, not concurrent
DoS resistance. No production configuration or host trust is changed.

HY2 rejects a wrong certificate pin with the exact mismatch cause, and a wrong
password with a typed authentication HTTP 502 plus the configured masquerade's
reverse-proxy error/fixture target evidence. The official server routes failed auth
to masquerade; this isolated proxy target is unreachable, so 502 is specific to
this fixture rather than a universal auth status. Both rejected clients exit and
the valid full PNM URI transfers again after each. All **12 owned units** are
not-found and the successful runtime fixture is removed.

This stage changes only opt-in tests/Makefile/docs. The production/default-test
baseline remains the prior **31 suites / 354 passing tests**; that full suite was
not redundantly rerun for these isolated test additions. Actual managed accounts,
integrated deployment/update/restore/recovery, reboot and external clients remain
separate acceptance work. No disposable target or external client is available.

## Native container acceptance prerequisites — 2026-10-23

The user reiterated automatic consecutive stages. A further bounded local path
is being evaluated: private native nspawn/rootfs testing, without host installation
or account/service changes. Mount/PID/user/cgroup namespace probes exit 0. WSL has
a hybrid cgroup layout: read-only parent tmpfs, writable legacy/unified children.
Those observations do not prove nested systemd can boot or safely delegate cgroups.

No container/bootstrap tool was installed. Exact Debian systemd-container
257.13-1~deb13u1 and debootstrap 1.0.141 packages were acquired through an
officially listed HTTPS mirror after direct CDN/Windows failures. Sizes and hashes
match the fixed APT metadata before private extraction under
`/var/tmp/pnm-container-tools-20261023/tools`; both version commands exit 0.
No host packages, accounts or services were installed/changed. The next bounded
stage is isolation/boot preflight in a disposable rootfs; PNM writes are forbidden
until the guest boundary is verified. See the
[container main-flow plan](superpowers/plans/2026-10-23-container-mainflow.md).
The native minimal shell and a separately prepared fresh rootfs now pass strict
namespace/UID/network/cgroup gates. All five namespaces differ; UID 0 maps to a
nonzero host range; only lo exists; writable systemd/unified mounts are rooted in
the owned scope/payload, with outside controllers not writable. Native idmapped
mounts keep backing ownership separate from the effective guest identity.

Debian foreign bootstrap passes Release signature verification and exits 0.
Package configuration runs only inside the verified private guest and exits 0.
Host account databases and dpkg status remain unchanged; scopes are not-found and
no fixture mounts remain after exit. Rootfs/evidence parent:
`/var/tmp/pnm-debian-guest.4w7y455l`; exact logs and additional privately verified
wget/xz tool pins are in the plan. No host package or account was changed.
Full guest systemd boot now passes. `boot-result.json` in that private parent
records manager `running`, all identity guards, live host-side cgroup boundary,
nspawn exit 0, unchanged host databases and complete scope/mount cleanup. Only
systemd/unified are writable inside the booted guest, and both host-visible mount
roots remain the owned scope/payload; the parent tmpfs is read-only after boot.
The WSL detector's outer-kernel result is paired with the exact native nspawn
marker and all namespace/UID/root/PID1/machine-ID guards. Private boot scripts
compile and were reviewed before execution. Earlier failed assumptions were not
counted as success; details and source reference are in the plan.

Subsequent actual PNM installation evidence is recorded below. A private container
is available locally; VM/kernel reboot and independent external clients remain
unavailable and cannot be inferred from its boot or installation result.

## Actual installation and renderer scope repair — 2026-10-24

Actual offline-cache CLI installation first reproduced circular Bash namerefs:
the health gate's local reality/hysteria arrays collide with renderer reference
names. Only the two Core and two Secret renderer reference names are now private
to their functions. Rendered bytes, validation and transaction gates are preserved.
The five new regression cases first fail against original source; corrected source
passes 13/13 focused tests and `make check` (31 suites / 359 tests, exit 0), plus
syntax/security/ShellCheck. The failed original guest has no remaining managed
accounts/binaries/configs/units, retains PNM_CONFIGURED=no and records completed
rollback; those are persisted observations after shutdown, not live recovery proof.

Fresh `/var/tmp/pnm-install-guest.zh1menk9` passes **8/8** actual CLI checks:
init/validate, nonmutating preview, both-Core installation/commit, distinct actual
NSS accounts and process UIDs, bounded privileges, configuration/invocation applied
bindings, production link readiness and certificate DER pin, and Core health.
The parent records approved live cgroup boundaries, nspawn exit 0, unchanged host
account/package databases, not-found scope and no remaining fixture mounts.
No production functions are overridden; pinned bytes use PNM's verified asset
cache. Raw output is protected because it contains credentials and share links.
The source hashes, private scripts and reports are retained in the fixture; a
reusable opt-in repository entry is still pending. No time-sync check was collected.

The preceding fixed-source guest `gswqfozh` starts Xray but fails health with a
minimal PATH lacking `/usr/local/bin`; the health function invokes bare `xray`
despite having an absolute managed binary path. A fresh guest with normal root
PATH alone passes. Next repair that command resolution with a focused regression,
then repeat minimal-PATH installation before repeat-install and lifecycle cases.
See the [renderer repair plan](superpowers/plans/2026-10-24-renderer-scope.md).
These are local private-guest installation checks, not integrated update/restore,
network acquisition, traffic, reboot, deployed-source or external acceptance.

## Managed executable health repair — 2026-10-24

The Xray health configuration test now invokes `PNM_XRAY_BIN`, matching version
discovery and the configured managed Core. A missing PATH entry cannot cause a
false config failure, and a competing PATH executable cannot substitute for the
managed binary. Arguments, error propagation and strict health gates are unchanged.
The two regressions fail before the fix (13 pass / 2 fail), then pass (15/15).
Independent review found no blocking issue. Frozen source
`/var/tmp/pnm-health-green.hni1ico0` passes syntax/security/ShellCheck and the full
default suite: **31 suites / 361 tests, exit 0**.

Fresh `/var/tmp/pnm-install-guest.i84_5clp/boot-result.json` records **8/8** actual
installation/account/process/applied/link/health checks with the originally failing
minimal PATH. Host boundary approval, nspawn exit 0, unchanged host databases,
not-found scope and no remaining fixture mounts pass. Offline-cache, time-sync,
traffic and external/reboot evidence boundaries remain as above. Next exercise
repeat-install refusal, per-Core restart/apply independence and trusted backup/
restore using actual NSS/systemd in a fresh clone.

## Xray apply candidate format — 2026-10-24

Actual changed-config apply uncovered an extensionless temporary `config` file:
Xray v26.10.21's auto loader cannot select its format. In `pos73g_w`, the same
candidate bytes return 23 without a suffix (Failed to get format) and 0 as JSON.
Only the Xray branch now names its staged candidate `config.json`; HY2 staging,
validation and transaction/recovery behavior are unchanged. The focused format
regression fails before repair (14 pass / 1 fail), then all 15 pass. Frozen
`/var/tmp/pnm-candidate-green.9ryuw8sq` passes syntax/security/ShellCheck and
`make check`: **31 suites / 362 tests, exit 0**. Independent review found no
blocking issue.

Actual guest `fewv_gnd` passes 13 checks through repeat-install refusal, both
independent restarts and both changed-config apply paths. Each operation checks
actual processes/invocations, resource bytes/metadata, applied binding and peer
preservation. Xray changes only XRAY_TARGET because HY2 masquerade shares the
SNI field. The later restore does not complete within the test deadlines and
records RECOVERY_REQUIRED with original rc143. No complete lifecycle or restore
pass is claimed. The test reports failure/NoGuestReport; final nspawn exit is 0,
host databases are unchanged, scope is not-found and no fixture mount remains.

The reusable opt-in guest harness remains an uncommitted next increment. Its
offline write/opt-in guards pass 4/4, including a reproduced/fixed FIFO stall.
Separate real parent TERM (`jd22oheh`) and HUP (`gcmpr795`) probes each fail the
interrupted run and retire their owned guest/scope without host database change
or fixture mounts. Next diagnose restore and bound CLI descendant cleanup on
timeout before committing the harness. No production apply or release occurred.

## Reusable actual guest main flow — 2026-10-24

The restore interruption above was caused by the inherited boot-only test unit's
**80-second** RuntimeMaxSec, not an established production restore hang. Only
the fresh clone's dedicated test unit now has 390 seconds; guest cases retain a
300-second cap and the independent host deadline remains 420. No production
restore change was needed. CLI calls own separate sessions and retire their
command group on timeout, preventing inherited PIPE fds from extending the wait.

The repository's explicit `make test-guest-mainflow` now exits 0 in fresh guest
`/var/tmp/pnm-install-guest._slfzj2u`: **14/14** installation/account/process,
repeat-refusal, per-Core restart/apply/peer preservation and trusted backup/restore
checks pass. Restoration verifies all archived resource bytes and metadata,
both new actual invocations, refreshed applied bindings, links and final health.
The final host report verifies live guest cgroup boundaries, normal nspawn exit 0,
unchanged host account/package databases, not-found scope and no fixture mounts.
Copied-source hashes and secret-bearing raw evidence remain in its private parent.

The five offline safety guards pass; all four Python files compile. FIFO failure
was reproduced before adding nonblocking open; real helper tests also cover links
and the PIPE-holding descendant. Independent review found no blocking issue.
The unchanged default production suite remains **31/362** from the preceding
successful run; it was not redundantly rerun for this separate opt-in harness.
Commands, prerequisites, deadlines and evidence boundaries are documented in
[the guest test guide](../tests/integration/GUEST_MAINFLOW.md). No acquisition,
time-sync check, new-version update, injected failure recovery, kernel reboot,
deployed-source identity or external traffic is established by the 14-case result.

## Actual deployment deadline failure and retry — 2026-10-24

The existing opt-in harness now offers `PNM_GUEST_SCENARIO=deployment-failure`.
Fresh `/var/tmp/pnm-install-guest.vh5luh5b` exits 0: **16/16** checks pass, including
missing-openssl refusal and late deployment compensation, followed by the original
14 installation/lifecycle/restore checks after retry. No production code changed.
Only the private guest PATH hides a tool; its actual executable/package remains.
The refusal cause, unchanged desired/NSS bytes and no new transaction are checked.

A guest-owned Xray startup delay crosses the existing 30-second commit window.
The test requires real dual-Core post-health completion, APPLY_DONE/HEALTH_CHECK
before APPLY_FAILED rc77, metadata window30, failure timestamp beyond its deadline,
and no durable commit/pointer. This qualifies the cause beyond a generic rc77.
Live rollback verifies absent Core processes/listeners/units/accounts/groups and
applied promotion, original node/version/NSS bytes and directory identity/metadata,
unchanged preexisting drop-in and completed rollback without RECOVERY_REQUIRED.
Only that exact owned delay is removed before the successful retry.

Final host evidence confirms nspawn exit0, no interruption, unchanged account/
package databases, not-found scope and no fixture mounts. Protected raw reports
and copied-source hashes remain in the fixture. This closes one real late-failure
case, not all interruption/concurrency/failure positions, a new-version update,
kernel reboot or external acceptance. The default suite remains the prior31/362.

## CLI update asset dependency repair — 2026-10-24

Actual update in guest `ut1_l8m2` exposed a missing CLI source dependency:
`pnm_assets_load` exists in lib/assets.sh, but bin/pnm loaded only its adapter.
Update returned78 before any request, which the cause-qualified checksum test
correctly rejected. The entry now sources the existing library after its adapter;
the removed broad assets command remains unavailable and no public route changes.
Installer packaging already copies the complete lib directory.

The actual CLI regression checks both Core names' unapproved-version refusal,
correct reason and absence of a write transaction in private state/lock paths.
It fails before repair (10 pass/1 fail), then passes11/11. Independent review
found no blocking issue. Frozen `/var/tmp/pnm-cli-assets-green.fqpxumap` passes
syntax/security/ShellCheck and `make check`: **31 suites/363 tests, exit0**.

Fresh guest `2t13z9ae` passes the distinct-version scenario **22/22** after this
repair, including the original14 on the older official pair and each Core's
checksum refusal, update, rollback and swap forward. Private HTTPS substitutes
asset transport only; actual curl/TLS/checksum/version/staging/publication/health
and applied logic run. Host databases remain unchanged, nspawn exits0, scope is
not-found and no fixture mounts remain. The separate uncommitted test increment
retains source hashes and protected evidence; upstream network/PKI, broader fault
recovery, reboot and external clients remain unaccepted.

## Actual distinct-version Core update/rollback — 2026-10-24

The explicit `core-update` scenario in the existing guest entry passes **22/22**
in `/var/tmp/pnm-install-guest.2t13z9ae`, Make exit0. It installs official Xray
v26.9.30 and HY2 v2.12.3, runs the original14 lifecycle cases, then each Core's
wrong-checksum refusal, update to v26.10.21/v2.13.0, rollback and swap forward.
Both binary bytes and actual version/invocation change; confirmed applied/link
state survives. Peer comparisons include runtime resources and previous binary/
metadata. A checksum rejection must fetch the frozen asset yet begin no write
transaction, preventing a generic78 from masquerading as the intended refusal.

Official GitHub release API sizes/digests are frozen in
`tests/integration/previous_core_versions.json`. WSL download/resume timed out;
Windows curl acquired both assets, verified there and again in the Linux private
cache. Partial files remain unexecuted/unpublished. A private lo HTTPS CONNECT
fixture serves only checked current bytes to real curl, using CA/proxy settings
only in CLI env. Real TLS, hash, version, staging, publication, service and applied
logic execute; upstream DNS/PKI/download is explicitly outside this fixture result.
No production function is replaced or managed production pin changed.

Seven offline guards pass, including bounded headers, incomplete CONNECT/TLS,
wrong target/path and CA-verified positive transport in an isolated network NS.
Own sockets, total connection lifetime/count and thread retirement are bounded.
Five Python implementation files compile, the existing real-Core refusal guard
and syntax/security/ShellCheck pass. Independent review found no blocking issue.
The preceding full default run remains **31/363**, without a redundant rerun.
Final host evidence: nspawn0, no interruption, host databases unchanged, scope
not-found and no fixture mounts. Source hashes and private raw reports remain.
Broader fault recovery, custom-port integration, concurrency, reboot and external
acceptance remain open. Next exercise T-04's existing configurable ports and
review the remaining hard-coded health assumptions against actual behavior.

## Configured-port health and recovered listener repair — 2026-10-24

Existing init flags, rendering, preflight and URIs accept persisted custom ports,
but check still enforced443/8443 and probed those defaults. The recovered-applied
helper also probed defaults. Forward health now uses only validated persisted
ports, reporting UNKNOWN without fallback when unavailable. Compensation first
verifies the recovered config hash, then parses its actual port through existing
JSON/YAML helpers; Xray must be TCP. Desired/default ports cannot substitute for
the recovered generation. Parser/port/transport failures do not probe or refresh
applied evidence. Default ports and output remain compatible.

Initial focused red: check15 pass/3 fail and deployment15 pass/2 fail. A later
non-TCP negative fails before its extra guard. Final frozen
`/var/tmp/pnm-port-health-green.erfo3wso` passes check18/18, deployment19/19,
syntax/security/ShellCheck and `make check`: **31 suites/370 tests, exit0**.
Negative cases verify malformed/invalid ports and non-TCP cannot promote applied
or borrow default listeners. Independent source review found no blocking issue.

Native red guest9s3b0ftl installs custom ports yet check rejects configuration.
Final fresh `/var/tmp/pnm-install-guest.e59hkntn` passes **16/16**: actual10443/
18443 occupancy refuses before managed writes, unrelated443/8443 sockets survive,
and actual install/listeners/URI/lifecycle/restore follow selected ports. Parent
evidence records nspawn0, no interruption, unchanged host databases, not-found
scope and no fixture mounts. The helper recovery cases are focused filesystem/
observations tests; this native scenario does not itself run recovery against a
preexisting active custom-port baseline. The reusable `configured-ports` scenario
is packaged separately in the existing Make entry; default scenarios retain443/
8443 and all cases now verify actual listener/URI port agreement. Broader failure/
concurrency/reboot/external acceptance remains open.

## Actual external restart evidence and held-lock contention — 2026-10-24

The existing opt-in guest entry's `runtime-evidence` scenario passes **19/19**
in `/var/tmp/pnm-install-guest.j61dn9c1`, Make exit0. After the original14, both
actual services are restarted outside PNM. Their invocation changes while config/
applied bytes stay fixed; show returns78 with unconfirmed target and ready peer.
Links return0 with only the peer URI. PNM restart still cannot promote stale
evidence or alter runtime resources; fully validated apply rebuilds confirmation
and both links become ready, with the peer unchanged.

A real independent flock FD holds the global lock; a second FD confirms kernel
contention. The actual writer and protected reader return73 with empty stdout,
unchanged Core/process/applied state and no new transaction. After release the
same commands succeed, confirming the cause and absence of a leaked lock. This
tests held-lock collision, not every concurrent install/apply/read interleaving.

Two changed Python files compile and seven offline guards pass. Host databases
remain unchanged, nspawn exits0, scope is not-found and no fixture mounts remain.
No production code changes; default source evidence remains31/370 without a
redundant rerun. Broader fault recovery and independent VM/kernel reboot remain
open; external service restart does not stand in for reboot acceptance.

## Restore compensation after an actual failed unit start — 2026-10-24

Actual HY2 `ExecStartPre` rejection reproduced an early recovery failure in fresh
guests `wiqao337` and `jwemkkpp`. `systemctl stop` succeeds but leaves HY2 in
`failed`, MainPID0; Xray has already been stopped/disabled. The restore callback
required `inactive`, so it returned70 before restoring the twelve published files
and correctly retained RECOVERY_REQUIRED. The probe observed only the rejected
start, proving compensation never reached the second start.

The callback now resets only that stopped failed unit, explicitly re-queries and
requires `inactive`, then follows existing file/service/applied/directory recovery.
Reset failure, query failure or a non-inactive result still retains uncertainty.
Focused regressions first passed11/failed1, then passed **12/12**, including reset
failure and successful-reset-without-state-change refusal. Syntax, security scan
and ShellCheck pass in `/var/tmp/pnm-restore-start-green.3tylai3_`.

Fresh `/var/tmp/pnm-install-guest.lood523m` passes **16/16**, Make exit0: actual
restore startup failure recovers both original resource generations, numeric
metadata, identities, service policy and confirmed applied bindings, followed by
a trusted successful retry. nspawn0, host databases unchanged, scope not-found,
no fixture mounts. Independent read-only review found no blocking issue.

The concurrent new full run exited **2**, and is **not green**: failures include `flock: failed to
execute true: Input/output error`. Direct host reads of `/usr/bin/true` and
`/usr/bin/df` also return EIO. Windows C free-space probes were inconsistent
(one reported0; Linux `/mnt/c` later reported689041408 available bytes), so this
does not establish a disk/filesystem root cause. No system binary, host service,
WSL instance or disk is repaired/restarted by this task. Preserve the failed log
and restore stable WSL execution before relying on another full acceptance run.
The earlier clean **31 suites/370 tests** is historical, not a pass for this fix.

Reusable startup-fault scenarios are being packaged separately. Their test-only
limits are now600 seconds for cases,690 for the cloned unit and720 for the host;
the former300-second cases limit expired near the final link check of the larger
update-failure scenario. Each CLI and owned socket/thread still has its own bound.

## Startup readiness and actual update/rollback fault compensation — 2026-10-24

Natural runs `k55gy846` and `viaq9o0_` failed at an Xray post-health check after
otherwise successful update/rollback starts; both compensated completely. Their
generic error messages alone do not establish which health condition failed.
The deterministic `startup-readiness` RED guest `dpg_alxd` separately proves a
Type=simple readiness window: real Xray's ExecStart is delayed3 seconds, the
production gate returns78 after0.463 seconds with `Xray TCP listener is absent`,
then returns0 for the same InvocationID without another restart or resource edit.
Permissions/configuration consistency remain OK during the failed observation.

The existing listener adapter now accepts a bounded optional probe count, default1.
Startup health and hash-verified recovered-generation checks request26 samples
with at most25 x0.2-second waits. Startup then independently repeats its complete
health policy. Ordinary diagnostic/preflight probes stay immediate. Tool errors
return2/UNKNOWN, never1/free: independent review caught an initial loop that lost
this distinction. Two tests reproduced that regression before PIPESTATUS handling
was repaired. Final focused listener/check suite passes **25/25**, renderer13/13.

Fresh `mkmrfpdx` passes startup-readiness **16/16**, both real Core services under
their original user/sandbox policies. Fresh `jkja5d_v` passes actual update-failure
**26/26**: each Core's update and rollback start is rejected once, compensation
restores resources/previous metadata/service/applied evidence, peer stays fixed,
and normal distinct-version update/rollback/swap subsequently succeeds. These
native runs exercise the waiting behavior before the final tool-error-only
PIPESTATUS correction; positive ss results follow the same successful path.
Both nspawn exits0, host databases stay unchanged, scopes are not-found and no
fixture mounts remain. Raw CLI/journal output stays private.

Eight offline guards pass. The command-group timeout fixture now waits for its
own descendant PID marker before starting the short test timeout; concurrent
process startup previously made that test race. Unexpected CLI failures retain
a private bounded service-journal excerpt without replacing the original error.
The first expanded full run exposed a renderer fixture lacking its isolated
listener observer; that fixture is repaired and its13 tests pass. Final frozen
source `/var/tmp/pnm-startup-checked.gdpgk2ro` passes syntax/security/ShellCheck,
eight guards and `make check`: **31 suites/380 tests, exit0**. Seven Python files
compile. Independent review's tool-error finding is repaired and re-reviewed;
no further blocking issue remains.
Persistent recovery failure, late publication/commit faults, kernel reboot,
deployed source identity and external clients remain separate acceptance work.

## Initiating error retained during failed Core recovery — 2026-10-24

The shared update/rollback abort helper reported the original failure to stderr
but did not copy it to the existing transaction failure field before rollback.
When compensation failed, the real journal incorrectly recorded `original_rc=0`.
The existing dual-Core update/rollback matrix now checks the initiating78 and
recovery70 independently. Frozen RED `pnm-original-error-red.cvuafqdv` passes37/
fails1 and records `rollback_rc=70 original_rc=0`. The one-line shared-entry
assignment preserves the original return code and all existing recovery gates.
Frozen GREEN `pnm-original-error-green.2rh7_zju` passes static checks, the full
focused suite38/38 and default **31 suites/380 tests, exit0**. Independent read-only
review found no blocking issue. This focused matrix uses actual files/journals
with simulated services; native persistent recovery failure remains separate.

At the earlier disk checkpoint, the next native slice needed reusable space. Exact stopped roots
`mkmrfpdx/rootfs` and `jkja5d_v/rootfs` have private, hash-verified retained-evidence
bundles beside them, including logs, trusted backup, actual source/configuration
and small transaction receipts. Their cleanup-review.json files identify device/
inode, file count and logical size. The cleanup proposal was not used;
neither rootfs has been deleted. Removing them would make approximately1.45GiB
of guest filesystem data reusable; Windows VHD/C free space need not immediately
increase. Baseline, asset caches, failed fixtures and external acceptance stay
outside that proposed cleanup.

The implemented reject-twice cases now pass actual native acceptance:
`core-recovery-failure-xray`24/24 in `2xnywz__`, HY224/24 in `btg1m7ba` and
`restore-recovery-failure`16/16 in `fzm8pblq`. The latter two are retained in the
verified private-storage archive below. Both Core rollback failures restore
binary/previous/applied bytes yet leave the target failed with MainPID0 and peer
unchanged. Restore recovers ordinary resources and Xray binding while HY2's
compensation fails; no complete service recovery is claimed. Original1/recovery70
and RECOVERY_REQUIRED are retained. Removing the owned fault does not clear the
gate: actual apply/links/show/check return70 with empty stdout and unchanged
PNM/NSS and managed Core inode/mtime. `expected_recovery_required=true` explicitly
distinguishes the accepted failure state from a healthy service.

Each native case records unchanged host databases, nspawn0, not-found scope and
no guest mounts. Nine offline guards pass, including all recovery host-entry
refusals and the optional canonical/root0700 POSIX work directory; eight Python
files compile. Independent source review accepts the test slice. Product source
remains the final31-suite/380-test baseline without a redundant full rerun.

C fell to1570078720 free bytes after Xray; an anonymous D-backed ext4 volume in
a private mount namespace completed the other cases without deleting old data.
The first export timed out and is not final evidence. The buffered rerun retains
the full raw image in an808675120-byte encrypted archive; trusted producer-cipher
hash and full decrypted raw-image hash both verify. Control/key/audit data are
under root0700 `/var/tmp/pnm-test-volume.cky4eb0a`, key0600; retain this with the
ignored D archive described in the test-storage plan. The storage loop is
detached and cleanup errors are empty. Its executed success path and separately
reviewed/error-injected fixed worker are explicitly distinguished in that plan.

## Verification already reported (historical host evidence)

A prior user-provided `proxy-tokyo` read-only report stated that PNM 0.16.0-rc.1, both Core services/listeners, `pnm check`, and selected permissions were healthy, and that public client connections had succeeded. This report is historical and was not independently refreshed in this documentation task. It does not close the local failure-injection gaps above or prove the current installed source matches this HEAD.

## Native managed-account TLS access failures — 2026-10-24

Committed recovery-required coverage is `3ba94e3`. New `tls-access` reuses the
14-case main flow, then proves wrong key ownership and a non-traversable parent
fail actual hysteria-account reads, JSON health and the startup gate. Diagnostics
leave Core/resource/receipt/NSS state unchanged and disclose no credentials.
Finally restores fixture permissions; an actual HY2 restart refreshes applied
binding and both links/health pass with Xray unchanged. Fresh `qktokjdj` passes
17/17. Native/Make exit0, unchanged host databases, scope not-found, no mounts.
Control/key/evidence: `/var/tmp/pnm-tls-green-volume.d1xlzf9b`; full encrypted
image in the existing ignored D pool passes cipher/raw readback verification,
loop detached, no cleanup errors. The first failed fixture is retained separately;
its test expected WARN=1 instead of the established FAIL=2, then was corrected.
Nine offline guards, nine Python compilations and syntax/security/ShellCheck pass.
Independent review accepts this test-only increment. See the TLS access plan.

## Native preexisting account reuse — 2026-10-24

TLS acceptance is committed as `5e006ce`. New account-reuse fixture `ecwu2gy_`
passes18/18: guest-only valid system identities survive actual dependency refusal,
late-deadline deployment compensation and full install/restart/apply/restore.
All four NSS file bytes/mode/UID/GID remain at their preexisting baseline,
transaction account ledgers stay empty, and actual Core UID/GID match policy.
Native/Make exit0, unchanged host databases, scope not-found and no guest mounts.
Control/key/results: `/var/tmp/pnm-account-volume.k93z09hb`; full encrypted image
in the ignored D pool passes trusted cipher/raw readback verification, loop is
detached and cleanup errors are empty. Nine offline guards, ten compilations and
syntax/security/ShellCheck pass; independent source review has no blocking issue.
This test-only slice covers valid reuse, not every account-tool failure. The
earlier container preparation plan is reconciled against these actual outcomes.

## Recovery readiness and native process interruption — 2026-10-24

Account reuse is committed as `ed0a670`. Source review during real TERM testing
identified that standalone recovery re-certified active Type=simple services
before listener readiness. The existing deployment runtime-port wait is now shared
by deployment and Core recovery (including restore). Both recheck active/config
after waiting; Core recovery also rechecks the original applied baseline. Absent
or unknown listeners, invalid runtime ports and observed drift cannot publish
recovered evidence; originally disabled policy remains disabled.

Focused RED passes38/fails2 in Core evidence and13/1 in rendering. GREEN passes
40/40 and14/14. Final frozen `/var/tmp/pnm-recovery-full.m_tn0a5p` passes static
checks and `make check`: **31 suites/383 tests, exit0**. Nine current offline
guards and eleven Python compilations pass. Two failed full logs remain private:
old simulated config/service boundaries and one misplaced fixture-state edit were
corrected before the final19/19 deployment suite and full success.

Actual Xray `gljriftj` and HY2 `8itir9ca` each pass17/17. TERM preserves143 and
returns with the target's real listener and recovered binding ready; resource and
peer state remain intact. SIGKILL leaves the unfinished journal and old applied
bytes. After owned drop-in removal, writer/links/show/check all refuse70 with
empty stdout and unchanged PNM/NSS/managed resources. Both runs record nspawn0,
unchanged host databases, not-found scope and no guest mounts. Xray's protected
control `/var/tmp/pnm-signal-green-volume.37po60eo` retains verified encrypted
evidence, released loop and empty cleanup errors. HY2's control is
`/var/tmp/pnm-signal-hy2-volume.o83q9afv`; its complete encrypted image also
passes cipher/raw readback verification, with detached loop and no cleanup errors.
The earlier test assumption requiring two starts was rejected; recovery may
legitimately preserve an active process. Its failed image is retained separately.
Independent source reviews accept the final production repair and per-Core test
parameterization. This is process interruption, not independent VM/kernel reboot.

## Ordinary restart readiness — 2026-10-24

Recovery/interruption repair is committed as `54d5d67`. Ordinary restart now
waits for its runtime listener before the original service health, applied binding
and success; missing/error observations retain78 and enter existing compensation.
Focused RED0/1 becomes GREEN1/1 (both Cores and both error outcomes). Independent
review also found HY2 FIFO/symlink input could bypass the helper's bounded probe;
safe RED times out124, then a regular/readable/non-symlink guard yields15/15
renderer tests. Final `/var/tmp/pnm-restart-final.mkb7hk8r` passes syntax/security/
ShellCheck, nine guards and **31 suites/385 tests, exit0**. Eleven Python sources
compile. The earlier31/384 full result predates the final type guard.

Final native `7xhrrhf0` passes16/16 including both actual delayed CLI restarts,
ready TCP/UDP at return, single startup attempts, correct new applied binding,
identical target resources and untouched peer. Native/Make exit0, unchanged host
databases, scope not-found, no mounts. Control/key/results are under
`/var/tmp/pnm-restart-final-volume.d52dqp7n`; encrypted full image in the ignored
D pool passes cipher/raw readback verification, loop detached, cleanup errors
empty. Earlier regular-file success is retained separately. Independent review
accepts the type-guard correction; no production or external traffic was tested.

## Native missing-dependency matrix — 2026-10-24

Ordinary restart repair is committed as `22e088b`. Fresh `fitvjgzu` passes33/33:
all19 declared preflight tools are individually absent only from a private PATH,
with actual JSON install refusal2 in the corresponding class. Authority/NSS
fingerprints, PNM inventory/transaction set and absent service/account/resource
baselines stay unchanged. Per-case finally restores the environment and owned
link; the original14-case lifecycle then passes. Native/Make exit0, unchanged
host databases, not-found scope and no mounts. Protected control/key/results:
`/var/tmp/pnm-dependency-volume.7got3ah5`; full encrypted image in the ignored D
pool passes cipher/raw readback verification, loop detached, cleanup errors empty.
Nine guards, twelve Python compilations and syntax/security/ShellCheck pass.
Independent source review has no blocking issue. Product source is unchanged
from the31-suite/385-test baseline; this is Debian missing-tool preflight evidence,
not upstream acquisition, another distribution or external-client acceptance.

## First-deployment startup failure recovery — 2026-10-24

Dependency refusal is committed as `e726f17`. Real RED `7ivqzpmd` restored files,
NSS and directories after Xray startup failure, but left the unit not-found/failed/
PID0 while recording ROLLED_BACK. Verified stopping now reuses restore's existing
failed/reset/requery policy through the systemd adapter. Before changes and after
compensation, missing units require successful inactive/PID0 queries. Matching
stdout cannot conceal observation errors; unowned missing/failed baselines are
refused without resetting them.

Focused RED has3 deployment failures plus1 missing-helper case. GREEN passes
deployment22/22, lifecycle9/9, restore-recovery12/12, restore-flow17/17, deploy8/8
and sandbox12/12. Initial full388/1 and restore-flow12/5 exposed fixture imports/
MainPID mock assumptions; actual adapter imports/property responses are corrected.
Final frozen `/var/tmp/pnm-deploy-start-full.j0rp4aah` passes syntax/security/
ShellCheck, nine guards and **31 suites/389 tests, exit0**;13 Python sources compile.
Independent source reviews accept the final repair and fixture dependency fixes.

Fresh `4n7nub1u` passes16/16: both first-Core startup failures fully restore
authority/NSS/directory/service baselines, retain original70 with completed
rollback and no applied/commit, then complete the normal main flow. Native/Make
exit0, unchanged host databases, scope not-found and no mounts. Protected control/
key/results `/var/tmp/pnm-deploy-start-green-volume.xowihu1c` and the ignored D
full-image archive pass cipher/raw readback verification, loop detached, cleanup
errors empty. The failed RED image and safe observations remain separately retained.
No production host, independent VM reboot or external client was exercised.

## Actual deployment post-health listener failures — 2026-10-24

Initial-start recovery is committed as `08b4a6c`. New listener-failure mode uses
a validated12-second managed-start delay without replacing Core binaries or
validators. A bounded observer directly confirms active and no target TCP/UDP
listener; return before first-accept+11.75 seconds proves that managed startup
never reached exec before failure completion. Both lifecycle phases precede the
specific Core check and post-health failure78. Full authority/NSS/directory/unit
compensation, no applied/commit promotion and a normal main-flow retry follow.

Final fresh `yex496qc` passes16/16. Native/Make exit0, unchanged host databases,
scope not-found, no mounts. Control/key/results
`/var/tmp/pnm-deploy-listener-final-volume.eilh3c60` and ignored D full image pass
cipher/raw readback verification, detached loop, cleanup errors empty. Earlier
phase-only evidence is retained separately. Nine guards (including invalid-delay
types/bounds), thirteen Python compilations and syntax/security/ShellCheck pass;
independent review accepts the final causal evidence and thread cleanup. Product
source remains31 suites/389 tests; this test-only slice does not prove VM reboot
or external connectivity.

## Whole-deployment process interruption — 2026-10-24

Post-health listener acceptance is committed as `3336d92`. The existing exact
CLI Popen/session watcher is shared between standalone and deployment tests,
with namespace/SID/PGID ownership checks, bounded retirement and primary-error
preservation. Actual TERM `r7jlz938` passes16/16: both first-start windows retain
143 plus APPLY_FAILED rc143, complete all original resource/NSS/directory/service
compensation, then run the normal lifecycle. Initial SIGKILL `kaiki853` passes5/5.
Their full images under control `/var/tmp/pnm-deploy-signal-volume.cz3yjtzb` and
the ignored D archive pass cipher/raw readback; loop detached, cleanup errors empty.

Final SIGKILL `wetg5fc0` passes5/5 with explicit unresolved-deployment stderr,
empty stdout and unchanged PNM/NSS/managed resource inode/mtime/runtime state
across real apply/links/show/check. Control/key/results:
`/var/tmp/pnm-deploy-sigkill-final-volume.ppf6ot75`; its full encrypted image also
passes readback, loop detached and no cleanup error. All native/Make exits0 retain
unchanged host databases, not-found scopes and no mounts. SIGKILL explicitly
reports mainflow_completed=false and expected_recovery_required=true: candidate
state is retained, no automatic recovery or full healthy lifecycle is claimed.
Nine guards, thirteen compilations and syntax/security/ShellCheck pass; independent
review has no blocker. An approval-service quota rejection delayed the final
rerun; later continuation was approved and no approval check was bypassed.
Product source remains31 suites/389 tests. Update/restore interruption and other
fault-position matrices remain necessary local work before external closure.

## Actual Core update/rollback process interruption — 2026-10-25

Whole-deployment interruption is committed as `2d26132`. The distinct-version
fixture now shares the exact owned CLI watcher for each Core's update and
rollback after binary publication. TERM `7j76s5tp` passes26/26: preserve143,
restore original binary/config/previous bytes and metadata, reactivate the actual
prior version, refresh applied binding, preserve peer and finish the normal matrix.
Native/Make exit0, unchanged host databases, scope not-found and no mounts.
Control/key/results `/var/tmp/pnm-update-term-volume.t4khgkre` and the ignored D
full encrypted image pass readback, loop detached, cleanup errors empty.

Independent SIGKILL update Xray `3dpcxgms` passes17/17, update HY2 `_cqcdl7y`
passes21/21, and rollback Xray `2r8p2l7r` passes18/18. Their controls
`/var/tmp/pnm-core-update-sigkill-xray-volume.qd0i2b31`,
`/var/tmp/pnm-core-update-sigkill-hysteria2-volume.qqg8cyxp` and
`/var/tmp/pnm-core-rollback-sigkill-xray-volume.h2akq7k8` verify full-image
readback, detached loops and empty cleanup errors. Rollback HY2 `ht89ott5`
passes22/22; control `/var/tmp/pnm-core-rollback-sigkill-hysteria2-volume.vhsoaqxh`
also verifies full encrypted-image readback, detached loop and empty cleanup errors.
All four native/Make exits0 retain unchanged host databases, not-found scopes
and no fixture mounts. SIGKILL retains the candidate generation and prior
applied/previous records without a commit. After the owned HTTPS server retires,
actual writer/links/show/check refuse70 with the exact unresolved operation,
empty stdout and unchanged persisted/runtime state. Reports separate the
completed initial lifecycle from an incomplete update matrix.
Nine guards, fifteen Python compilations and syntax/security/ShellCheck
pass. Static independent review has no blocker. Product source remains31/389;
late previous/metadata/commit positions, restore interruption and VM/external
acceptance are separate. The user currently has no deployed target for G-01.
The task runner reports `usageLimited`; this increment is closed without starting
another stage. Restore interruption and late fault-position work remain local
next actions, rather than being reclassified as external acceptance blockers.

## Actual trusted restore process interruption — 2026-10-25

Update/rollback interruption is committed as `a2f8654`. Consecutive local work
resumes under the renewed user instruction. Restore reuses the protected trusted
archive, exact owned CLI/session watcher and real managed Core startup. It owns
both Cores, so compensation checks both original runtime bindings and listeners,
all resource bytes/modes/UID/GID, directory identities, NSS and previous state,
then retries the archive successfully.

Initial TERM `78z29jw3` passes17/17 with verified archive under
`/var/tmp/pnm-restore-term-volume.hcfa56al`. Initial SIGKILL Xray `2ngevftq`
fails the HY2-inactive assertion: Type=simple returns before the delayed ExecStart
probe, so the CLI can already continue to HY2. Its failed full image is separately
retained and verified under `/var/tmp/pnm-restore-sigkill-xray-volume.8_hd28ny`;
loop detached, cleanup errors empty. It is not passing acceptance evidence.

The existing start fixture now has a bounded ExecStartPre delay, preserving the
real Core ExecStart and Type=simple. Guards first fail on the absent mode, then
pass9/9; fifteen Python sources compile and syntax/security/ShellCheck pass.
Independent source review accepts the cause and repair; service-state assertions
still reject a missed signal window. Final TERM `_o0lwh5i` passes17/17, including
both compensation windows and a healthy trusted restore retry. Control
`/var/tmp/pnm-restore-term-final-volume.u3wg8v9z` verifies full encrypted-image
readback, detached loop and no cleanup error. Native/Make exit0, unchanged host
databases, scope not-found and no fixture mounts. Final SIGKILL Xray `npkl6xla`
and HY2 `k844uu2j` each pass16/16. Both retain published archive resources, prior
applied evidence and an unfinished core-restore journal. After fault removal,
actual apply/links/show/check refuse70 for that exact operation with empty stdout
and no persisted/runtime mutation. Xray's window leaves HY2 inactive/PID0; HY2's
window has both new live generations. Reports explicitly retain
mainflow_completed=true, restore_matrix_completed=false and
expected_recovery_required=true; they do not claim automatic recovery.
Xray control `/var/tmp/pnm-restore-sigkill-xray-final-volume.u6y5tp_5` verifies
full-image readback, detached loop and empty cleanup errors. HY2 control
`/var/tmp/pnm-restore-sigkill-hysteria2-final-volume.1b9imypr` also verifies
full encrypted-image readback, detached loop and empty cleanup errors. Both native/
Make exits0 leave unchanged host databases, not-found scopes and no fixture
mounts. Product Bash is unchanged; the31/389 baseline was not repeated for this
test-only increment. Earlier partial-file publication, late publication/commit,
independent VM/reboot, deployed-source identity and external clients stay open.

## Native Core publication read-only failures — 2026-10-25

Restore interruption is committed as `f6f60ee`. Next T-22 slice uses a guest-only
one-use move launcher for previous binary, previous metadata and applied evidence.
It runs the real mv under a read-only bind in a new private child mount namespace,
requires kernel EROFS, then removes only its own identified bind before returning
the actual failure. Parent mounts are only compared, never cleaned with child IDs.
Real CLI73 and stage-specific error, original resource/previous pairing, refreshed
binding, unchanged peer and completed uncommitted compensation are required for
each operation/Core, followed by clean version swaps.

Initial `2of0eycu` passes18 preceding checks but refuses before any fault mount:
the existing guest propagation is not fully private. Its separately retained
control `/var/tmp/pnm-core-publication-previous-volume._fuk4tfd` verifies full
encrypted-image readback, detached loop, empty cleanup errors and unchanged host
DBs. Read-only verified-image extraction confirms the guard cause. This is failed
fixture evidence, not an EROFS acceptance pass. A new private child namespace
addresses the cause; independent review also removed a cross-namespace parent
unmount fallback before execution. Host refusal includes both launcher paths and
direct unmount; unsafe targets refuse before actions. Nine guards,16 Python
compilations and syntax/security/ShellCheck pass. Final previous `x4aht50p`
passes26/26: both real Core operations observe kernel EROFS and actual mv failure,
restore resources/previous/binding without peer changes, and allow clean swaps
forward. Native/Make exit0, unchanged host DBs, scope not-found and no mounts.
Its control `/var/tmp/pnm-core-publication-previous-final-volume.w3fymwp8`
verifies full encrypted-image readback, detached loop and empty cleanup errors.
Final metadata `kow46z9k` also passes26/26, native/Make exit0, unchanged host DBs,
scope not-found and no mounts. Its control
`/var/tmp/pnm-core-publication-metadata-final-volume.1ztys_du` verifies the same
full-image retention and cleanup. Final applied `bfopszs1` passes26/26 with the
same native/Make0 and host/scope/mount guarantees. Its control
`/var/tmp/pnm-core-publication-applied-final-volume.tktrfinz` also verifies full
encrypted-image readback, detached loop and empty cleanup errors. In total twelve
actual transient VFS EROFS publication paths pass across the three fresh guests;
the repeated normal-flow checks are not twelve independent full matrices.
Production Bash is unchanged; the31-suite/389-test baseline was not rerun for
this test-only stage. Commit/marker faults, earlier restore-write faults, persistent
storage/power-loss durability, independent VM/reboot, G-01 and external clients
remain open.

## Native partial restore publication refusal — 2026-10-25

Core publication EROFS acceptance is committed as `d475c80`. T-24 now reuses the
same private-child move fixture for one additional fixed HY2 configuration path
and the existing restore failure/retry validation. A different archived node must
already have APPLIED evidence while the failed target has INTENT but no APPLIED;
ordinary WRITE count must lie strictly between0 and the resource count. Both
original resources/modes/UID/GID, directories/NSS and fresh bindings, no commit,
completed rollback and trusted restore retry are required.

The new routing guard first fails for the absent scenario, then9 guards pass.
Sixteen Python sources compile; syntax/security/ShellCheck pass. Independent
source review finds no blocker; the original startup-failure default remains.
Native `sbvfde8t` passes16/16. Safe observations confirm4 of12 ordinary resources
published, the distinct archived node applied, the failed target unpublished,
kernel EROFS30, actual mv1 and removed child bind. Both original generations
recover with healthy bindings/checks, then trusted restore retry succeeds.
Native/Make0 leaves unchanged host DBs, scope not-found and no mounts. Control
`/var/tmp/pnm-restore-publication-volume.5yo2uajz` verifies full encrypted-image
readback, detached loop and empty cleanup errors. Final review finds no blocker.
Product Bash is unchanged; the31/389 baseline was not repeated for this test-only
stage. Commit/marker, persistent storage, VM/reboot, deployed identity and clients stay
separate.

## Native deployment publisher precommit refusal — 2026-10-25

Partial restore refusal is committed as `4206f2e`. T-15 now targets the unchanged
real python publisher after unique COMMIT_INTENT and both applied writes. The
launcher validates canonical protected deployment transaction metadata, delegates
other Python calls unchanged, and uses a new private child namespace with the
shared guarded read-only bind. A scoped interpreter observer records only the
real pending-file EROFS errno/path match; it does not replace IO APIs, exceptions
or return values. Parent namespace/mounts are compared only, never unmounted with
child IDs. Full original deployment/NSS/directory/unit recovery and a healthy
normal-flow retry remain required, with no marker or uncertainty residue.

New entries first fail offline; then10 guards pass, including observer filtering
and unchanged control flow. Seventeen Python sources compile and static gates
pass. Independent pre-execution review accepts stdin/observer scope, dynamic path
validation, mount ownership and existing move/startup behavior. Native publisher
control `/var/tmp/pnm-deployment-commit-readonly-volume.3yn9k7x9` runs `fkorwxid`,
now15/15: actual pending-file EROFS30 and publisher73 after COMMIT_INTENT, both
applied writes and post-health; full resource/NSS/directory/unit recovery, no
marker/uncertainty/applied residue and a complete healthy main-flow retry.
Native/Make0 leaves host DBs unchanged, scope not-found and no mounts. The control
verifies full encrypted-image readback, detached loop and empty cleanup errors.
Shared-bind move regression `mtixk7f7` also passes16/16, again4 of12 resources
published before the actual restore EROFS and a successful trusted retry. Control
`/var/tmp/pnm-restore-publication-volume.50mysyr7` verifies the same full-image
retention and cleanup, with unchanged host DBs/not-found scope/no mounts.
Product Bash is
unchanged; later marker/rename/fsync uncertainty, persistent media, VM/reboot,
G-01 and external clients stay separate.

## Deployment abort marker observation repair — 2026-10-25

Continue T-17 from `236b566`. A shell `-e`/`-L` false result also covered an
unavailable transaction directory. The rollback engine retained a failed journal
append but still invoked service-control callbacks. A private Linux filesystem
test publishes a real valid marker without setting the in-memory committed flag,
then moves its own transaction directory aside: old abort wrongly controls
services (22 pass/1 fail). This is mocked-service evidence, not hardware EIO.

Abort now queries the marker relative to an opened, owner-matching `0700`
directory, without following its final symlink or the marker. Only dedicated
status3 means confirmed leaf absence and permits rollback. Existing markers and
all unknown states retain recovery70, the original error and candidate resources.
Independent review caught generic Python failure1 being mistaken for absence;
the added regression reproduces that problem (23 pass/1 fail), then passes after
the dedicated status repair. Its post-close marker assertion now uses a saved
transaction path. Final `/var/tmp/pnm-marker-checked-records.s6pfj9_l` passes
syntax/security/ShellCheck, focused24/24 and full31 suites/391 tests, exit0.
Frozen production/test bytes match the working tree. Earlier full attempts
`qsxub6l8` and `we44xriy` remain failed evidence: private source ancestors blocked
the real nobody test; the latter also had the repaired post-close test assertion.
Final checks separate readable source from mode0700 logs; no product permissions
were relaxed. Independent final review finds no blocker.

Final native publisher EROFS guest `_w5ter13` passes15/15 under
`/var/tmp/pnm-marker-probe-final-native-volume.povfwhp2`: kernel EROFS30 and actual
publisher73, successful known-absent compensation, original NSS/directories/units,
no marker/uncertainty/applied residue and complete healthy retry. Native/Make0
leaves host DBs unchanged, scope not-found and no fixture mounts. Full encrypted
image readback verifies, the loop is detached and cleanup errors are empty. The earlier
`jn5cusz_`15/15 run also verified encrypted readback and cleanup, but predates the
dedicated status repair. Late post-rename SIGKILL remains the next local increment;
hardware IO failure, independent VM/reboot, G-01 and external clients stay open.

## Native late deployment marker interruption — 2026-10-25

Marker observation repair is committed as `292b682`. T-17/T-19 now exercises the
real publisher after successful rename and before the following directory-sync
call executes. A narrowly scoped interpreter trace observes both real records,
cleared temporary name and the exact call, writes only fixed safe booleans and
pauses for at most30 seconds. A complete root0600 receipt, rather than existence
alone, authorizes the existing owned live CLI SID/PGID SIGKILL watcher. Publisher
stdin and filesystem APIs remain unchanged; PATH is restored before new commands.

New entries first fail for the missing observer module, then11 offline guards
and18 Python compilations pass. Syntax/security/ShellCheck pass. Independent
pre-execution review finds no blocker in stdin, signal ownership, call timing,
scope restoration or evidence boundaries. Native `kx7wcwuz` passes6/6 under
`/var/tmp/pnm-late-commit-sigkill-volume.tsq9luc1`: actual CLI-9, unique terminal
COMMIT_INTENT, both applied writes, valid product-verified marker and retained
uncertainty, no commit/rollback, both enabled applied-bound real generations and
listeners. Four new real writer/links/show/check commands refuse70 with exact
unresolved deployment cause, no stdout and no receipt/resource/runtime changes.
The intentional unresolved result reports mainflow_completed:false and
expected_recovery_required:true. Native/Make0 leaves host DBs unchanged, scope
not-found and no fixture mounts. Full encrypted image readback verifies, loop
detaches and cleanup errors are empty. Product Bash is unchanged;31/391 remains the
latest full baseline. This does not close fsync failure, hardware power loss,
independent VM/reboot, G-01, upstream acquisition/platform or external clients.

## Native account creation refusal — 2026-10-25

Late commit interruption is committed as `6a7e970`. Continue T-08/G-06 with
actual shadow creation tools, preserving the existing guest and transaction
model. Exact second-identity hysteria groupadd/useradd invocations are isolated
in new private child namespaces with a read-only `/etc` bind. Prior actual Xray
identity and the precise absent-user/present-or-absent-group point are checked
before running the tool. A kernel EROFS probe and actual nonzero tool result are
separate evidence; this does not observe or synthesize the tool's internal errno.
Only the creating child unmounts its exact bind; unrelated/recovery invocations
delegate normally, and PATH plus parent namespace/mounts are preserved.

Missing implementation first fails the guards. Final11 guards,19 Python
compilations and syntax/security/ShellCheck pass under
`/var/tmp/pnm-account-final-gates.bhnu66xg`. Independent pre-execution review
finds no blocker. Native `uvjp4dv2` passes16/16 under
`/var/tmp/pnm-account-creation-volume.dye5wq46`: separate real groupadd/useradd
failures returnCLI70 after2/3 actual APPLIED identities; all have matching
RESTORED, target INTENT has no APPLIED, terminal rollback and no commit/applied
promotion. Primary NSS bytes/numeric metadata, authority, directory identity/
metadata and service baseline recover; all managed identities/resources are
absent, followed by the complete healthy normal lifecycle/backup/restore retry.
Primary NSS means passwd/group/shadow/gshadow, not ancillary shadow backup files.
Native/Make0 leaves host DBs unchanged, scope not-found and no mounts. Full
encrypted readback verifies, loop detaches and cleanup errors are empty.
Independent final review finds no blocker. Account deletion failures,
other NSS/platform/upstream cases and independent VM/client gates remain open.
Product Bash is unchanged;31/391 remains the current full baseline.

## Native account deletion refusal — 2026-10-25

Creation compensation is committed as `1b49c04`. T-08 now covers incomplete
recovery when actual userdel or groupdel fails. The existing account fixture
accepts exact `-- hysteria` deletion commands only at the expected NSS removal
point, with both services already not-found/inactive/PID0. The reviewed shared
child read-only `/etc` bind preserves mount ownership and parent isolation.
Creation retains its restricted wrapper and original behavior. Combine this
with the existing real publisher EROFS73; each deletion case uses a fresh guest.

New generic/deletion entries first fail, then11 guards,19 Python compilations
and syntax/security/ShellCheck pass under
`/var/tmp/pnm-account-delete-gates.48oxnj46`. Independent pre-execution review
finds no blocker. Userdel guest `03i3l3z_` passes5/5 under
`/var/tmp/pnm-account-delete-user-volume.qia_bd8w`: actual deletion refusal,
CLI70 with original73/recovery70, exact remaining owned user/group and unfinished
APPLIED receipts, RECOVERY_REQUIRED, ordinary resource/service baseline restored,
no marker/commit and four fresh protected command refusals without stdout or
receipt/NSS/resource/directory/unit mutation. Its intentional result is
mainflow_completed:false and expected_recovery_required:true; it does not claim
complete NSS or directory compensation. Its full encrypted-image readback and
cleanup verify. Initial groupdel `plytlxc6` under
`/var/tmp/pnm-account-delete-group-volume.vwhvltu5` fails at CLI73 rather than70;
its failed image still verifies full encrypted readback, detached loop, unchanged
host DBs/not-found scope/no mounts and no cleanup errors. Read-only verified-image
inspection proves USERGROUPS_ENAB=yes, no remaining Hysteria group, its RESTORED
receipt and no groupdel wrapper attempt. Actual userdel had removed the private
group, so the intended tool fault never ran. The installed userdel manual also
documents this policy. The first inspector incorrectly assumed a single tx and
was corrected to select OPERATION=deployment; only read-only extraction occurred.

Only the fresh groupdel fixture now configures USERGROUPS_ENAB=no before taking
its baseline. It verifies the protected regular policy file and unique setting,
preserves mode/UID/GID/inode and compares login.defs across recovery and refusals.
The userdel case retains the default yes policy. No PNM argv or product code is
changed. Independent review accepts this smaller policy branch instead of adding
foreign group members (which would itself prevent explicit groupdel). Final
groupdel `kxu3cfbs` passes5/5 under
`/var/tmp/pnm-account-delete-group-final-volume.qluan8iw`, including actual
groupdel refusal under the explicit no policy and exact remaining owned group.
Full encrypted readback/cleanup verify, with host DBs unchanged, scope not-found
and no mounts. Final default-policy userdel `g7re80jp` also passes5/5 under
`/var/tmp/pnm-account-delete-user-final-volume.ehcq2731`; its full encrypted
readback/cleanup verifies with the same unchanged host/not-found scope/no mounts.
Shared creation regression `pqxtqvyd` passes16/16 under
`/var/tmp/pnm-account-creation-final-regression-volume.zpaqug3_`, including normal
complete lifecycle/restore; full encrypted readback and cleanup verify, host DBs
remain unchanged, scope is not-found and no mounts remain. These runs use the
updated19 compiled Python sources. Independent final review finds no blocker.
No failed fixture run is counted as a refusal PASS. Production Bash has no diff
from the verified `292b682` full31/391 baseline; it was not rerun for this
integration-only increment.
Product Bash is unchanged;31/391 remains the full baseline.

## Independent Debian VM preparation — 2026-10-25

Account deletion acceptance is committed as `820d6cc`. Continue the existing
independent-kernel VM/reboot gate with the available WSL host rather than
assuming missing emulator packages make it impossible. Initial read-only checks
observe KVM API12, no installed QEMU/kernel/initrd and APT candidate metadata.
`/var/tmp/pnm-vm-tools.s1a8keac` then creates and immediately closes an empty
KVM VM descriptor successfully, with unchanged host NSS/dpkg hashes. This is not
KVM_RUN or boot evidence. Full baseline ownership inspection covers10,184
entries within the unshifted numeric range; key path samples are0:0. No ownership
conversion is performed. The first owned ext4 clone preserves the compared
account/init bytes, modes and numeric ownership.

Private APT configuration inspection now passes: APT_CONFIG/main/parts/sources/
preferences/auth/status/cache/log paths are isolated and effective Pre/Post-
Invoke hooks are absent. Signature, date/validity and archive hash checks remain
enabled; only explicit official Debian13 sources are configured. The installed
public `.gpg` keyring is a protected alias to `.pgp`; after validating its root-
owned canonical target/ancestors, a private snapshot is used without modifying
system trust. The initial regular-file assumption stopped preparation before any
download and was corrected. Host databases remain unchanged. The download-only
script passed independent review. Authenticated APT refresh/download now passes:
38 packages,124MiB, including QEMU10.0.13 and Debian kernel6.12.113+deb13-amd64.
Every archive's size/SHA256 matches fresh signed metadata before parsing its
control fields. All38 data archives are extracted privately without maintainer
scripts or host installation. QEMU/busybox/cpio runtime probes pass; private
depmod/modprobe resolution supplies8 initramfs modules. The1,770,448-byte
initramfs has a recorded SHA256; its real host invocation refuses77 before any
mount, with unchanged mountinfo and host databases. Baseline ownership covers
10,184 entries. Busybox provides findfs rather than blkid, so the init script
uses findfs and still requires the supplied UUID to resolve to/dev/vda.

Preboot checks `/var/tmp/pnm-vm-preboot-gates.yf42qq4w` pass12 host guards,
20 integration Python compilations and syntax/security/ShellCheck. The first
boot attempt `/var/tmp/pnm-vm-boot-volume.twmcogmx` stops before the guest kernel:
legacy QEMU -drive auto-opens O_RDONLY while the exclusive anonymous fdset has
only O_RDWR. The failure is reproduced on a small fresh anonymous file; explicit
file/raw -blockdev permissions survive the bounded paused-VM probe with default
locking retained. The failed disk is fully encrypted/readback-verified, the loop
is detached, QEMU is quiescent, host databases are unchanged and cleanup is empty.
Fresh `/var/tmp/pnm-vm-boot-volume.n79xtpbb` now passes the complete boot-only
slice: actual Debian13 kernel6.12.113+deb13-amd64, systemd running, distinct
boot/machine identities, only lo, matching live QEMU PID/start/executable/argv
and anonymous disk FD, one-use serial approval, persisted guest result, clean
powerdown and QEMU exit0. Full2GiB encrypted image readback matches the original
digest; loop detached, QEMU quiescent, host NSS/dpkg unchanged and cleanup empty.
No PNM resources are installed in this boot-only slice. PNM lifecycle, same-disk
independent reboot and abrupt-VM interruption remain separate next steps.
Independent review of later extraction/initramfs/operator code was unavailable
after the reviewer reached its usage limit; compilation, self-review and actual
checks are recorded separately and do not stand in for independent review.
The [separate plan](superpowers/plans/2026-10-25-independent-debian-vm.md) retains
raw exclusive owned storage, explicit QEMU device/config restrictions, nonce/
live-process/serial binding and encrypted full-image/cleanup requirements.

## Independent VM lifecycle/reboot and abrupt-stop acceptance — 2026-10-25

VM lifecycle/reboot acceptance is committed as `4561782`. The next abrupt-VM
slice compiles22 integration Python sources and passes17 guards plus static
checks at `pnm-vm-abrupt-preboot.ao15em3i`. Only the publisher pause helper gains
the approved VM route; general startup/account/mount fault guards stay mapped-
container-only. `/var/tmp/pnm-vm-boot-volume.ytr_5uep` reaches the actual
post-rename/uncertainty window, validates the live QEMU PID/start/argv/executable/
disk again and stops that QEMU with SIGKILL/-9. Same-disk next-kernel acceptance
reads the persistent uncertainty record, then hits IndexError while the test
parses journal rows. The failed image is fully encrypted/readback-verified,
QEMU is quiescent, loop detached, host databases unchanged and cleanup empty.
Read-only verified-image inspection confirms2935 journal bytes,8 rows including
one NUL-containing malformed row, no retained COMMIT_INTENT or terminal event,
and intact uncertainty. Progress appends are not the commit authority and are
not individually fsynced by pnm_tx_journal; requiring their complete persistence
was a test error. Preserve the exact damaged bytes and inspect them safely;
acceptance still requires real four-command refusal without mutation, rather
than inferring safety from an inspector result. Recheck the live pause/markers
after persisting its baseline so stale observations cannot authorize a VM kill.
Guards now pass18/18,22 integration sources compile and static checks pass at
`pnm-vm-abrupt-final-preboot.pr90cmyr`. A fresh complete run is in progress at
`/var/tmp/pnm-vm-boot-volume.6fb5o_my` now passes the observed live-owner VM kill
(-9) and same-disk next-kernel recovery checks. Uncertainty and the valid marker
remain; the journal again contains one malformed row and no persisted commit
intent/terminal event. Both service invocations change, managed resources and
authority/NSS are preserved, and four actual fresh commands refuse70 with the
deployment-specific cause, empty stdout and no receipt/resource/runtime mutation.
No recovery record is repaired by the fixture. Normal recovery-guest poweroff
and QEMU0 pass. Full2GiB encrypted image readback matches its original digest;
loop detached, QEMU quiescent, host NSS/dpkg unchanged and cleanup empty.

Independent boot-only acceptance is committed as `102483a`. Stage2 now reuses
the actual14-case mainflow under a VM guard and this boot's private approval;
the mapped nspawn route retains its existing UID/namespace checks. A fresh VM
will request an actual guest reboot and re-enter the same owned disk/kernel.
Post-reboot checks require changed boot ID and both Core invocations, unchanged
persisted resources/applied records, withheld stale links, non-promoting ordinary
restart, and per-Core validated apply without changing its peer. Host refusal
and stale-approval guards pass15/15 at `pnm-vm-lifecycle-guards.ch_o1q15`;21
integration sources compile. Full VM execution/archival is still in progress at
`/var/tmp/pnm-vm-boot-volume.llmpj6is` passes the real14-case lifecycle and
requests guest reboot. Its reboot test initially expects node-links0 even when
both unsafe links are withheld. The verified encrypted image's read-only
debugfs inspection observes both statuses drift, both URI values null and empty
stderr; product node.sh explicitly returns78 in this case. Correct only the
test expectation to78 when no Core is confirmed, retaining0 when any link is
ready. The failed run remains retained with full image readback, detached loop,
quiescent QEMU, unchanged host databases and empty cleanup. A fresh full rerun
at `/var/tmp/pnm-vm-boot-volume.nm7fh9va` again passes14 lifecycle checks and
reaches post-reboot acceptance. It then exposes JSONDecodeError in the test's
CLI helper: ordinary restart text was parsed as JSON. A focused real-helper
regression reproduces that error at `pnm-vm-output-red.bkw7854h`; restrict JSON
parsing to commands explicitly using --json. Reboot PASS remains open while
this failed image is archived. Its full encrypted2GiB readback and cleanup pass.
The output-contract regression and host guards pass16/16 at
`pnm-vm-output-green.wgccpgz1`; all21 integration sources compile. A new complete
rerun `/var/tmp/pnm-vm-boot-volume.4m0l596i` now passes14 real mainflow checks,
actual guest-requested reboot and7 reboot acceptance checks. The first kernel
reports Restarting system/QEMU0; the same owned anonymous disk is relaunched
with a fresh nonce. Kernel boot ID and both service invocations change while
persisted Core resources, applied records, authority and NSS stay unchanged.
Both stale URIs remain withheld through ordinary restart. Each explicit apply
reconfirms its own applied binding and preserves its peer; both TCP/UDP
listeners are observed before normal poweroff/QEMU0. Full2GiB encrypted image
readback now matches the original digest, the owned loop is detached, QEMU is
quiescent, host NSS/dpkg hashes are unchanged and cleanup is empty. Source is
unchanged from this actual run; the default31/391 baseline is
unchanged, not freshly rerun. Independent review remains unavailable; this
increment has self-review and executed checks.

## Matrix reconciliation — 2026-10-25

This is a source-to-evidence reconciliation of T-01–T-27 in
[the acceptance plan](ACCEPTANCE_PLAN.md), not a new27-case execution campaign.
L1 refers to the recorded full Bash suite; native means the previously recorded
private nspawn guest sharing WSL's kernel; VM means the independently booted
Debian13 kernel. Native evidence must not be silently relabeled L2 VM evidence.
The [guest guide](../tests/integration/GUEST_MAINFLOW.md) names each executable
scenario; dated records above retain its actual results and limitations.

| ID | Verified boundary | Still not established by that evidence |
|---|---|---|
| T-01 | L1, native and VM positive dual-Core install/lifecycle; real identities, bindings, TLS and listeners | External traffic and the whole supported-platform matrix |
| T-02 | L1 credential/TLS reuse and corruption refusal; native/VM repeat-install refusal preserves resources | A complete VM replay of every existing-credential corruption/reuse branch |
| T-03 | Native19 prerequisite refusals; VM actual first-install partial/trust/checksum refusals for both Cores and verified non-ZIP Xray staging refusal with complete outer recovery; VM update transport/checksum refusal | Upstream DNS/PKI outages, timeout/other ZIP/version combinations and other distributions |
| T-04 | L1 configured-port checks and native configured/default-port conflict lifecycle | Complete independent-VM conflict replay |
| T-05 | L1 alias/symlink/managed-path and directory protection; host fixture refusal guards | Cross-process privileged ancestor replacement is outside the protected-parent assumption |
| T-06 | L1 original/missing byte and numeric metadata compensation; selected native complete-resource checks | Every nondefault metadata combination on every L2 operation |
| T-07 | L1 directory enrollment/drift/empty removal; native directory compensation checks | All externally modified directory timings on the independent kernel |
| T-08 | Native valid-account reuse and real groupadd/useradd/userdel/groupdel refusal, precise incomplete recovery | Other NSS providers/platforms and account interruption timings |
| T-09 | Native real first-Xray startup failure and complete compensation/retry | Full VM replay of all startup fault positions |
| T-10 | Native real first-HY2 failure after Xray activation and complete compensation/retry | Full VM replay of all startup fault positions |
| T-11 | Native active-without-listener failures for each Core, full compensation/retry | All VM scheduling/listener-failure variants |
| T-12 | L1 TLS/SNI/pin/access checks; native real managed-account TLS faults; VM positive TLS loading | External handshake/network and every L2 TLS fault combination |
| T-13 | L1 configured/applied failure paths; native selected applied/publication EROFS compensation | Every node/applied write-failure position through real VM deployment |
| T-14 | Native actual outer deadline failure, full compensation and clean retry | All late health/deadline timing interleavings |
| T-15 | L1 and bounded tmpfs uncertainty/candidate ENOSPC; native uncertainty-create EROFS; VM candidate-create/rename EROFS, candidate-write EFBIG and real ext4 candidate ENOSPC with full compensation/retry/reboot | Other whole-deployment storage/commit positions, full inode exhaustion on VM and physical media behavior |
| T-16 | L1 and actual VM post-durable-commit journal append EROFS preserve install0, valid marker and normal lifecycle/reboot | Other derived logging/cleanup failures and real-device media behavior |
| T-17 | L1 marker corruption/uncertain publication; native post-rename CLI stop; VM retained marker+uncertainty after abrupt stop | All corruption/fsync/device-failure positions and physical media behavior |
| T-18 | L1 foreign file/applied metadata drift retention without blind rollback | Every independent-VM external-edit race |
| T-19 | Native actual TERM/SIGKILL slices; VM SIGKILL of owned QEMU at observed publisher window, same-disk new-kernel refusal with torn journal | Other VM interruption points and physical power loss |
| T-20 | L1 actual flock; native independent lock holder refuses apply/links without mutation | Every install/apply/reader scheduling interleaving |
| T-21 | L1 old/unknown schema, unsafe paths/fields and read-only inspection boundaries | This L1 item does not imply safe execution of arbitrary records |
| T-22 | Native distinct-version startup/publication/TERM/SIGKILL slices; VM update/checksum/rollback/swap and paired previous-state reboot | Remaining commit/storage failures and abrupt-VM update/rollback positions |
| T-23 | L1 malformed/untrusted archive and resource-budget refusal before candidate execution | Arbitrary executable safety is excluded by trusted-input policy |
| T-24 | Native trusted restore startup/partial-publication/interruption/recovery slices; VM positive round trip then reboot | Abrupt-VM restore and all remaining storage positions |
| T-25 | Native real per-Core lifecycle/update/rollback success and selected recovery failures; VM positive lifecycle/update/reboot | Every failure combination on the independent kernel |
| T-26 | Native external service restart and VM actual new-kernel reboot with stale URI suppression and validated per-Core reconfirmation | External client traffic is a separate assertion |
| T-27 | Earlier private real-Core/local-client evidence remains a separate layer | L3 external dual-protocol clients/targets are unavailable; not accepted |

No row closes an unexecuted position merely because a unit suite, successful
commit or positive VM run passed. Deployed-source identity G-01 remains blocked
without an authorized target; other supported distributions and the remaining
storage/fault positions remain unverified. Phase3 and release acceptance are not
complete. The independent review agent remains usage-limited; later increments
have self-review and executed checks, not independent review approval.

## Acquisition refusal regression and final gates — 2026-10-25

The matrix audit identifies three missing explicit L1 refusal assertions. Add
partial curl failure and checksum mismatch tests that require the exact69/78
classes, confirmed fixture invocation, absent final payload, removed private
candidate and an unchanged unrelated sentinel. The curl executable is a local
controlled stand-in, not a real upstream failure. Real unzip rejects a non-ZIP
response78 without emitting a staged executable or changing its input archive.
These tests pass6/6 assets and11/11 staging, and add3 cases to the full baseline.

`/var/tmp/pnm-acquisition-gates.0ob38zfp` final static gates and `make check`
pass0:31 suites,394 cases,0 failures. The first snapshot omitted the repository's
.shellcheckrc and fake-command executable mode; its static failure and383/11 full
result are invalid fixture evidence, retained in the earlier logs. Correct the
snapshot using the unchanged tracked ShellCheck configuration and exact Git
file modes, without modifying product code or adding disabled lint rules. The
final full runtime matches the working tree except a subsequent comment that
identifies the existing extracted backup-fixture source to ShellCheck. After
that annotation, staging11/11 and standalone ShellCheck for both changed test
files pass; no runtime statement differs from the full passing snapshot.
Final current-worktree static gates pass,43 local documentation paths resolve,
all27 matrix IDs occur exactly once, and a fresh host NSS/dpkg comparison matches
the pre-tooling baseline.

The T-01–T-27 reconciliation above and the acceptance-plan status now distinguish
selected native/VM evidence from the complete L2/L3 matrix. All protected images,
failed-run evidence and unrelated untracked cache are retained. No VERSION,
production service, firewall, host package installation, push, tag or release is
changed by this increment.

## T-16 real committed-progress append refusal — 2026-10-25

Continue the already authorized storage/commit acceptance with the existing
publisher, transaction engine and private VM. The
[bounded plan](superpowers/plans/2026-10-25-commit-progress-refusal.md) isolates
only install's CLI mount namespace and observes the final directory-sync return
after uncertainty removal. A read-only bind of its owned regular journal makes
the actual caller Bash append fail EROFS; product fsync/rename/unlink and service
functions are not replaced. Parent mount identity/propagation and exact bind
identity are checked; parent mounts must remain unchanged when the CLI exits.

The host guard first fails for the missing helper at
`pnm-progress-refusal-red.171uw683`. A focused real-directory-fsync observer test
then reproduces a missing return event at `pnm-progress-trace-red.e8zxfuwx`:
Python tracing must retain a local callback for the sync_directory call in order
to observe its return. The corrected observer keeps that callback only for the
real stdin function. `pnm-progress-final-preboot.22sscryq` passes21 guards and
compiles23 integration sources plus the2 private operators; static checks also
pass in `pnm-progress-preboot.bclu9nmo`. The existing warning is on stdout, while
the kernel append refusal is on stderr; the assertions retain that CLI contract.

Fresh `/var/tmp/pnm-vm-boot-volume.q9afkgcu` passes the real T-16 refusal and
normal14-case lifecycle, then7 same-disk reboot checks. Install returns0 with
the committed-progress warning and actual read-only-file-system refusal. The
authoritative marker passes the real product verifier, uncertainty is absent,
and the journal ends COMMIT_INTENT without COMMIT or rollback events. Both real
Core generations remain applied-bound; subsequent links/check/restart/apply and
trusted backup/restore succeed. Reboot preserves resources, withholds stale
links through ordinary restart and reconfirms each Core independently. Guest
poweroff/QEMU0, parent-mount equality and host NSS/dpkg equality pass. Full2GiB
encrypted image readback now matches its original digest, loop is detached,
QEMU is quiescent and cleanup is empty. Product Bash has no diff from the
verified source baseline; the default31/394 result remains the prior full run,
not a new full-suite run for this integration-only increment.

The automatic WSL approval review initially fails because of its own usage
limit; that command does not execute. After the user's renewed continue request,
the same command passes the original approval path and executes. No approval
check is bypassed. The independent code-review agent still reports its usage
limit; this increment records self-review and actual checks, not independent
approval. This slice does not establish real-device EIO or physical power loss.

## T-15 actual marker rename refusal — 2026-10-25

After committed-progress refusal is committed as `e07d3d2`, continue the
[rename refusal plan](superpowers/plans/2026-10-25-marker-rename-refusal.md).
Extend the existing publisher helper with an explicit rename variant; its
default pending-creation variant and all ordinary fault callers retain their
mapped-guest guard. Only the explicit variant uses the already approved VM
publisher guard, passed through readonly-bind/unmount so mount cleanup keeps
the same boundary. No production transaction or file API is changed.

The new variant host guard fails before implementation at
`pnm-marker-rename-red.hx8owab8`. Candidate timing regression additionally
requires no activation for the empty mkstemp file or an open stream, even when
the older pending-file stream is already closed. It arms only after candidate
write/fsync/close. Preboot `pnm-marker-rename-preboot.5e_7w7nh` passes23 guards,
23 integration Python compilations plus2 operator compilations and static gates.

`/var/tmp/pnm-vm-boot-volume.36t5df2a` now observes actual os.replace EROFS with
its exact temporary source and commit.env destination, publisher73 and CLI73.
Only the publisher's private namespace has the late read-only directory bind;
its owned mount is removed before the caller continues. There is no marker;
persisted uncertainty is retained for forensics. Actual compensation restores
original resource bytes/metadata, NSS, directory identities, absent units and
applied state, with ROLLBACK_COMPLETE/ROLLED_BACK and no COMMIT or recovery error.
The real next install recognizes that completed rollback and succeeds without
deleting or repairing the retained uncertainty. Normal14-case lifecycle and7
same-disk reboot assertions pass. QEMU0/poweroff, host-database equality and
parent-mount checks pass. Full2GiB encrypted image readback matches its original
digest, loop is detached, QEMU quiescent and cleanup empty. The stage preserves
all failure evidence. Other marker creation/write faults and physical media remain
separate. Independent review remains usage-limited; validation is self-review
and executed checks, not independent approval.

## T-15 actual candidate creation/write refusals — 2026-10-25

Continue after rename refusal commit `c859ea5` using the
[candidate refusal plan](superpowers/plans/2026-10-25-marker-candidate-refusal.md).
The same publisher-only private namespace and fixed approved-guest guard now
cover explicit candidate create/write variants. Creation arms the existing
read-only bind at the actual tempfile.mkstemp call, before any candidate exists,
then observes its real EROFS. Write validates the exact empty root0600 candidate
FD/inode and changes only the publisher subprocess's soft RLIMIT_FSIZE to0,
preserving its hard limit and Python's existing ignored SIGXFSZ policy. The
real write/flush raises EFBIG. Original limits must restore before evidence is
written; parent limits and mounts remain unchanged. No product file API or
transaction callback is replaced. EFBIG does not establish physical ENOSPC/EIO.

RED `pnm-marker-candidate-red.ar0ulmg6` records the missing explicit variant and
unimplemented write-limit observer. GREEN `pnm-marker-candidate-green.0lt_ll1p`
passes25 guards including actual child EFBIG/restored soft+hard limits; final
preboot `pnm-marker-candidate-preboot.aiff_uyf` passes26 guards including exact
pre-mkstemp activation,25 integration/operator compilations and syntax/security/
ShellCheck. An earlier RED invocation was rejected for approval-review usage
capacity; after the user renewed continuation, the identical escalation path
executed successfully. No alternate execution path bypassed that review.

`/var/tmp/pnm-vm-boot-volume.op1m0hdn` passes all three actual faults in order:
candidate creation EROFS, candidate write EFBIG and the established rename EROFS.
Each returns original publisher/CLI73, preserves uncertainty without marker,
fully restores original resources/NSS/directory metadata and identities, absent
units/applied state, and ends ROLLBACK_COMPLETE/ROLLED_BACK without COMMIT or a
recovery error. Each next attempt and the normal14-case lifecycle succeed
without repairing/deleting retained transaction evidence. The same disk then
passes7 independent-kernel reboot assertions, clean guest reboot/poweroff and
QEMU0. Host database comparisons and parent mount/limit checks pass. Its D-backed
export subsequently fails actual EIO at encrypted-output write/flush; no complete
image readback is claimed for that run. The incomplete ciphertext and protected
failure receipts remain intact. After raw retirement, Windows and WSL both show
only2,147,426,304 bytes free on D; an owned1MiB write/fsync/readback passes. This
is an operator storage-capacity incident, not a PNM transaction or physical-media
failure result. No filesystem repair, remount or existing-data cleanup is done.

Recheck C at4,761,964,544 bytes free, then use only the exact root0700 `image`
child of this run's root0700 canonical Linux control directory. The operator
still rejects other output paths; three focused path-guard cases pass. Fresh
`/var/tmp/pnm-vm-boot-volume.smlq1v57` repeats all3 faults, normal14 checks and7
same-disk reboot assertions successfully. Full2GiB encrypted image readback
matches its original digest, both QEMU runs are quiescent, loop is detached and
cleanup empty. Final `pnm-marker-candidate-final.sco0sk7e` passes26 guards,
25 compilations, static gates and17 document paths. A later transport stage's
unstaged changes are excluded from this commit and these26-guard results.
Production Bash remains unchanged since `292b682`;31 suites/394 tests is the
existing full baseline, not a newly run full suite for this test-only increment.
Independent review remains unavailable by usage capacity; these results are
self-review and executed validation, not an independent approval.

## T-03 actual update transport refusals — 2026-10-25

After candidate marker acceptance commit `6261a8b`, continue the
[transport refusal plan](superpowers/plans/2026-10-25-asset-transport-refusal.md).
Reuse the guarded loopback HTTPS CONNECT fixture, pinned asset bytes and real
curl/update path. No product download API, exit status or system trust store is
replaced. An explicitly selected allowed asset path sends a short body against
the true Content-Length and then TLS close_notify. Each Core must observe real
curl18/update69. With the guest's unchanged public CA bundle, its fresh private
fixture certificate is untrusted: require curl60/update69, exactly one budgeted
unknown-CA server alert and no HTTP GET. Other TLS/server errors still fail.
The server's bounded connection budget becomes10 for the maximum two-Core
fault/retry scenario; owned socket retirement and thread joins remain bounded.

Meaningful RED `pnm-asset-transport-red.y27zefj_` fails on missing partial_paths;
the earlier wrong test selector is not feature RED evidence. Initial GREENs
retain their actual failures: abrupt TLS close did not produce HTTP partial18,
and curl's post18 close omitted a reciprocal close_notify. The fixture now
sends its proper close_notify and accepts only the precisely observed
UNEXPECTED_EOF_WHILE_READING during that selected partial shutdown, leaving
other errors authoritative. `pnm-asset-transport-green.ofm5k3uc` passes all27
guards including real curl0/18/60 and subsequent normal retrieval in a separate
network namespace, with no retained sockets/threads. Preboot
`pnm-asset-transport-preboot.11_2dbrr` passes25 Python compilations and static gates.

Fresh `/var/tmp/pnm-vm-boot-volume.c09hq622` passes normal14 lifecycle and12
actual update assertions: each Core's partial/trust/checksum refusal, distinct
version update, rollback and swap forward. The two new refusals preserve full
Core and peer resources, previous pairing, applied evidence and InvocationIDs,
create no publication transaction and leave no new temporary download directory.
Only fixture transport settings are restored before the successful real update;
no runtime/persisted PNM state is repaired. All7 same-disk independent-kernel
reboot assertions pass, including paired previous version metadata, stale-link
withholding and explicit rebind with peer preservation. Both QEMU runs exit0
with actual reboot/poweroff, are quiescent, and the loop is detached. Full2GiB
encrypted image readback matches the original digest, cleanup is empty and a
fresh host NSS/dpkg hash comparison equals the pre-tooling baseline. All18
document paths pass. This is controlled
update acquisition evidence, not first-install acquisition/ZIP or upstream outage
acceptance. Independent review remains usage-limited; this is self-review and
executed validation. The existing31/394 full Bash baseline remains distinct.

## Bounded candidate ENOSPC publisher slice — 2026-10-26

Continue after transport acceptance commit `08630bc` with the
[bounded storage plan](superpowers/plans/2026-10-26-bounded-commit-enospc.md).
Fresh Windows checks show only C/D volumes, C=2,049,884,160 and D=2,146,570,240
bytes free, so the existing2GiB VM plus ciphertext/margin remains blocked.
No retained evidence is deleted. A new explicit `make test-commit-storage`
target uses only a64KiB/64-inode tmpfs with nodev/nosuid/noexec in each owned
child mount namespace. Default `make check` still performs no mounts.

The original deployment marker Bash helper and its stdin Python publisher run
unchanged against synthetic root0600 transaction records. A scoped interpreter
observer fills only that tmpfs immediately before actual candidate mkstemp or
write/flush. No file API/result or product program is replaced. Each actual
ENOSPC28 produces publisher73, preserves the complete pending record and original
record bytes, removes the incomplete candidate and never publishes commit.env.
The exact owned tmpfs is unmounted; parent namespace/mount table and host primary
NSS/dpkg hashes are checked unchanged. This is a Linux publisher-only slice,
not complete deployment compensation, independent-kernel or physical media proof.

Meaningful host-refusal RED `pnm-bounded-storage-red.d4plgzfj` fails before the
fixture module exists. `pnm-bounded-storage-final.138tyvnl` passes both actual
refusals (56 bounded inode allocations,13 bounded block writes),28 guards,
24 Python compilations and syntax/security/ShellCheck. Additional
`pnm-bounded-storage-refusals.vkf1dz2s` and `pnm-bounded-entry-refusals.ymgvrs39`
prove missing opt-in, actual nobody and optimized-Python entry refusals before
storage mutation, rather than successful skipped explicit checks.

The first full source copy at `pnm-bounded-full.99nobvbg` was under the root0700
log directory, so nobody could not read bin/pnm and the real non-root diagnostics
case failed before its intended policy checks. This is a test-operator layout
error, not a product change. Keep that failed run. A separate trusted public
source copy retains Git executable modes and .shellcheckrc; logs stay root0700.
`pnm-bounded-full-corrected.omxdc7dv` first passes the unchanged read-access case,
then fresh `make check` passes all31 suites/394 tests and28 guards pass.19 document
paths pass. Independent review remains usage-limited; validation is self-review
and actual execution. Product Bash, VERSION and production services are unchanged.

## Bounded uncertainty-file ENOSPC — 2026-10-26

After commit `4078e75`, continue the
[uncertainty ENOSPC plan](superpowers/plans/2026-10-26-pending-enospc.md).
The same64KiB/64-inode publisher-only fixture now observes two earlier original
operations. Before pending os.open, inode exhaustion causes real ENOSPC73 and
leaves no pending file. At its validated empty root0600 FD, block exhaustion
causes real ENOSPC73 and leaves an empty incomplete pending file. Neither may
publish a marker/candidate or alter original record bytes. Report absent/empty/
complete states explicitly; the empty file is not claimed durable uncertainty.
The existing candidate create/write cases still require complete pending bytes.

RED `pnm-pending-storage-red.t92zj6b_` fails both new unsupported phases with77.
GREEN `pnm-pending-storage-green.4c05vhie` passes all4 actual kernel refusals,
including57 bounded inode allocations for pending creation and14 bounded block
writes for pending write, plus28 guards. Every own tmpfs is retired; unchanged
parent mount table/namespace and host primary NSS/dpkg hashes are required.
This remains synthetic-record publisher evidence, not outer deployment recovery
or independent-kernel storage fault acceptance. Product Bash stays unchanged;
the immediately preceding fresh31-suite/394-test full baseline is preserved and
is not described as a second full run for this test-only extension.

Self-review identifies that a supplied parent namespace number alone is not
proof of the actual parent boundary. Wrong-number RED
`pnm-storage-parent-red.ygcq6jxd` bypasses that comparison but is still stopped by
the host propagation check; mutation controls are forbidden by the regression,
so no host mount occurs. The guard now requires the supplied number to match
the live parent's /proc/PID/ns/mnt and the worker's namespace to differ, before
any directory/mount operation. `pnm-storage-parent-green.39wbf1nm` passes all4
real ENOSPC cases,28 guards, the actual nobody guard,24 Python compilations and
syntax/security/ShellCheck.20 document paths pass. Independent review remains
unavailable by usage capacity; the boundary is self-review and execution.

## Independent VM real ext4 ENOSPC recovery — 2026-10-26

After commit `d2712d1`, fresh Windows C capacity recovers to4,059,680,768 bytes,
and a preboot recheck confirms4,040,536,064. No prior evidence is deleted. Continue
the [VM disk-space plan](superpowers/plans/2026-10-26-vm-commit-enospc.md) in the
existing2GiB independent VM using its exact protected Linux output path.

The explicit new space publisher variant requires this boot's approved VM guard;
host/container routes refuse before allocation. It verifies root ext4 /dev/vda,
at most2GiB filesystem, protected root0700 evidence and an anonymous root0600
filler on the transaction's own filesystem. At the actual empty candidate FD,
bounded fallocate operations exhaust available VM blocks. The unchanged original
publisher encounters actual ENOSPC28 and returns73. Only the owned anonymous
filler is closed; available blocks must recover before evidence is recorded and
the real CLI proceeds with compensation. No limits, file APIs, publisher stdin
or transaction resources are substituted.

Meaningful host-refusal RED `pnm-vm-space-red.ycn5vm3q` precedes implementation.
Preboot `pnm-vm-space-preboot.3n5tg1w4` passes29 guards,4 bounded tmpfs regressions,
27 integration/operator Python compilations and static gates. Actual independent
VM `/var/tmp/pnm-vm-boot-volume.5nul5yug` now passes original publisher/CLI73,
retained pending/no marker and complete original resource/NSS/directory/unit/
applied compensation with terminal rollback. Without state repairs, normal14
lifecycle checks and7 same-disk reboot checks pass. QEMU exits0 with actual
guest reboot/poweroff, both runs are quiescent, loop is detached and cleanup empty.
Full2GiB encrypted image readback matches the original digest. Fresh host NSS/dpkg
hashes equal the pre-tooling baseline and all21 document paths pass.
This closes the selected candidate-write virtual ext4 space refusal, not other
commit positions, physical EIO, deployed identity or external-client acceptance.
The recent31/394 full Bash result remains separate from this test-only increment;
independent review is still unavailable, so review is self-review and execution.

## Independent VM first-install acquisition refusals — 2026-10-26

After ext4 recovery commit `b81600d`, continue the
[first-install acquisition plan](superpowers/plans/2026-10-26-install-acquisition.md).
C capacity remains3,935,350,784 bytes before launch. The VM-only fixture reuses
the exact bounded HTTPS server and approved current asset bytes. Hold only the
verified subject cache inode in protected evidence to force acquisition; retain
the peer cache and refuse to overwrite any unexpected cache destination on
fixture restoration. No curl, staging function or CLI result is substituted.

Host-refusal RED `pnm-install-acquisition-red.9v1skdjc` precedes implementation.
Preboot `pnm-install-acquisition-preboot.n64_bkyj` passes30 guards,28 integration/
operator compilations and static gates; the subsequently added account-receipt
assertion is compiled before VM preparation. Actual
`/var/tmp/pnm-vm-boot-volume.wirimd90` passes all7 negative first installations:
curl18 partial-body and curl60 untrusted private fixture CA each return69 for
each Core; checksum refusal returns78 for each; a hash-approved non-ZIP Xray
body reaches verified cache and real unzip/staging, returning78. The ZIP case
also proves4 actual owned identity APPLIED/RESTORED pairs. All cases preserve
authority and primary NSS bytes/mode/UID/GID, original directory identities and
unit baseline, absent runtime/applied/commit/uncertainty, peer/held cache and no
temporary candidates, with original outer terminal rollback and no recovery
error. Safe receipts and the invalid ZIP cache remain for forensics.

Only the declared test approval pins, transport and original cache fixture are
restored before the normal14-case lifecycle; no runtime, service, NSS or
transaction repair is performed. The same disk passes7 independent-kernel reboot
checks, actual guest reboot/poweroff and QEMU0, full2GiB encrypted readback with
matching digest, quiescent QEMU, detached loop and empty cleanup. Fresh host NSS/
dpkg hashes equal the tooling baseline and22 document paths pass. This is controlled
acquisition evidence, not upstream outage or arbitrary executable safety.
The recent31/394 full Bash result remains separate; independent review is still
usage-limited, so review is self-review and actual execution.

## Immediate next steps

Selected abrupt-VM recovery is committed as `1f68c03`. The follow-on G-03 slice
reuses the existing verified prior/current Core assets and private loopback HTTPS
transport for checksum refusal, actual distinct-version update, rollback and swap
forward. Its separately approved VM route preserves the original mapped guest
guard and does not enable container-only startup/account/mount fault helpers.
Reboot baselines now retain previous/previous.env fingerprints and compare each
trusted previous binary's actual version with its metadata before/after reboot.
`pnm-vm-update-preboot.zgepo12i` passes18 guards,22 integration compilations and
static checks. The additional actual-version pairing regression passes with
the19-guard suite at `pnm-vm-update-final-guards.0t7xz72w`, including rejection of
mismatched metadata for each Core without modifying it. Fresh
`/var/tmp/pnm-vm-boot-volume.eq48angk` passes14 lifecycle +8 distinct-version
update/checksum/rollback/swap checks and7 same-disk reboot checks. Both paired
previous files persist with unchanged fingerprints and actual version/metadata
agreement; stale links stay withheld through ordinary restart, independent apply
reconfirms bindings without changing the peer, and both listeners are observed.
Normal guest-requested reboot/poweroff and QEMU0 pass. Full2GiB encrypted image
readback matches the original digest, QEMU is quiescent, loop detached and cleanup
empty. A fresh host NSS/dpkg hash comparison also matches the pre-tooling
baseline. Production Bash remains unchanged since `292b682`;31/391 is the
existing full baseline, not a fresh full-suite run for this test-only increment.
Independent review is still unavailable; self-review and actual checks are
recorded separately.

Startup readiness/harness and initiating-error repairs are committed as
`ce6713f`, `0bee0d8`, and `580ead7`. Fresh native fault cases now complete the
recovery-required plan. TLS access, valid-account reuse and per-Core process
interruption now also pass. Ordinary restart's forward readiness gate is repaired.
All19 declared prerequisite tools and first-deployment Core startup failures now
pass real checks. Actual post-health listener absence now passes as well.
Update/rollback and restore startup interruption now pass. Native transient
previous binary/metadata/applied publication failures and partial restore EROFS
also pass. Native publisher EROFS, late post-rename SIGKILL and all four account
tool refusal slices now pass as recorded above. Continue the
[independent Debian VM plan](superpowers/plans/2026-10-25-independent-debian-vm.md):
private authenticated tools/initramfs and the independent boot-only slice now
pass, including clean poweroff and full encrypted image verification. Continue
with the remaining matrix audit; real PNM lifecycle and same-disk guest-requested
reboot pass14+7 checks, and the selected abrupt-VM pending-commit slice now passes.
Persistent storage, remaining fault positions and
deployed-host/external-client prerequisites stay separate. The earlier cleanup
proposal is unnecessary; all original roots are retained.
Successful main flow, update/rollback and late-deadline compensation cannot replace
the following VM/reboot, deployed-host and external-client prerequisites.

1. Confirm deployed PNM source identity for G-01 using read-only checks when an authorized target is provided; none is currently available.
2. Complete the unexecuted storage/commit positions in the reconciliation only in a disposable, controlled fault environment; do not infer physical failure behavior from the selected VM stop.
3. Record external dual-protocol client handshake/traffic when clients/targets are supplied; none is currently available and local evidence does not replace L3.
4. Keep Debian12/Ubuntu22.04/24.04 as unverified platform acceptance until their own execution evidence exists; os-release fixtures are L1 only.
5. Reassess Phase3 completion against those gates. The planned local VM stages and matrix reconciliation are complete; Phase3 as a whole is not. Do not start Phase4 or release work automatically.

Local account/lifecycle acceptance can now continue in the verified Debian WSL
container. Remaining external prerequisites include an authorized deployed source
identity for G-01, broader storage/commit-position acceptance,
and external clients for dual-protocol traffic. The stand-in and private-network
Core/container results do not close those external items;
Phase 3 remains incomplete and release work has not started.

**Local execution capacity history (2026-10-25):** after the final verified
transport VM is retired and its complete image retained, Windows reports
C=2,004,451,328 and D=2,147,233,792 bytes free. Both are below the2,147,483,648-byte
raw test-disk size, before ciphertext, root/tool staging or host operating margin.
Linux statvfs reports virtual ext4 capacity and must not substitute for Windows
backing-volume availability. Do not start another heavy VM/storage-fault run
under that capacity. All owned QEMU processes/loops from the completed runs are
retired; retained images/keys and the incomplete D export remain untouched.
Resume remaining first-install acquisition, storage/commit positions and other
platform work after adequate approved storage is available. No automatic deletion,
VHD compaction, disk repair or WSL restart is authorized by this checkpoint.

**Current capacity gate (2026-10-26):** later physical C availability recovers
to about4GB without this task deleting retained data. The selected real ext4
ENOSPC VM then completes with verified image and cleanup as recorded above.
Recheck physical backing-volume availability before every additional heavy run;
Linux virtual capacity alone is insufficient. Use only the exact owned Linux
output directory, one VM at a time, with space for the disk, ciphertext and host
margin. Retained evidence and the earlier incomplete D export remain untouched.

## Boundaries

The user explicitly requested review and a local Git commit, reconfirmed by continuing the task on 2026-10-23. Production apply/update/restore, SSH/Tailscale/UFW/cloud firewall changes, version changes, push, tags and releases remain outside this task's authorization.
