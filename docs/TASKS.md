# PNM Current Tasks

**Updated:** 2026-10-29. **Phase 3 bounded Debian/Ubuntu acceptance remains pending.
Phase 4 installed-node Profile main flow is basically complete; real systemd
acceptance is pending. Phase 5 local observability is implemented with passing
local gates; optional external checks remain deferred.
Phase 6's scoped recovery diagnostics are implemented with passing local gates;
firewall management remains manual. Phase 7 local regression/release preparation
is complete; current amd64/arm64 Ubuntu and Debian userspace CI pass; full real acceptance remains pending. No release
has been published.**

**Published runtime baseline:** branch `dev`, source commit `3d6ac5b`, VERSION
`0.16.0-rc.1`. Includes the dual-Core lifecycle, installed-node Profiles, optional
resource/status observations, sanitized recovery diagnostics, native architecture
asset/digest selection and amd64/arm64 CI.
Earlier records below remain specific to their own sources and execution layers.

## Continuation checkpoint

- Expanded cloud acceptance (2026-10-30 UTC): user authorized the recommended
  next steps, then explicitly separated public dual-protocol acceptance. The
  managed-installation workflow now selects eight native OS/architecture pairs
  automatically (max four concurrent) or a dispatch-selected subset. The existing
  lifecycle gains a real dual→reality→hy2→dual cycle with unchanged-peer/resource
  assertions, a real HY2 UDP bind failure/compensation/retry, and invalid-candidate
  admission refusal. It adds five checks to the prior14; VM lifecycle counts
  follow the same shared19-check baseline. No production CLI change is included.
  Native cloud execution is pending; local preparation guards40 total/32 executed/
  8 skipped and workflow/Bash/Python checks pass. VM reboot integration is next;
  public endpoint provisioning/client tests remain separate by user instruction.
- Cloud root-cause closure (2026-10-30 UTC; 2026-10-29 workspace date):
  fixed source `2e927a29addf475df0ff4b2fd818eb9cdedc6d71` passes
  [managed-installation run40997253783](https://github.com/mrshyi/pnm/actions/runs/40997253783),
  job123873139880, Debian13 amd64/lifecycle. The real export log confirms
  template root mode0700 before normalization to0755. The parent evidence
  directory remains0700. Rootfs was initially created0700 and Docker export
  did not supply a root entry to correct it; unprivileged Core services could
  not traverse `/`. Earlier cloud diagnostics showed Xray post-health FAIL,
  permission_denied and rollback. This was a test-template permission defect,
  not an amd64/ARM64 asset or PNM platform-guard defect.
- The fixed cloud boot-only and lifecycle clones both report root0755,
  manager running, mapped non-host-root UIDs, private namespace/network and
  approved owned cgroup/payload boundaries. All14 existing lifecycle checks
  pass: fresh baseline, actual node init/validate and preview, real dual-Core
  installation/commit, distinct service identities and bounded privileges,
  config/InvocationID applied bindings, URI readiness, Core/TLS health,
  repeat-install refusal, each Core restart and apply preserving its peer,
  trusted protected backup/restore with real bindings and damaged-package refusal.
  No recovery-required flag remains in the successful scenario. Both clones
  exit0, retire their exact scopes/mounts and leave host account/package database
  hashes unchanged. Product files32 retain manifest4e2c718e5391d02c573d9cd771fa26299641a880398dcc44185c4aa6fcc4de98
  across the failing and passing runs: production validators/permissions/code
  were not weakened or modified. Only harness diagnostics and fixture mode changed.
- Fresh local guard regression:40 total/32 executed/8 root-only skipped,
  exit0; synthetic export verifies root0700 becomes0755 while its parent stays
  private0700. Builder ShellCheck0.8.0, syntax, security/release scans and diff
  checks pass. A prior diagnostic commit b0faa98 missed the extracted timeout
  fixture's new helper dependency;2e4d3cf fixed the fixture, and39 guards then
  passed before the subsequent cloud diagnostic commits. No production behavior
  was changed for that test correction. The latest regular eight-job
  [CI40997254129](https://github.com/mrshyi/pnm/actions/runs/40997254129)
  was still running at this checkpoint; no final result is claimed.
- Remaining acceptance: this successful pilot is only Debian13 amd64/
  selfsigned lifecycle. Other OS/architecture deployment combinations, the
  distinct-version update/four fixed failure scenarios, external-ca variants,
  actual Profiles, installed CLI wrapper/uninstall, VM reboot and public clients
  remain unaccepted. Do not turn14 checks or local ready URIs into those claims.
  The development host was not used for dependency/image preparation or deployment.
- Cloud failure investigation (2026-10-29): continuing the authorized isolated
  CI pilot after source751634a failed install apply78. The retired runner's
  private logs are unavailable, so the existing guest call wrapper now adds
  only fixed error categories and allowlisted transaction steps/exit codes to
  its bounded public result. No raw stderr/journal, credentials, config, paths
  or links are emitted. The final assertion distinguishes boot from selected
  mainflow failure; isolation/production validators remain unchanged. Rerun the
  same Debian13 amd64/lifecycle pilot before broadening scope; no development-
  host installation or production mutation is part of this investigation.
- Online verification (2026-10-29), exact source
  `751634ac7bd0bb5dfb23eb8c6cc65947f6da33d6`: regular
  [CI40973033072](https://github.com/mrshyi/pnm/actions/runs/40973033072)
  completed successfully on all eight native OS/architecture jobs. Each job
  passes check/release separately35 suites/475/0 and privileged70/0, ShellCheck,
  preparation38 total/30 executed/8 skipped and transport7. All four Ubuntu
  jobs additionally pass temporary real systemd8 and pinned real-Core10; all
  Ubuntu78 / Debian76 shell summaries have zero failures. Repeated gates do
  not increase unique coverage; the five ordinary root-only skips remain explicit.
- The separate [managed-installation pilot40973033155](https://github.com/mrshyi/pnm/actions/runs/40973033155),
  job123794195597, completed FAILURE. Official Debian13 amd64 template
  acquisition/package setup/export succeeded. The boot-only clone passed real
  systemd startup, mapped non-host-root UID, namespace/machine/root identity,
  live unified cgroup scope/payload approval and safe shutdown. A second clone
  passed the same isolation boundary, fresh-resource baseline, actual node
  initialization/validation and installation preview. Actual install apply
  then returned78; guest result passed=false at stage "installation apply".
  No complete managed installation, subsequent lifecycle, compensation/retry,
  Profiles, reboot or public clients are accepted from this run. The driver's
  final generic "guest boot was not confirmed" assertion does not negate the
  separately successful boot-only result or identify the install root cause.
- Both clone reports confirm host account/package databases unchanged,
  scope_after=not-found, no remaining fixture mounts and nspawn exit0. The
  workflow correctly failed instead of emitting public success metadata.
  Its private install stdout/stderr/service journal were intentionally not
  uploaded; the public artifact contains only identity, template and packages.
  Exit78's specific validator/failure cause cannot be determined from available
  online evidence. Next action: capture a bounded sanitized failure phase/code
  through the existing harness, then rerun this exact lifecycle pilot before
  broadening combinations. Do not dump private journals/configuration/links.
  No implementation change or Git commit/push accompanied this verification.
- Automated environment preparation (2026-10-29, delivery candidate based on3d6ac5b):
  the user authorized preparing disposable environments through existing CI/
  harness facilities. A separate managed-installation workflow prepares an
  allowlisted official native Debian/Ubuntu rootfs, retaining image IDs/digests
  and public package versions; APT setup occurs only inside its normal owned
  build container. Existing nspawn guards then verify a boot-only clone before
  publishing the template's boot receipt and running the existing CLI scenario.
  No parallel transaction framework or new fault scenarios were added. Hybrid
  guards are retained; unified cgroup views must be confined to the same owned
  scope/payload. Clone policy-rc.d is verified against the original template
  before removal, replacing the missing clone-local receipt assumption.
  The first automatic pilot is Debian13 amd64/lifecycle. Dispatch definitions
  expose the other native OS/architecture choices and eight existing bounded
  scenarios; none is claimed executed yet. This removes manual fixture supply
  as the planned prerequisite for that pilot, but actual CI boot/install success
  remains pending. VM reboot, real Profiles and public clients remain unverified.
  No packages/images were installed/pulled, containers created or services
  modified on the development host. Delivery review confirmed no blocking
  defect and the user explicitly authorized commit/push. Fresh submission
  checks repeat38 preparation guards (30 executed/8 skipped),2 Core guards,
  workflow/Python structure, Bash syntax/ShellCheck0.8.0 and security/release/diff
  scans successfully. No production business-suite rerun is claimed. The first
  online pilot remains pending; source review is not boot/install verification.
- Preparation checks: integration guards38 total/30 executed/8 root-only
  skipped, exit0; real-Core refusal/native-manifest guards2/2, exit0. New
  builder and extracted workflow Bash steps pass syntax and ShellCheck0.8.0;
  BaseLoader validates four OS choices, two native architectures, eight existing
  scenario choices and contents-read token scope. Changed Python parses cleanly;
  make syntax/security-scan, release scan and git diff checks exit0. No475-case
  production suite rerun is claimed for this harness-only change. Actual image
  acquisition, boot-only confirmation and CLI lifecycle remain pending the
  first online pilot. Preparation guard log: `/tmp/pnm-auto-guest-guards.log`.
- Debian deployment/acceptance alignment (2026-10-29): the user added full
  Debian12/13 deployment to the same finite contract as Ubuntu22.04/24.04,
  for native amd64 and arm64 independently. U-01–U-08 and the release checklist
  keep their IDs and fixed faults; there is no new implementation or failure
  matrix. Full Debian acceptance is in scope, not automatically deferred.
  Current source3d6ac5b has passing userspace CI on all eight combinations;
  only Ubuntu has the selected real temporary systemd/Core CI evidence.

  | OS | Architecture | Repository/userspace CI | Selected real systemd/Core | Full deployment/Profile/reboot/external client |
  |---|---|---|---|---|
  | Debian12 | amd64 | PASS | BLOCKED | BLOCKED |
  | Debian12 | arm64 | PASS | BLOCKED | BLOCKED |
  | Debian13 | amd64 | PASS | Managed lifecycle14 PASS; separate protocol suite pending | Lifecycle14 PASS on2e927a2; remaining acceptance pending |
  | Debian13 | arm64 | PASS | BLOCKED | BLOCKED |
  | Ubuntu22.04 | amd64 | PASS | PASS | BLOCKED |
  | Ubuntu22.04 | arm64 | PASS | PASS | BLOCKED |
  | Ubuntu24.04 | amd64 | PASS | PASS | BLOCKED |
  | Ubuntu24.04 | arm64 | PASS | PASS | BLOCKED |

  PASS applies only to source3d6ac5b and the recorded CI layer. Missing approved
  disposable native root/systemd/reboot targets, verified fixture/asset setup
  and external clients prevent full execution. Debian must also run the existing
  systemd/Core integration on an approved target before complete U-01 PASS.
  No installation, target provisioning, dependency installation or reboot was
  executed for this documentation alignment. Earlier Debian deferral records
  below describe prior scope, not the current contract.
- Pre-release acceptance checklist (2026-10-29): consolidated the executable
  release decision/checklist in [RELEASING](RELEASING.md), reusing U-01–U-08.
  It separates candidate/CLI delivery, actual Profiles and diagnostics, external
  protocol transfer and normal uninstall exit checks; no extra fault matrix is
  introduced. All eight Debian/Ubuntu OS/architecture targets execute the same bounded
  checklist independently after the Debian alignment above; full acceptance
  cannot be claimed from container CI. No new acceptance run, deployment, version/tag,
  commit/push or release is implied by the checklist.
- Dual-architecture CI verification (2026-10-29): source
  `3d6ac5b4e231363ad33da1b58034e64e9061fb7f`, push/attempt1,
  [run40936099974](https://github.com/mrshyi/pnm/actions/runs/40936099974)
  completed successfully on all eight jobs. Actual ARM64 logs report aarch64.
  No runtime/test correction was required after delivery.

  | Environment | amd64 job | arm64 job | Result |
  |---|---|---|---|
  | Ubuntu22.04 |123666935765|123666935488|PASS both|
  | Ubuntu24.04 |123666935530|123666935481|PASS both|
  | Debian12 container |123666935386|123666935617|PASS both|
  | Debian13 container |123666935125|123666935554|PASS both|

- All eight jobs pass check and release-check separately:35 suites/475 passed/
  0 failed per gate. Privileged suites pass70/0 (CLI18/read1/TLS8/transaction28/
  Profile9/recovery6), with no root-section skips. All pass ShellCheck,
  preparation36 total/28 executed/8 skipped and loopback asset transport7.
  Each Ubuntu job also passes real temporary systemd8 and real-Core10, plus
  the2-test refusal/native-manifest guard. Ubuntu78 / Debian76 shell summaries
  per job contain zero failures. Five ordinary root-only skips remain explicit;
  repeated gates are not independent additional coverage.
- ARM64 Ubuntu22/24 evidence now includes verified official Xray26.10.21 and
  HY2 2.13.0 execution as nobody, production-rendered config/certificate
  validation, actual unprivileged Core startup, separate local client transfers
  for both protocols and the HY2 share-link pin. These are private network/
  temporary-unit checks. Debian12/13 ARM64 is native userspace/container-root
  evidence with PID1 tail, not real systemd boot acceptance. Profile service
  controls in privileged unit suites remain simulated.
- Full ARM64 deployment acceptance remains BLOCKED before execution: no
  verified disposable supported root/systemd/reboot target or native boot fixture
  was supplied. Rechecked workspace: UID1001/aarch64/PID1 codex, no QEMU,
  nspawn or /dev/kvm. A reviewed read-only Docker query reports an aarch64
  Ubuntu22.04 daemon, but no prepared supported test image; existing application
  images are not adopted as acceptance fixtures. No image pull/container create,
  dependency installation, managed deployment, host account/service/firewall
  change or reboot was performed. Target/fixture information was requested.
  U-02–U-08, actual Profile switching, two-version update/rollback, trusted full
  restore, reboot persistence and public external-client acceptance remain
  unverified. Reuse the existing finite checklist when prerequisites arrive;
  passing CI does not establish production readiness.
- Fresh compatibility validation: `make release-check` exits0, including
  release/syntax/security scans and35 suites/475 passed/0 failed. Five
  root-only skips remain update CLI, read access, TLS access, low-mode
  recovery and numeric ownership. Focused suites assets13/node30/archive9
  also exit0; URL/latest lookup cases exercise both architecture observations,
  and the archive fixture accepts a native ELF header while refusing foreign
  Xray/HY2 headers before candidate validation. The modified node digest fixture
  includes both architecture entries to avoid selecting the wrong hash.
  Standard ShellCheck0.8.0 and changed-shell-test ShellCheck exit0. Offline
  mainflow preparation exits0 (36 total/28 executed/8 skipped); Core refusal /
  native-manifest guards exit0 (2 tests). Native loopback TLS acquisition exits0
  (7 tests); its initial restricted-sandbox attempt could not create sockets
  (7 setup errors), then normal reviewed execution passed without product changes.
  PyYAML validates eight native jobs;20 extracted Bash steps pass syntax and
  ShellCheck, and integration Python sources pass AST syntax checks. Logs:
  `/tmp/pnm-arm-{release-check,assets,node,backup,guard,network,shellcheck}.log`.
  These local results precede the online CI above; full managed acceptance
  remains pending, while native temporary-unit/Core execution is now verified.
- ARM64 test assets: current Xray26.10.21/HY2 2.13.0 and previous Xray26.9.30/
  HY2 2.12.3 manifests record official release API URLs, sizes and SHA-256
  digests. Test loaders select the host architecture and reject foreign pins.
  This is isolated test metadata, not approval to install production assets;
  no Core assets were downloaded or executed on the development host.
- Fresh environment: UID1001, aarch64, PID1 codex; no QEMU/nspawn executable
  was found. Native L1 gates use private temporary fixtures; full root/systemd,
  reboot and external-client acceptance remains pending for both architectures.

- Delivery / CI verification (2026-10-29): reviewed, committed and pushed the
  Debian12/13 CI addition and its fixture corrections. Source
  `c6beab18aaf5039a5db434dab0af7e1f17034c3a`, branch `dev`, VERSION unchanged.
  [CI run40901377916](https://github.com/mrshyi/pnm/actions/runs/40901377916),
  push/attempt1, completed successfully on all four amd64 jobs:
  Ubuntu22.04 (123544272296), Ubuntu24.04 (123544273042),
  Debian12 (123544273032) and Debian13 (123544273308).
- Every job passes check and release-check separately:35 suites/475 passed/
  0 failed per gate. Six privileged suites pass70/0 (CLI18/read1/TLS8/
  transaction28/Profile9/recovery6), with no privileged-section skips.
  All jobs pass ShellCheck, preparation36 total/28 executed/8 skipped and
  loopback asset transport7. Each Ubuntu job additionally passes isolated
  systemd8 and pinned real-Core10. All78 Ubuntu /76 Debian shell summaries
  per job have zero failures. Repeated gates are not extra unique coverage.
  The five ordinary root-only skips remain explicit and their corresponding
  privileged cases execute in the root section.
- Debian jobs use official12-slim/13-slim containers without privileged options;
  actual identities are Debian12/13, x86_64, root and PID1 tail. Normal gates
  run as nobody in private copies excluding `.git`; root suites use private
  fixtures. Debian12 records OpenSSL3.0.22/systemd252/ShellCheck0.9.0;
  Debian13 records OpenSSL3.5.7/systemd257/ShellCheck0.10.0. No Debian real
  systemd/Core/VM target runs. Profile service controls remain simulated;
  these results do not establish full managed install, real managed accounts,
  actual Profile ownership admission, reboot or public client connectivity.
  U-02–U-08 and full Debian systemd acceptance remain pending; firewall is manual.
- CI defects found and corrected: run40898184336 (36a2eaf) stopped before
  tests on Git checkout ownership;8a8cec5 scopes safe.directory to the one
  read-only source query. Run40898436294 exposed missing deploy fixture
  systemd availability isolation;372b1da adds the existing service stub.
  Run40899468868 exposed a read-access fixture expecting permission WARN1
  while absent systemd correctly caused FAIL2;c6beab1 applies the existing
  PNM_TEST_SYSTEMD hook only to that child CLI. Assertions and production
  permission/recovery code remain unchanged. A private-copy unavailable-host
  probe reproduces deploy5/3 before and8/0 after; focused native8/0 and
  ShellCheck0.8.0 exit0. The local read-access body explicitly skips as non-root;
  the final four-platform CI executes it as root successfully. No dependencies
  installed or PNM deployed on the ARM64 development host for this work.

- Phase6 assessment / Phase7 authorization (2026-10-29): source and the separately
  recorded35-suite/475-pass gate below support basic completion of the recovery
  diagnostic scope. Manual firewall management is retained. The user authorized
  Phase7 preparation; this does not authorize release/tag/version changes,
  deployment or automatic Git mutations.
- Phase7 local preparation: add the existing Profile/recovery unit suites to the
  existing Ubuntu22.04/24.04 privileged CI step (six suites total), without new
  fixtures, scenarios or deployment commands. Profile service controls remain
  simulated; recovery uses private root-owned receipts. Add the Unreleased
  changelog and update release/contribution instructions for Profile selection,
  configured ports, separate CLI/Core installation and exact-source evidence.
  Runtime code and regression cases are unchanged from the Phase6 gate.
- Phase7 fresh checks: `tests/release-scan.sh` exit0 (including security scan);
  offline guest preparation exit0,36 total/28 executed/8 root-only skipped;
  real-Core refusal guard exit0,1/1. PyYAML6.0.3 BaseLoader validates both Ubuntu
  labels, six existing root suite commands/files, unchanged push/PR triggers and
  contents-read token scope. Ten local links/anchors in the changed release
  documents pass; external URLs were not fetched. `git diff --check` exits0.
  Logs: `/tmp/pnm-phase7.Nd88pCIv/` and `/tmp/pnm-phase7-guards.ox0oWKZU/`.
  The prior475-pass business gate and ShellCheck results were not rerun or counted
  as fresh checks for this documentation/workflow-only increment.
- Phase7 disposition: local preparation and current-runtime Ubuntu CI complete;
  release readiness remains NOT READY. The rechecked development namespace remains UID1001,
  ARM64/PID1 `codex`, without KVM/QEMU/nspawn; full authorized boot fixtures and
  approved assets are still absent. U-02–U-08, real Profile/root/systemd/reboot
  and external-client acceptance remain unverified. Debian remains deferred.
  No managed installation, development-host dependency provisioning, production
  service/account/firewall mutation, version bump, tag or release was performed.
  Candidate review/commit/push and its Ubuntu CI are now complete. Stop adding
  features; the next work is the existing finite acceptance on an explicitly
  authorized disposable environment.
- Phase5 assessment / Phase6 scope (2026-10-29): the local status/resources main
  flow is basically complete based on source and the recorded34-suite/468-pass
  gate below. External checks remain deferred. The user authorized continuing
  Phase6 and then explicitly selected manual firewall management, with only
  recovery diagnostics in this increment. No new hardening campaign is required.
- Phase6 implementation: `pnm recovery list|inspect` and its menu entry reuse
  the existing transaction parser and shared lock. They remain available while
  the pending guard blocks ordinary reads, report that exact guard's result,
  redact sensitive evidence and leave records/permissions/write refusal intact.
  No new transaction engine, state database, automatic replay/repair, firewall
  writes or backup encryption. Current uncommitted work remains based on268a315;
  final Phase6 gate results follow.
- Phase6 fresh validation (2026-10-29,268a315 plus uncommitted Phase4/5/6 edits):
  `make release-check` exit0, including release/syntax/security scans and35
  unit/mock suites,475 passed/0 failed. Recovery6/6 and CLI18/18 are included;
  the actual update CLI body remains skipped in this non-root run. The other four
  root-only skips remain read access, TLS access, low-mode recovery and numeric
  ownership. The targeted recovery suite separately passed6/6, exit0.
  `make shellcheck`, supplemental ShellCheck of the two changed Phase6 unit
  scripts and `git diff --check` each exited0. Private logs/exits:
  `/tmp/pnm-phase6.4XsyX9zB/`. Environment: UID1001, Ubuntu22.04 ARM64,
  PID1 `codex`, umask077, Bash5.1.16, Python3.10.12, OpenSSL3.0.2 and approved
  temporary ShellCheck0.8.0.
- Phase6's user-selected development scope is complete: CLI/menu recovery
  diagnostics, actionable refusal hints, shared-lock inspection while blocked,
  validated/redacted output and evidence preservation. Tests use real private
  files/transaction receipts with a test-only root-policy override; the real CLI
  root refusal is exercised. This is not native root/systemd integration,
  production recovery, reboot or external-client acceptance. No packages,
  accounts, services or firewall rules were changed; no deployment, new amd64 CI,
  commit or push was performed. Firewall automation, automatic replay and backup
  encryption/key custody are explicitly deferred. Stop this increment here;
  Phase7 release/deployment actions are not automatically authorized.
- Phase4 assessment / Phase5 authorization (2026-10-29): source and the recorded
  33-suite/458-pass gate support basic completion of the bounded installed-node
  Profile flow (CLI/menu, three selections, preserved resources, unchanged peer,
  failure compensation, membership guards, links/checks and trusted restore).
  This assessment does not substitute for real systemd acceptance or imply
  single-Core initial provisioning. The user explicitly authorized Phase5 when
  this flow was basically complete; missing integration fixtures do not trigger
  another Phase4 hardening cycle.
- Phase5 scope: additive Profile/desired-port information in status, and optional
  `check --resources` memory/Swap/load/system OOM observations. Default check
  behavior, CLI name, state/transaction architecture and VERSION remain intact.
  No automatic tuning, daemon/state store, external connectivity checks or new
  fault campaign. Earlier Phase4 test results below remain separately identified;
  final Phase5 gate evidence is recorded next.
- Phase5 fresh validation (2026-10-29,268a315 plus the uncommitted Phase4/5 edits):
  `make release-check` exit0; release scan, syntax/security scan and34 unit/mock
  suites,468 passed/0 failed. Five root-only bodies/suites remain skipped:
  actual update CLI, read access, TLS access, low-mode recovery and numeric ownership.
  Included suites: Profile9/9, resources/status8/8, CLI17/17 and check28/28.
  The check suite separately exited0 with28/28; the earlier seven-case resource
  run passed before the reader-unavailable case was added, and the final gate
  executes all eight. Production ShellCheck and supplemental ShellCheck of the
  three changed Phase5 unit scripts exited0. `git diff --check` exited0.
  A read-only native `/proc` observation exited0 with the expected four-row format;
  this establishes reader execution, not node health or absence of warnings.
  Private logs/exits: `/tmp/pnm-phase5.uTsUPDpn/`. UID1001, Ubuntu22.04 ARM64,
  PID1 `codex`, umask077; approved temporary ShellCheck0.8.0, Bash5.1.16,
  Python3.10.12 and OpenSSL3.0.2. No packages, accounts or services were changed;
  no deployment, external-client checks, new amd64 CI, commit or push was run.
- Phase5 local main flow is now basically complete: default checks retain their
  scope, optional resource diagnostics preserve JSON/quiet output and0/1/2 exit
  precedence, and status separates desired Profile/ports from actual services.
  Unreadable desired state is unknown/null without default-port probes. OOM is
  explicitly system-wide/cumulative, not Core attribution. Keep real supported
  systemd/Profile/reboot acceptance pending with Phase3/4; optional external
  checks remain deferred. Phase6 recovery diagnostics are now explicitly scoped
  above; firewall management remains manual.
- Phase4 authorization (2026-10-29): the user explicitly requested its main-flow
  implementation without waiting for the unavailable Phase3 acceptance fixtures.
  This does not close Phase3 or authorize deployment. The bounded development
  flow is existing dual-Core install → `profile set reality|hy2|dual --yes` →
  profile-aware links/checks and trusted restore. Optional `PNM_PROFILE` reuses
  node.conf; missing means dual. Switching retains all Core resources and uses
  the existing transaction/locks. Single-Core initial provisioning, broader
  Phase5 observability and firewall/release work are outside this increment.
  Current uncommitted edits are based on268a315. Do not apply earlier
  published-source CI to them.
- Phase4 local validation (2026-10-29): final `make release-check` exited0,
  including release scanning, syntax/security checks and33 unit/mock suites:
  458 passed/0 failed. Five root-only skips remain the actual update CLI, read
  access, TLS access, low-mode recovery and numeric ownership. The new Profile
  suite passes9/9; CLI passes16/16 with its root-only body skipped; restore includes
  an archived reality-profile case that leaves Hysteria2 inactive/disabled.
  Separate targeted Profile9/9 and CLI16/16 runs exited0. `make shellcheck` and
  supplemental ShellCheck of the four changed unit scripts each exited0.
  `git diff --check` exited0. Final gate logs/exits are private under
  `/tmp/pnm-phase4.wbxCBFvE/final-release-check.*`; the incomplete earlier gate
  had no terminal exit record and is not counted. Environment: UID1001,
  Ubuntu22.04 ARM64/PID1 `codex`, umask077, Bash5.1.16, Python3.10.12,
  OpenSSL3.0.2 and approved temporary ShellCheck0.8.0.
- Profile tests use private real files/transactions and simulated service
  observations; they do not establish actual systemd activation, production
  ownership admission, client connectivity or reboot acceptance. No installation,
  dependency provisioning, real service/account changes or new amd64 CI was run.
  Phase4's installed-node CLI/menu, preserved resources, failure compensation,
  disabled-Core guards/links/checks and profile-aware restore are implemented
  locally. Remaining acceptance is the same normal switch and selected failure
  flow on approved Ubuntu22.04/24.04 amd64/systemd fixtures; no new fault campaign
  is required. Phase3 U-02–U-08 remain BLOCKED. VERSION remains0.16.0-rc.1.
- Cleanup based on HEAD `d926d07` (2026-10-29): removed11 unused
  functions,120 runtime lines including separators, across assets/preflight,
  legacy host diagnostics and lifecycle reset. Repository reference checks found
  no remaining callers. The removed asset-output test now checks the production
  manifest loader's two version/hash pairs and silent output. Active CLI,
  transaction, TLS, account and recovery paths were retained; no new stage or
  fault scenario was added. Other cleanup candidates remain outside this change.
- Fresh cleanup validation on Ubuntu22.04 ARM64, UID1001/PID1 `codex`, umask077:
  `make release-check` exit0, including syntax/security scanning and the embedded
  `make check`:32 suites,447 passed/0 failed. Five root-only skips remain:
  actual update CLI, read access, TLS access, low-mode recovery and numeric ownership.
  The assets suite passed13/13 separately. `make shellcheck` and supplemental
  ShellCheck of `tests/unit/test_assets.sh` each exited0; `git diff --check` exited0.
  Tools: Bash5.1.16, Python3.10.12, OpenSSL3.0.2 and the previously approved
  temporary ShellCheck0.8.0. Private logs: `/tmp/pnm-mainflow-cleanup.N3ctKksT/`.
  The worktree was clean before these edits; VERSION remains0.16.0-rc.1.
- No new amd64 CI, managed installation, real account/service changes or reboot
  was run for this cleanup. The published-source CI below is earlier evidence,
  not validation of these local edits. U-02–U-08 remain BLOCKED; Debian is deferred.
- Ubuntu development validation remains first; Debian acceptance is deferred.
- Earlier published/validated source:ce0faf7efedd86f8d4516e605220e3cc7a4a8f4d,
  [run40526987902](https://github.com/mrshyi/pnm/actions/runs/40526987902), success
  on both Ubuntu22.04/24.04 amd64. Public external-ca inputs now reach the menu
  installation action too; this does not establish a full guest-install pass.
- Per Ubuntu job: normal check/release447 each; privileged suites52; loopback
  asset transport7; real systemd8; official-Core private-network10; ShellCheck
  success. These are separate execution layers, not an independent total.
- Main-flow preparation per Ubuntu job:36 total,28 executed/8 root-only skipped;
  no guest installation or reboot runs in that step.
- The five ordinary non-root skips remain intentional; their corresponding
  privileged suites actually execute without skips. Current ARM64 transport
  self-checks use synthetic assets and do not execute amd64 binaries.
- Earlier stages and the corrected protected-checkout failure remain below as dated,
  source-specific evidence; earlier CI is not substituted for latest-source runs.
- Root service/Core integration now uses disposable Ubuntu22.04/24.04 amd64
  GitHub-hosted runners. The ARM64/non-root development host remains L1 only;
  do not provision it, run service/storage faults on it or start Phase4 automatically.
- Stage14 candidateee132a757b15da84b488f04b6e285acb206e5ddb is published;
  [run40458759515](https://github.com/mrshyi/pnm/actions/runs/40458759515)
  passed the expanded7-case transport suite on both Ubuntu versions.
- Stage15 candidateb3e223d730c773b61da8512e4574b29ece9083fb is published;
  [run40460290093](https://github.com/mrshyi/pnm/actions/runs/40460290093)
  passed the TLS leaf/mode fixes and all existing gates on both Ubuntu versions.
- Stages16–17 add no-replace publication for TLS pairs and Hysteria2 binaries;
  both commits pass their own Ubuntu22.04/24.04 CI runs. No installation,
  production service, account or release/version changes were performed.

## Current environment

- `dev-sanjose`: Ubuntu 22.04.5 LTS ARM64, UID/GID1001, OpenSSL3.0.2.
- The execution namespace has PID1 `codex`; root, `/dev/kvm`, QEMU and nspawn
  are not available in the checked session. Do not infer the whole host's service
  state from this namespace. Recheck capabilities before choosing integration work.
- This is a Linux L1 development workspace. Supported deployments remain Debian
  12/13 and Ubuntu22.04/24.04 amd64 with systemd.
- ShellCheck0.8.0 was approved, downloaded from the configured Ubuntu repository
  and extracted to `/tmp/pnm-cloud-fix.v5LWBeoD/shellcheck-tool`. It was not
  installed system-wide. This temporary path must be rechecked before reuse.
- No deployment target or external clients have been supplied for G-01/L3.
  Historical WSL storage limits, host paths and private VM assets are not cloud
  prerequisites or transferred fixtures.

For development setup and gate commands, use [CONTRIBUTING](../CONTRIBUTING.md).
For test IDs and closure rules, use [ACCEPTANCE_PLAN](ACCEPTANCE_PLAN.md).
Continue Ubuntu validation in stages, committing validated work and recording
exact source identity before moving on. CI uses disposable hosted runners;
production access, deployment and package installation on the development host
remain outside scope.

## Current implementation and remaining acceptance

Status is split into development disposition and remaining acceptance. **开发完成**
means the scoped repair exists with recorded automated evidence, not complete
deployment acceptance. **必须修复** requires a reproduced defect in this frozen
scope. **验收挂起** means specified evidence or an authorized fixture is missing.
**明确延期** records work excluded from this closeout, without claiming it passed.

| Item | Development disposition / source anchors | Remaining acceptance |
|---|---|---|
| G-01 runtime/config/link state | 验收挂起; dual-Core runtime/applied/InvocationID gates exist in `lib/node.sh` and `lib/render.sh`; no new implementation gap confirmed | U-02/U-04/U-08: verify installed source identity and runtime/link evidence on the disposable Ubuntu targets. Any separate existing deployment stays unverified until supplied |
| G-02 deployment recovery | 开发完成; `lib/deploy.sh` and `lib/transaction.sh` implement common commit/compensation, metadata/directory/account receipts and uncertainty guards | 验收挂起: U-02/U-03/U-07/U-08; full CLI installation and the selected compensation/reboot checks |
| G-03 Core update/rollback | 开发完成; `lib/core-ops.sh` pairs current/previous binaries and version metadata and isolates the peer Core | 验收挂起: U-05/U-07/U-08; distinct approved versions, selected startup failure and persisted state |
| G-04 backup/restore | 开发完成; `lib/core-ops.sh` validates trusted archives, bounds parsing and compensates resource metadata; D-009 remains binding | 验收挂起: U-06/U-07/U-08; trusted round trip, rejected archive and selected restore failure |
| G-05 dependency preflight | 开发完成; `lib/preflight.sh` and `adapters/assets.sh`; recorded real curl/TLS7-case transport checks include503 retry counts | 验收挂起: U-01/U-07; actual install missing-tool refusal before managed changes |
| G-06 HY2 TLS/account access | 开发完成; `lib/tls.sh`, `lib/accounts.sh`, `lib/check.sh`; recorded privileged access8/8 and isolated real-Core TLS/traffic | 验收挂起: U-02/U-03/U-07; actual managed accounts, self-signed/external certificate loading and compensation |

**必须修复 queue: no newly confirmed item in this closeout review.** This is a
targeted source/evidence reconciliation, not a claim of an exhaustive defect-free
audit. If U-01–U-08 reproduce a security, correctness, recovery or compatibility
failure, record its source, command, expected/actual state and minimal fix here;
do not turn an untested combination into a new implementation task by default.

**明确延期:** Debian12/13 acceptance; public external-client T-27 and separately
supplied deployed-node comparisons; physical media/power-loss faults, exhaustive
storage/commit/concurrency combinations, alternative NSS providers, other HTTP
retry statuses/Retry-After and upstream DNS/PKI outage campaigns. Retain these
limits for supported-platform/production readiness; they do not automatically
expand the bounded Ubuntu closeout. Basic Ubuntu reboot and selected rollback
failures remain required below, not deferred.

The finite execution contract is [U-01–U-08](ACCEPTANCE_PLAN.md#ubuntu-closeout).
All eight must have evidence on Ubuntu22.04 and24.04 before Ubuntu closeout is
declared. The recorded32423be CI satisfies only the U-01 layer for that
source; U-02–U-08 remain pending. No target, assets or installation/reboot
authorization is inferred from this checklist. Phase3 remains acceptance-pending;
closure requires the bounded results and an explicit disposition of residuals,
not merely this document edit. Phase4 development is now separately authorized;
its implementation does not change these Phase3 acceptance dispositions.

| Closeout ID | Ubuntu22.04 | Ubuntu24.04 |
|---|---|---|
| U-01 | PASS at32423be, run40894062624 | PASS at32423be, same run |
| U-02 | BLOCKED | BLOCKED |
| U-03 | BLOCKED | BLOCKED |
| U-04 | BLOCKED | BLOCKED |
| U-05 | BLOCKED | BLOCKED |
| U-06 | BLOCKED | BLOCKED |
| U-07 | BLOCKED | BLOCKED |
| U-08 | BLOCKED | BLOCKED |

BLOCKED here is a pre-execution disposition: authorized disposable full-flow/boot
fixtures and the required verified assets have not been established. No new
attempt or failure is implied. Existing hosted service/Core CI is not that fixture.

Current source, historical observations and fresh Ubuntu checks have separate
evidence below; selected CI integration does not establish the full L2 matrix.
The [dated T-01–T-27 reconciliation](history/PHASE3_EXECUTION_2026-10-22_26.md#matrix-reconciliation--2026-10-25)
retains exact prior coverage and limits. Earlier A-01–A-05 reports are pre-repair
findings; do not reopen them solely because the archived text describes old code.

## Earlier cloud increment: shared TLS and non-root tests

- Shared TLS validation rejects OpenSSL3.0's exit0 hostname mismatches and uses
  locale-stable default certificate dates instead of unsupported date options.
  Added regression coverage retains SAN/CN precedence and wildcard boundaries.
- Transaction inspect's umask failure was a hardcoded0644 fixture expectation;
  the test records the actual mode. Production transaction logic was unchanged.
- Non-root fixtures expect diagnostic UNKNOWN/WARN or permission refusal without
  weakening production guards. Root assertions/skips remain distinct.

Results below were executed **after the TLS fix and before the current cleanup**:

| Check | Actual result |
|---|---|
| `make check`, umask077 | exit0;32 suite summaries,392 passed,0 failed |
| `make shellcheck`, temporary tool on PATH | exit0; ShellCheck0.8.0 |
| `make release-check`, umask077 | exit0; repeats32 suites/392 passes, not independent coverage |
| Supplemental ShellCheck of five changed test/fixture scripts | exit0 |
| Transaction suite, umask077 and022 | exit0 each;25/25 each |
| Offline guest guards | exit0;33 total,25 passed/8 root-only skipped |
| Core refusal guard | exit0;1 passed |
| Integration Python in-memory compilation |26 files passed, no bytecode generated |

Root-only bodies/suites were skipped: real update CLI, root/runuser/nobody access,
real TLS access, low-mode recovery and numeric ownership. Non-root392 passes are
not the historical root399 baseline or proof of root branches. The pre-fix cloud
baseline had374 passes/17 failures; its separate log remains
`/tmp/pnm-cloud-l1.zOeyAANW/check.log`. Post-fix logs are private under
`/tmp/pnm-cloud-fix.v5LWBeoD/`; these are volatile local evidence, not durable
handoff artifacts. Detailed repair evidence is
[archived](history/PHASE3_EXECUTION_2026-10-22_26.md#cloud-tls-compatibility-and-regression-repair--2026-10-26).

## Cloud development cleanup

- Current instructions are in AGENTS/CONTRIBUTING; the completed one-time cloud
  transfer handoff is removed, including its obsolete source-transfer/commit text.
- Old rolling execution notes, three baseline audit/design reports and56 dated
  plans are in [history](history/README.md). Their results and limitations are
  retained, but their old next steps are not the current task list.
- Acceptance guidance now distinguishes Linux ARM64/non-root L1 from amd64 L2.
  Repeated historical result blocks have been removed from the active plan.
- Removed Windows-only certificate-path handling and the Windows metadata stub.
  Preflight now exercises actual Linux ownership/modes and rejects unsafe modes.
- Python test entry points suppress bytecode, and caches are ignored.

Fresh cleanup checks (Ubuntu ARM64/non-root, private logs under
`/tmp/pnm-cloud-cleanup.o0x8j6_s/`):

| Check | Actual result |
|---|---|
| `make release-check`, umask077 | exit0; release scan plus embedded `make check`:32 suites,392 passed,0 failed |
| `make shellcheck`, approved temporary ShellCheck0.8.0 on PATH | exit0 |
| Supplemental ShellCheck of the two changed test scripts | exit0 |
| Preflight suite, umask077 and022 | exit0 each;14/14 each, real Linux metadata |
| HY2 SNI suite | exit0;9/9 |
| Markdown local paths/anchors |73 files,138 links checked; no failures; external URLs not fetched |
| Archive preservation |59 reports/plans and the prior uncommitted rolling task record preserved, apart from banners/links/title |

The release target supplies this cleanup's full check run; a second standalone
`make check` was not repeated. Root-only bodies/suites retain the skips listed
above. No new root/systemd, actual Core, VM/reboot or external traffic evidence
is claimed. The opt-in real-Core target was only dry-run inspected for `-B`;
no assets were downloaded or executed. No commit, push or deployment was performed.

## Ubuntu22.04/24.04 compatibility

The platform adapter already accepts Ubuntu22.04/24.04 amd64; no whitelist,
architecture, Core asset, account or service-policy relaxation was needed.
The shared TLS repairs above are included in published commit39312aa.

- CI now selects `ubuntu-22.04` and `ubuntu-24.04` explicitly instead of a moving
  `ubuntu-latest`, keeps failures independent, records OS/tool versions and checks
  the native host through the actual platform adapter before mock tests. All
  three existing gates remain configured. The setup step declares its test tools.
- Platform regressions cover both Ubuntu fixtures and the Debian compatibility
  baseline, reject unsupported architectures, other Ubuntu versions, derivatives
  and missing VERSION_ID. The distro name alone cannot bypass the architecture gate.
- Service regressions run the actual `systemd-analyze verify` against both
  rendered unit policies using isolated targets and temporary Core paths, and
  require refusal when the fixture executable loses its executable mode. No Core
  program or service is started, and host unit search paths are excluded.

This session has Ubuntu22.04 ARM64, Bash5.1.16, Python3.10.12, OpenSSL3.0.2 and
systemd249.11. It has no approved Ubuntu24.04 or amd64/root guest. The CI matrix
was initially checked only as configuration; the subsequent executed amd64 results
are recorded below. Neither layer proves deployed Ubuntu lifecycle acceptance.
Fresh local results (private logs under `/tmp/pnm-ubuntu-compat.oNt1gGQy/`):

| Check | Actual result |
|---|---|
| `make release-check`, umask077 | exit0; release scan and embedded `make check`:32 suites,395 passed,0 failed |
| `make shellcheck`, approved temporary ShellCheck0.8.0 on PATH | exit0 |
| Supplemental ShellCheck of check/service suites | exit0 |
| Focused check/platform suite | exit0;27/27 |
| Focused service suite, actual systemd249 verifier | exit0;4/4 |
| CI YAML/matrix and all five run scripts | parsed/asserted and `bash -n` passed; no CI execution |

This is fresh Ubuntu22.04 ARM64/non-root L1 evidence, including static systemd
parsing. Explicit root-only skips remain: real update CLI, root/runuser/nobody
access, real TLS access, low-mode recovery and numeric ownership. No second
standalone full check was counted. Ubuntu22.04/24.04 amd64 root/service lifecycle,
reboot and external traffic remain unverified.

## Stage 1: executed Ubuntu CI reconciliation

On2026-10-26 the connected GitHub app supplied the completed job metadata and
full job logs for [CI run40310959008](https://github.com/mrshyi/pnm/actions/runs/40310959008),
attempt1, exact source39312aaf6de9e97cccfcaf09e257e923d6246cad, event `push`.
Both jobs and each of `make check`, `make shellcheck`, `make release-check`
concluded success. Each log contains64 suite summaries:32/395 passes for the
first full check, then the same32/395 for the release target's repeated check,
with0 failures. Repetition is not additional independent coverage.

| Job | Observed native environment | Actual scope |
|---|---|---|
|121531726496, Ubuntu22.04 |22.04.5 LTS, x86_64, Bash5.1.16, Python3.10.12, OpenSSL3.0.2, systemd249.11 | Non-root L1 plus real certificate tools and isolated static unit verification; all three gates passed |
|121531726942, Ubuntu24.04 |24.04.5 LTS, x86_64, Bash5.2.21, Python3.12.3, OpenSSL3.0.13, systemd255.4 | Same L1/static scope; all three gates passed |

Both logs retain explicit skips for the real update CLI, root/runuser/nobody
access, real TLS access, low-mode recovery and numeric ownership. These are
now actual Ubuntu amd64 CI results, not os-release fixture inference, but do
not close root/Core/systemd lifecycle, reboot, G-01 or L3. Only status evidence
changed in this stage; no business tests were rerun for the documentation edit.

## Stage 2: fail-closed asset candidate publication

Validation parent166e828. Source/caller inspection found that the shared download
adapter ignored chmod failure and accepted GNU `mv -n` exit0 when a destination
appeared during transport. A directory could also receive the temporary candidate
as a child. Host cache preparation would then set its selected path without a
new hash check. Core update uses the same adapter before its binary transaction.

The shared function now rejects pre-existing dangling links, checks candidate
chmod, uses no-target-directory/no-clobber publication and requires the original
candidate path to disappear before success. Occupied destinations return73;
candidate mode failure returns77. Only the owned candidate is removed on refusal;
foreign destinations and unrelated sentinels are retained. No CLI, manifest,
URI, service policy or managed transaction schema changed.

Five new regression wrappers exercise both Cores with a controlled curl script:
dangling destination before transport, raced file/directory/link and chmod error.
Before the fix the asset suite had6 passes/5 failures; afterward11/11 pass. Actual
GNU move/file/link operations and hashes execute in private temporary paths;
chmod error is injected and no network, account or service operation occurs.
The14 host-apply and5 approved-version tests also pass (exit0 each). Full
`make release-check` exits0:32 suites,400 passed,0 failed, including syntax and
security scanning. Standard ShellCheck and supplemental asset-test ShellCheck
both exit0. Root-only skips remain unchanged; no L2 or external result is added.
Private logs:
`/tmp/pnm-stage2-assets.OWQojhdj/`. Earlier39312aa CI results do not cover this patch.

## Stage 3: ZIP observation and executable-mode refusal

Validation parent6ec55cc. A private reproduction showed `unzip -Z1` returning23
with a valid-looking name, followed by successful extraction and staging0. The
process-substitution producer's status did not reach the existing while-loop guard.
The helper now checks list-query success and nonempty output before the existing
member-name checks and real extraction. It returns78 on list/format refusal,
and77 when candidate chmod fails, with no successful candidate path on stdout.

Four new wrappers first failed (11 existing passed/4 failed), then the staging
suite passed15/15. They cover failed listing with and without output, empty
success, and final chmod failure. Extractor invocation and actual candidate files
are checked, source ZIP hashes remain unchanged, and the real safe/traversal ZIP
cases remain. Safe ZIP construction/extraction and metadata use real tools;
observer/permission errors are injected. No real Core, account or service runs.
The12 sandbox install cases also pass. `make release-check` exits0:32 suites,
404 passed,0 failed; standard ShellCheck and supplemental staging-test ShellCheck
both exit0. Existing root-only skips remain; neither storage failure on a real
device nor L2/Core runtime is newly validated. Private logs:
`/tmp/pnm-stage3-zip.2QudjIGe/`.

## Stage 4: first-install version-query refusal symmetry

Validation parent5eb8be9. Added unparseable HY2 and failed Xray query cases;
both failed-query fixtures now emit a matching-looking banner before exit23.
Per-process receipt files prove the correct version command ran and preserve
fail-fast Xray-before-HY2 behavior. Each refusal returns78 without publishing
either managed binary; the matching pair still permits both publications.
Only fixed safe fixture programs execute and their publication function is
substituted. Runtime code and manifests did not change in this stage.

The focused approved-version suite passes7/7. Standard and supplemental
test-script ShellCheck pass. `make release-check` exits0:32 suites,406 passed,
0 failed, including syntax/security scanning. Root-only skip labels remain the
same. No additional independent full run is counted. Private logs:
`/tmp/pnm-stage4-versions.S7jmiGqQ/`. These remain L1 boundary checks, not official
Core execution, a failed real filesystem, root identity or L2 acceptance.

## Stage 5: filename-independent checksum verification

Validation parentae838f5. A real GNU sha256sum probe rejected a correct approved
digest when the source filename contained a literal backslash: filename escaping
prepended a backslash to the parsed digest. The shared verifier now reads the
content through standard input, checks the tool's exit status directly and
extracts the digest without an awk pipeline. Download, cached and supplied-asset
callers retain their interfaces and mismatch refusal behavior.

Two regressions first failed (11 passed/2 failed), then the focused asset suite
passed13/13. One uses an actual backslash-containing Linux path and real hashing;
the other injects matching checksum output followed by exit23 with caller
pipefail disabled. No network, Core or host service is involved. Private logs:
`/tmp/pnm-stage5-hash.sKgyFC7V/`.

`make release-check` exits0:32 suites,408 passed,0 failed. Standard ShellCheck
and supplemental asset-test ShellCheck exit0. The same root-only skips remain;
this is L1 evidence, not a fresh supported-platform integration result.

## Stage 6: TLS pin pipeline failure propagation

Validation parent9dda49f. Shared SPKI pin generation previously masked pipeline
failure with a successful final newline. The private-key pipeline also depended
on caller pipefail. Both now enable pipefail within command
substitutions, check status before using output and return78 on tool failure.
The SPKI helper buffers output until the pipeline succeeds. No persisted pin,
certificate, CLI or client-link format changed; caller shell options are retained.

Four regressions first failed (6 passed/4 failed). The focused TLS suite then
passed10/10. Actual temporary EC certificates, public-key DER conversion, hashing
and encoding run; controlled wrappers emit their normal valid output before
exit23 at DER/digest/base64 or private-key export. Tests cover caller pipefail
both on/off, empty failure output and unchanged caller options. Standard and
supplemental TLS-test ShellCheck pass. Private logs:
`/tmp/pnm-stage6-tls.L98Uhzxk/`. These are L1 tool-failure boundary checks,
not actual Core TLS handshakes or root/service permission acceptance.

`make release-check` exits0:32 suites,412 passed,0 failed, including syntax and
security/release scans. Existing root-only skips remain unchanged. No second
independent full test run or new Ubuntu amd64 CI execution is claimed.

## Stage 7: transaction checksum and inspect observation failures

Validation parentfd3710c. Transaction hashing had the same GNU filename-escape
issue as asset verification, causing write intent refusal for a legal parent
path containing a backslash. It now hashes content through stdin and propagates
tool failure without relying on caller pipefail. Missing/unsafe sentinels remain.
Inspect previously accepted an empty failed hash query because it only compared
output against UNSAFE; it now checks status and a canonical digest before using
the transaction's terminal state. Existing write guards retain the refusal.

Three regressions first failed (25 passed/3 failed), then the focused suite
passed28/28. Actual private files, snapshots, writes, rollback, numeric metadata
and receipt parsing execute. Backslash-path recovery preserves original content
and metadata and remains inspectable. A controlled hash wrapper emits valid
output before exit23, or no output; failed observations refuse inspect78 and the
pending-transaction guard70 while preserving candidate bytes. The direct hash
failure case runs with caller pipefail disabled. Standard and supplemental
transaction-test ShellCheck pass. Private logs:
`/tmp/pnm-stage7-transaction.FEq7vMyo/`. This does not prove physical EIO or
authenticate snapshot bytes against a separately retained original digest.

`make release-check` exits0:32 suites,415 passed,0 failed. The existing root-only
skips remain. The final focused28/28 run additionally verifies downstream write
guard refusal; the full run also includes those assertions. No L2 result is added.

## Stage 8: applied binding hash observation consistency

Validation parente4999df. Applied publication and status retained filename-based
checksum pipelines: a literal backslash could prevent publication or label
unchanged runtime content as changed. With caller pipefail disabled, a hash tool
printing a valid digest before exit23 could still publish/confirm a binding.
Publication now reuses the transaction hash helper; standalone status retains
its module boundary and hashes through stdin with direct status checking.
Publication refuses70 and observation returns unknown on hash failure. Existing
digest/InvocationID matching, CLI and record formats are unchanged.

Four regressions first failed (41 passed/4 failed), then the focused suite
passed45/45. Each exercises both Cores:
backslash-path observation, real transaction-backed evidence publication and
receipt inspection, failed observation and failed publication. Actual private
files/hashes/transactions execute; systemd InvocationIDs are controlled fixtures.
Peer receipts and restart counters remain unchanged, and a failed hash leaves
original applied bytes with no written resource or staged binding. The error
cases disable caller pipefail and inject valid hash output followed by exit23.
Standard and supplemental Core-evidence-test ShellCheck pass. Private logs:
`/tmp/pnm-stage8-binding.qk3v4VNg/`. This is L1 evidence, not a real running
configuration identity or new supported-platform/L2/client acceptance result.

`make release-check` exits0:32 suites,419 passed,0 failed, including syntax and
security/release scans. Root-only skips remain the same; the focused45/45 run
and its full-gate repeat are not counted as independent acceptance coverage.

## Stage 9: Ubuntu-first development main-flow validation

The latest user instruction prioritizes Ubuntu development/main-flow checks and
defers Debian acceptance. Debian is no longer a prerequisite for this stage.
Validation source is71e4c2b; this increment changes documentation only. The fresh
run used Ubuntu22.04.5 ARM64, UID1001 and PID1 codex. A read-only Docker probe
confirmed an ARM64 server with no prepared Ubuntu test image; no container,
package, account, service or deployment was created or changed.

`make release-check` exits0:32 suites,419 passed,0 failed. This fresh run includes
the following development main-flow segments:

| Segment | Existing suites / passed wrappers |
|---|---|
| CLI, node initialization/validation/reporting/links | CLI11; node30 |
| Fresh sandbox install, credentials/TLS, failed-install retry | sandbox install12 |
| Applied binding, config apply, restart, update and rollback | Core operations15; Core evidence45 |
| Backup/archive validation and restore/compensation | backup archive9; backup flow9; restore flow17; restore recovery12 |
| Shared deployment compensation and receipt inspection | deployment transaction24; transaction28 |
| Shared real-certificate/tool-failure checks | TLS10 |

These suites use private real files, crypto, metadata and transactions with fixed
Core/service/account/platform observations where needed. They are L1 development
segments, not one real host installation or official-Core traffic. Root-only
update CLI, access/readability, TLS access, low-mode recovery and numeric ownership
branches retain their existing explicit skips; the TLS-access suite has0 executed
passes. Table entries are part of419, not additional independent passes.

Standard ShellCheck exits0. Offline guest guards exit0:33 total,25 executed and8
root-only skipped; real-Core refusal guard exits0:1 passed. Neither boots a guest
or executes an official Core. Private full-gate logs:
`/tmp/pnm-stage9-ubuntu.MwuaZn23/`. At stage9, Ubuntu amd64 CI evidence remained
at39312aa; stage10 records the subsequent successful latest-source jobs.

## Stage 10: refreshed Ubuntu amd64 CI

Published source:d7919a2e95f4f172d935a326d24c637165165a9f, push event,
[CI run40444662565](https://github.com/mrshyi/pnm/actions/runs/40444662565),
attempt1, completed success. Both jobs checked out this exact source, including
all published asset/TLS/transaction/applied-binding fixes.

| Job | Actual platform/tools | Result |
|---|---|---|
| 121992956951 | Ubuntu22.04.5 x86_64; Bash5.1.16, Python3.10.12, OpenSSL3.0.2, systemd249.11-0ubuntu3.23 | check32/419/0 failures; ShellCheck success; release-check32/419/0 failures |
| 121992957259 | Ubuntu24.04.5 x86_64; Bash5.2.21, Python3.12.3, OpenSSL3.0.13, systemd255.4-1ubuntu8.18 | check32/419/0 failures; ShellCheck success; release-check32/419/0 failures |

Each log contains64 suite summaries because release-check repeats check. This
is419 passed wrappers per gate, not838 independent cases. Both jobs retain the
same five root-only skip labels (real update CLI, access, TLS access, low-mode
recovery, numeric ownership). These actual Ubuntu amd64 L1 results close the
latest-source CI gap, not root/Core lifecycle, reboot or external acceptance.
The follow-up CI preparation reuses existing isolated integration targets; it
must retain their ownership/cleanup guards and needs actual run results before
any stronger acceptance claim.

## Stage 11: Ubuntu-hosted service and real-Core integration

Validation parentd76379d. CI now explicitly invokes existing test-systemd and
test-real-cores after the ordinary gates, on the same disposable Ubuntu22.04/24.04
amd64 runners. A30-minute job deadline bounds the CI operation. Pinned fixture
assets are acquired by the existing shared downloader from the test manifest's
versions/hashes into an owned root-private temporary cache; the real-Core harness
independently validates size/hash/ownership before execution. EXIT removes the
owned cache. No managed PNM install, host package change or production operation
is added by these integration steps.

The old systemd fixture's empty runtime configs both returned70 from the current
listener gate in a local reproduction. Replace sleep-only services with nobody
Python TCP/UDP listeners on temporary high ports, render configs using existing
fixtures/production functions, and exercise actual listener readiness during
activation. Compensation compares the restored config digest rather than an
empty JSON literal. UUID-scoped unit names, ownership/hash checks, cleanup and
root/opt-in refusal remain in place. These listeners are test programs, not Cores.

Local validation: workflow matrix/runner/deadline/entry-point assertions, both
outer and inner Bash syntax/ShellCheck, integration-script syntax/ShellCheck,
repository syntax/security scans and diff whitespace checks pass. Actual local
TCP/UDP listeners plus production render/parser/readiness pass as the normal
workspace user outside the socket-restricted sandbox; this starts no systemd
unit. Systemd opt-out returns64 and non-root opt-in returns77. Hosted systemd
and official-Core execution are pending the candidate's actual CI run; no root
or traffic acceptance result was claimed during local preparation.

Actual result: [run40446477495](https://github.com/mrshyi/pnm/actions/runs/40446477495),
push/attempt1, exact sourced2b1844d7acaf79e8baf04c5fa007ee4e906688f,
completed success. Jobs121998867541 (Ubuntu22.04) and121998867796 (Ubuntu24.04)
each pass check32 suites/419 wrappers, ShellCheck, release-check32/419, real
systemd8/8 and official-Core10/10. Each job has66 suite summaries:64 from the
repeated L1 gates, one service suite and one Core suite; do not sum them as unique
independent cases. L1 root-only skips remain explicit.

Real service checks cover activation, independent restart/applied InvocationID,
inactive/disabled and active/disabled recovery, TERM/lock release, config/update
compensation and failed-apply evidence recovery. Official Xray v26.10.21 and
Hysteria2 v2.13.0 run as nobody, accept production-rendered config/certificate
fixtures and transfer through real local clients. Wrong VLESS UUID, REALITY short
ID, HY2 certificate pin and password are refused; a valid PNM HY2 pin URI still
transfers. Both harnesses report success only after owned-unit/resource cleanup.
These are actual Ubuntu service and private-network protocol results, not full
managed-account CLI installation, persisted reboot or public L3 connectivity.

## Stage 12: privileged access and recovery CI

Validation parentf46775a. Add the existing CLI, read-access, TLS-access and
transaction suites as explicit sudo invocations on the same disposable Ubuntu
runners. This targets all five previously reported root-only skips: actual CLI
approval refusal, real UID access boundaries, eight TLS-access cases, low-mode
recovery and numeric ownership restoration. TLS access uses private
synthetic files with actual UID/GID/modes, ancestor traversal and runuser/nobody
read probes; NSS/service names are test mappings and no account is created or
changed. Rename only the stat adapter's local scalar from target to stat_target
to remove source-aware ShellCheck array-name collisions, without changing
permission checks or expectations. Ordinary non-root L1 behavior remains a skip.

Local Bash syntax, supplemental ShellCheck and the workflow matrix/entry-point
assertions pass. Privileged execution was still pending during preparation;
the previous stage11 Core/service results did not count as this suite's run.

Candidate run40448066295 failed on both Ubuntu versions: CLI11/11 passes, then
read-access0/1 returns126 instead of1 before the remaining privileged suites can
run. Ordinary check/release-check32/419 and ShellCheck pass. The nobody process
cannot open the checkout below the runner's protected workspace. The corrected
test copies only bin/lib/adapters/VERSION and the public OS fixture into its
owned readable temporary tree, confirms nobody can read the entry point, and
leaves config/state0700 and lock0600. All original exit/status assertions remain.
CLI code runs from the copied tree; production permission guards are unchanged.
Local copied-CLI version/help bootstrap, Bash syntax, supplemental ShellCheck and
workflow assertions pass. Move the privileged step after initial check/ShellCheck
and before the repeated release-check to surface these failures sooner.

Correctioned2b3b137af2eee9103b54c6288955a605759127 was pushed and validated by
[run40449338994](https://github.com/mrshyi/pnm/actions/runs/40449338994),
push/attempt1, completed success. Both jobs122008127260 (Ubuntu22.04) and
122008127445 (Ubuntu24.04) pass every step:

| Execution layer, per Ubuntu job | Actual result |
|---|---|
| Normal-user check and release-check |32 suites/419 passed/0 failed each; repeated gates, not838 independent cases |
| ShellCheck | success |
| Privileged CLI suite |11/11, including actual CLI approval refusal before preparation |
| Privileged read-access suite |1/1 with actual nobody UID, UNKNOWN diagnostics, protected-command77 and public help0 |
| Privileged TLS-access suite |8/8, actual ownership/modes/traversal/runuser with mapped NSS names |
| Privileged transaction suite |28/28, including low-mode and numeric UID/GID restoration |
| Real systemd integration |8/8 |
| Official Core private-network integration |10/10 |

Each job has70 summary lines:32 normal,4 privileged,32 repeated normal,2 real
integration. The privileged section's48 wrappers have no SKIP lines. The normal
user section intentionally retains all five root-only labels. This closes their
Ubuntu execution gap, not the remaining real account-install/NSS variants or
physical storage/reboot/external-client matrix. The protected-checkout failure
was a test-fixture bootstrap defect; no production permission expectation changed.

## Stage 13: real loopback asset acquisition

Validation parent78c528c. Add a separate non-root test-asset-network target and
Ubuntu CI step using the existing AssetServer from guest_update_cases, without
changing its VM guards or server implementation. Both production asset URLs,
curl transport, hash/mode checks and candidate publication execute against a
private loopback CONNECT/TLS fixture with synthetic bytes. No Core executes.

Five local cases pass on Ubuntu22.04 ARM64/curl7.81/OpenSSL3.0.2, each covering
both Cores: verified private publication, checksum refusal78, partial HTTP18→69,
untrusted CA60→69 and controlled TLS-handshake timeout28→69. Assertions cover
receipt statuses, mode0600/current ownership, absent refused destinations,
candidate cleanup, retained unrelated data and bounded owned-thread cleanup.
The first local pilot exposed a fixture CA-subject collision; distinct issuer
subjects give the intended unknown-CA refusal. No production behavior changed.

The client wrapper disables curlrc/retries and imposes test-only bounds. This
does not verify default production retries/overall deadlines, upstream DNS/PKI
outages, full install compensation or archive/Core execution safety. Python AST,
embedded Bash syntax/ShellCheck, repository syntax/security scans, standard
ShellCheck and workflow entry-point/matrix checks pass. Socket creation needs the
approved local loopback execution context outside the restrictive sandbox.
Ubuntu amd64 execution was pending during local preparation.

Published sourcea2f12d6ced683801967c2fe20ff22589925f614f passed
[run40455459999](https://github.com/mrshyi/pnm/actions/runs/40455459999),
push/attempt1, completed success. Jobs122027642713 (Ubuntu22.04) and122027642994
(Ubuntu24.04) each run all5 acquisition cases successfully, with no skips.
Each also passes normal check/release-check32 suites/419 wrappers per gate,
ShellCheck, privileged11+1+8+28=48, real systemd8/8 and official-Core10/10.
The acquisition unittest result is separate from the70 existing suite summaries;
do not add repeated gates or execution layers as unique independent cases.
No runtime module, CLI/config/URI format or VERSION changed in this stage.

## Stage 14: actual HTTP503 retry-count candidate

Validation parent9f90060. Extend the existing HTTPS fixture with per-path503
budgets and request receipts, defaulting to no injected503 for all existing
callers. Keep its10-connection bound, strict CONNECT/GET/path checks and owned
socket/thread cleanup. The asset tests retain production curl retry flags in
two additional cases; other fault cases still disable retries for bounded tests.
No production module, CLI option, timeout or retry policy changes.

Local actual curl/TLS suite passes7/7, covering both Cores. Two503 replies then a
valid body require exactly three HTTP attempts, valid private publication and
consumed failure budgets. Three503 replies exhaust initial+two retries, yielding
curl22/adapter69 with no published destination or retained candidate. A private
source-copy mutation removing `--retry 2` makes both new tests fail as expected,
without changing repository runtime source. Transfer ceilings are test-only;
Retry-After, other statuses, upstream DNS and default overall deadlines remain
outside this evidence.

Python parsing, embedded Bash syntax/ShellCheck, repository syntax/security,
standard ShellCheck and the existing guest guard suite pass. Guest guards report
33 total,25 executed and8 root-only skipped. Ubuntu amd64 CI execution remains
pending during local preparation.

Actual sourceee132a757b15da84b488f04b6e285acb206e5ddb passes
[run40458759515](https://github.com/mrshyi/pnm/actions/runs/40458759515),
push/attempt1, both Ubuntu jobs successful:122038127649 (22.04) and122038127435
(24.04). Each runs7 acquisition cases with no skips and also passes normal
check/release32 suites/419 per gate, ShellCheck, privileged48, real systemd8
and official-Core10. This verifies the declared503 retry count with actual
the actual curl/OpenSSL stacks on both Ubuntu versions; other retry
statuses, Retry-After and default overall deadlines remain open.

## Stage 15: TLS staging destination and mode failures

Runtime validation baseee132a7; stage14 result record221f987 is documentation
only. Source/caller inspection and private reproductions found that self-signed
generation deleted an existing dangling certificate link after failed validation,
while external staging replaced it and returned0. Both destination checks now
reject leaf links as occupied, including an absent target, and return73 before
file publication. Existing regular files retain the same refusal behavior.

Four real-crypto/file regressions initially fail (10 existing passed/4 failed);
the link-only repair passes TLS14/14, sandbox install12/12, ShellCheck and local
release-check32 suites/423 wrappers/0 failures. A second injected-mode regression
reproduces ignored certificate/key chmod errors (14 passed/2 failed). Check both
chmod calls and remove only the newly generated temporary pair on failure77.
The final focused TLS suite passes16/16 and sandbox12/12; standard and targeted
ShellCheck pass. Final local release-check exits0:32 suites/425 passed/0 failed.
Its source includes both the leaf checks and permission-failure repair; Ubuntu
amd64 integration execution was still pending at that local validation point.

Tests cover both certificate/key destinations in self-signed and external modes,
retained foreign links/absent targets, no counterpart publication or leaked
temporary pair, and unrelated sentinel preservation. No CLI, configuration, pin,
URI or VERSION changes. Existing outer transaction/caller cleanup remains in use;
these pre-existing-leaf checks do not coordinate arbitrary privileged writers.
Private logs: `/tmp/pnm-stage15-tls-links.0cfiMChK/`. CI additionally records curl
version for future transport evidence; the stage14 record does not infer an
unrecorded curl build version from the runner label.

Published sourceb3e223d730c773b61da8512e4574b29ece9083fb passes
[run40460290093](https://github.com/mrshyi/pnm/actions/runs/40460290093),
push/attempt1, completed success. Jobs122042999846 (Ubuntu22.04) and122042999546
(Ubuntu24.04) each pass normal check/release32 suites/425 wrappers per gate,
ShellCheck, privileged48, acquisition7, real systemd8 and official-Core10.
TLS contributes16 wrappers within425; layers/repeated gates are not summed as
unique cases. The ordinary five root-only labels remain intentional, with their
separate privileged suites actually executing. Recorded curl versions are7.81.0
on22.04 and8.5.0 on24.04. Remaining full installation, account, storage, reboot,
external-client and deferred Debian boundaries are unchanged.

## Stage 16: no-replace TLS pair publication

Validation base4819a79 (stage15 result record, runtimeb3e223d). Controlled
interleavings reproduce six failures: a destination appearing after precheck
could be overwritten by external import, receive a nested candidate, or be
removed after self-signed validation failed. The initial TLS run reports16
passed/6 failed. Both staging paths now validate private candidates first and
reuse backup publication's `ln -T` no-replace pattern. Candidate inode anchors
allow compensation to remove only owned links while preserving foreign changes.
External import copies to private candidates instead of final destinations.

Focused TLS passes25/25, including both leaves/modes across raced files,
directories and links, foreign replacement with either successful or failed
second publication, a failed command after link creation, and mismatched external
input without publication. Sandbox install passes12/12. Standard and targeted
ShellCheck pass. Protected staging parents are assumed; these tests do not prove
arbitrary privileged concurrent writes or physical storage failure recovery.
Local `make release-check` exits0:32 suites/434 passed/0 failed. The five
ordinary root-only skips remain explicit.

Source dfb561f4eae75574536c5c59b4ff694f4c3ab471 passes
[run40465124191](https://github.com/mrshyi/pnm/actions/runs/40465124191),
push/attempt1. Jobs122058554836 (Ubuntu22.04) and122058554499 (Ubuntu24.04)
each pass normal check/release32 suites/434 per gate, ShellCheck, privileged48,
loopback acquisition7, real systemd8 and official-Core10. No failed summaries;
this remains isolated integration rather than full managed installation,
persisted reboot or external-client acceptance.

## Stage 17: Hysteria2 binary staging publication

Validation basedfb561f4eae75574536c5c59b4ff694f4c3ab471. The shared staging
helper used by host installation and Core update still
copied directly to `hysteria`. Four added regressions reproduce replacement of
existing files/links, accepting a destination directory, and retained executable
bytes after a failed copy (15 passed/4 failed). Stage privately, verify executable
access, then reuse the existing `ln -T` no-replace pattern. Occupied destinations
return73 with no success path; owned failed-copy candidates are removed.

Focused staging passes19/19, covering both preexisting and late destinations,
preserved target/marker bytes, no nested executable or candidate leak, and copy
failure after writing bytes. Standard and targeted ShellCheck pass. Caller
version/configuration checks and managed transaction boundaries remain intact;
no Core binary is executed by these synthetic staging tests. Local
`make release-check` exits0:32 suites/438 passed/0 failed, retaining the five
ordinary root-only skips. Ubuntu integration was pending during local preparation.

Source c4e906ccade0fca843405daa6480f14655fde1cf passes
[run40465705895](https://github.com/mrshyi/pnm/actions/runs/40465705895),
push/attempt1. Jobs122060468649 (Ubuntu22.04) and122060468868 (Ubuntu24.04)
each pass normal check/release32 suites/438 per gate, ShellCheck, privileged48
without skips, loopback acquisition7, real systemd8 and official-Core10.
All70 shell-suite summaries per job report zero failures; repeated gates and
execution layers are not added together as unique cases. Remaining installation,
managed-account/NSS, physical storage, reboot, external-client and deferred
Debian acceptance are unchanged. Phase3 remains open.

## Next priorities

Main-flow preparation update (U-02, 2026-10-27): the independent VM worker's
Debian13-only OS check prevented Ubuntu boot admission. It now follows the
managed Debian/Ubuntu version policy and reports actual OS identity; VM isolation
and per-boot approval are unchanged. The existing clone driver carries its source
manifest into the guest; CLI cases compare actual entry/library files before
and after the successful lifecycle and report the manifest digest/file count.
No additional fault campaign or product feature was added. These preparation
changes do not clear U-02–U-08's environment/asset/authorization blocks.

Local preparation suite:35 total,27 executed/8 root-only skipped, exit0.
Existing L1 main-flow suites also pass: sandbox install12/12, Core operations15/15,
host apply14/14. Four changed Python sources parse successfully; workflow YAML
retains both Ubuntu versions and adds the non-deploying preparation suite.
These are local fixture/L1 results, not full CLI deployment or reboot acceptance.

Actual source0ff5762bad677511d86e5d20cdbbe6947f08b09e passes
[run40477522467](https://github.com/mrshyi/pnm/actions/runs/40477522467),
push/attempt1. Jobs122099309741 (Ubuntu22.04) and122099309921 (Ubuntu24.04)
each pass the new preparation suite35 total/27 executed/8 skipped and existing
normal check/release32 suites/438 per gate, ShellCheck, privileged48, transport7,
real systemd8 and official-Core10. All70 shell summaries per job have zero
failures. Root-only preparation skips remain explicit. No new U-02–U-08 execution
is claimed; the next actual operation is authorized disposable-guest installation,
not another speculative hardening increment.

U-03/U-06 main-flow implementation update (2026-10-27): the existing clone/VM
driver now accepts `external-ca` and `external-ca-mismatch`. The first follows
the normal lifecycle with a private CA-signed SAN certificate; the second checks
one wrong-key installation refusal and complete rollback before retrying the
matching pair. External source bytes/metadata and normal CA URI verification
must be preserved. The normal backup/restore path now also refuses one damaged
archive without changing managed resources or live Core state before the trusted
round trip. Existing CLI/environment inputs and transaction facilities are reused;
no product runtime or command format changes and no expanded fault matrix.

Local preparation suite:36 total,28 executed/8 root-only skipped, exit0, including
actual OpenSSL chain/hostname validation and PNM pair validation of correct/wrong
keys. L1 suites pass: archive9, backup9, restore17, restore recovery12 and sandbox
install12. Standard ShellCheck passes and four changed Python sources parse. Full guest execution of these new
paths remains pending; U-03/U-06 are still BLOCKED in the closeout table.

Actual sourced976f57202764aa2d1aac20a17c15f20c5743e44 passes
[run40482079293](https://github.com/mrshyi/pnm/actions/runs/40482079293),
push/attempt1. Jobs122114610802 (Ubuntu22.04) and122114610278 (Ubuntu24.04)
each pass preparation36 total/28 executed/8 skipped, normal check/release32
suites/438 per gate, ShellCheck, privileged48, transport7, real systemd8 and
official-Core10. All70 shell summaries per job report zero failures. This runs
the CA fixture validation and existing selected integration; the newly scripted
external-ca CLI installation/compensation and damaged-restore guest paths were
not executed by CI and remain unaccepted. No U-02–U-08 PASS is inferred.

U-03 user-facing installation repair (2026-10-27): node initialization exposed
external-ca but installation accepted no public source-file arguments. Added
paired `--tls-cert FILE --tls-key FILE` inputs, scoped to the invocation and
forwarded through existing deployment/TLS staging. Pair and configured or legacy
inferred SAN checks run after ordinary preflight and before deployment. Bad or
missing inputs return preflight2; malformed argument pairs return64. Self-signed
defaults, internal environment compatibility and managed transaction behavior are
preserved. No credential/configuration/URI format or VERSION change.

Five new L1 regressions reproduce the entry gap (14 existing passed/5 failed),
then pass19/19 after repair, including paths with spaces, JSON preview, legacy
name inference/input variables, missing/wrong inputs and default self-signed
behavior. Actual CLI parser/help tests pass12/12 (one normal root-only skip).
Preparation passes36 total/28 executed/8 root-only skipped. Standard and targeted
ShellCheck pass. Guest scenarios now use the public arguments and require wrong
keys to refuse before any write transaction rather than exercising rollback.
Local `make release-check` exits0:32 suites/444 passed/0 failed, retaining the
five ordinary non-root skips. Full Ubuntu guest installation/reboot remains
BLOCKED.

Actual source61c5a86b7b35fd91496f692cd1c763b427c6070c passes
[run40485517751](https://github.com/mrshyi/pnm/actions/runs/40485517751),
push/attempt1. Jobs122126204236 (Ubuntu22.04) and122126203737 (Ubuntu24.04)
each pass normal check/release32 suites/444 per gate, standard ShellCheck,
privileged49 (CLI12/read1/TLS8/transaction28), preparation36 total/28 executed/
8 skipped, transport7, real systemd8 and official-Core10. All70 shell summaries
per job report zero failures. The newly public install inputs are covered by
CLI/preflight L1 tests; actual full guest installation and U-02–U-08 remain
unaccepted. No installation/deployment was performed on the development host.

U-03 interactive entry update (2026-10-27): the menu's install action previously
called installation without external certificate inputs. New uncommitted
external-ca nodes now prompt for both file paths and forward the public arguments
to the same installer. Missing input never invokes installation; self-signed
nodes retain the old action without extra prompts. Node-init guidance also
mentions the required external-ca arguments. No alternate installation framework,
new protocol or expanded acceptance scope was added.

Local CLI/menu tests pass15/15 with the ordinary real-update root-only skip.
Standard ShellCheck and targeted test ShellCheck pass. Local `make release-check`
exits0:32 suites/447 passed/0 failed, with the five ordinary non-root skips.
The prior61c5a86 CI record above applies only to that committed source.

Actual sourcece0faf7efedd86f8d4516e605220e3cc7a4a8f4d passes
[run40526987902](https://github.com/mrshyi/pnm/actions/runs/40526987902),
push/attempt1. Jobs122269120758 (Ubuntu22.04) and122269121398 (Ubuntu24.04)
each pass normal check/release32 suites/447 per gate, ShellCheck, privileged52
(CLI15/read1/TLS8/transaction28), preparation36 total/28 executed/8 skipped,
transport7, real systemd8 and official-Core10. All70 shell summaries per job
report zero failures. Menu cases run against temporary config fixtures and a
recording installer stub; they prove prompting/argument/cancellation behavior,
not full guest deployment. U-02–U-08 stay BLOCKED. The earlier Git approval
quota failure was resolved through the normal approval path; no bypass was used.

1. Pin the latest validated runtime baseline above and the finite U-01–U-08
   checklist. Change it only for reproduced in-scope main-flow defects.
2. Obtain explicitly authorized disposable Ubuntu22.04/24.04 amd64/systemd boot
   fixtures and independently verified approved Core/backup assets; record what
   installation, account changes, scoped faults and guest reboot are authorized.
   Do not provision the development host or reboot the hosted CI controller.
3. Execute only U-01–U-08, reusing existing integration harnesses where suitable;
   record per-OS/ID PASS, FAIL or BLOCKED and source identity. A missing prerequisite
   is BLOCKED, not a new open-ended hardening stage or a claimed pass.
4. Fix only reproduced in-scope defects, rerun affected checks and required gates,
   then issue one closeout table with remaining explicit deferrals. Do not rerun
   unchanged gates solely to increase counts or add speculative fault campaigns.
5. Phase4–6 scoped development, Phase7 local preparation and current-runtime Ubuntu
   CI are complete. Execute the finite authorized Ubuntu acceptance when its
   environment/assets are supplied. Keep Debian and optional
   external checks deferred. Production changes, single-Core provisioning,
   firewall automation, encryption/key custody and publishing remain outside this increment.
