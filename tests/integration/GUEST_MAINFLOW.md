# Private guest main-flow checks

Current Ubuntu work is limited to [U-01–U-08](../../docs/ACCEPTANCE_PLAN.md#ubuntu-closeout).
For U-03, `PNM_GUEST_SCENARIO=external-ca` selects the normal lifecycle using a
private test-CA-signed DNS-SAN certificate. `external-ca-mismatch` starts in a
separate fresh clone, first imports that certificate with an independent wrong
key and requires preflight CLI2, unchanged authority/NSS and no write transaction,
then retries with the matching key through the normal lifecycle. Both now pass
the public `--tls-cert FILE --tls-key FILE` installation arguments.
The source certificate/key must remain unchanged, and the external-ca URI must
retain SNI without insecure/pin bypass. Local certificate checks prove the fixture
chain and pair only, not guest installation or public client trust.

For U-06, the shared normal lifecycle now rejects one synthetic damaged backup
with CLI78 and unchanged managed files/Core processes before the existing trusted
backup→change→restore round trip. Its result includes `damaged_backup_refused`;
the external scenarios also identify the TLS mode and whether the mismatch was
actually checked. These remain opt-in guest operations requiring the existing
approved environment/assets. They do not enlarge U-01–U-08 or run in default CI.

The independent VM boot worker recognizes the managed platform policy, including
Ubuntu22.04/24.04, and reports the actual OS identity in its handshake. Platform
policy fixtures do not prove that a Ubuntu VM was prepared or booted. Existing
VM nonce, source-worker digest, isolation and per-boot approval remain required.

The main-flow clone driver copies its runtime source digest map to the private
guest `/opt/pnm-source-hashes.json`. The CLI cases verify `/opt/pnm` against that
map before any CLI operation and after the successful lifecycle. Results include
only the source file count and manifest digest. Independent VM preparers must
carry the same map for their exact copied source; no legacy fixture is inferred
to have it. This source check does not authenticate Core or backup assets.

`make test-commit-storage` is a separate explicit Linux-root publisher check that
does not clone or boot a guest. Its child mount namespaces own a64KiB tmpfs with
64 inodes and nodev/nosuid/noexec. Synthetic protected records exercise the
unchanged marker helper: an observer exhausts only tmpfs inodes immediately
before real mkstemp, or data blocks before the real candidate write/flush.
Require observed kernel ENOSPC28 and publisher73, retained complete pending
record, unchanged original records, no marker/candidate, exact owned unmount and
unchanged parent namespace/mount table and host NSS/dpkg hashes. Only fixed labels
and counts are reported; protected per-run evidence remains under /var/tmp.
This is a bounded L1/Linux publisher slice, not full deployment compensation,
independent-VM ENOSPC or physical EIO. Default `make check` does not run mounts.

The same target also tests the earlier uncertainty-file creation and write.
Inode exhaustion before the original pending os.open must leave no pending file;
data exhaustion at its exact empty root0600 FD must leave an empty incomplete
file. Both require actual ENOSPC28/publisher73 and no marker/candidate. Report
pending_state as absent, empty or complete; an empty file is not durable complete
uncertainty. The two candidate cases still require the complete pending bytes.
All four cases retain the same bounds, owned unmount and parent/host checks.
The worker also checks the live parent's actual mount namespace; a supplied
namespace number alone cannot authorize a mount in the caller's namespace.

The independent VM lifecycle worker also accepts `deployment-space-full`.
Its explicit publisher variant requires this boot's approved VM identity,
root ext4 /dev/vda and a filesystem of at most2GiB before creating an anonymous
root0600 filler on the transaction's filesystem. At each actual empty pending
and candidate FD in separate deployment attempts, bounded fallocate operations
exhaust available blocks; require original
publisher ENOSPC28/73. Closing only the owned anonymous filler must recover
space before recording evidence and returning to the real CLI compensation.
For the pending-write attempt, keep the filler through buffered stream close,
then require the retained pending file to be empty. The candidate-write attempt
still requires its complete pending record. The real publisher and file APIs
are unchanged during both VM attempts.
Require original CLI73, complete resources/NSS/directory/unit/applied rollback,
retained pending/no marker and terminal ROLLED_BACK, then normal14 checks and7
same-disk reboot checks without state repair. Host/container execution refuses
before allocation. The fault helper rejects mapped guests even when this
VM-only scenario is selected by the CLI. Physical media EIO and other failure positions remain
separate from this controlled virtual-disk space refusal.

The VM-only `deployment-inode-full` scenario fills the approved root ext4's free
inodes with empty files in a new protected evidence directory. It requires
`f_favail == 0` while data blocks remain. It observes two real ENOSPC positions
in sequence: initial uncertainty-file creation (no pending record remains), then
commit-candidate creation (the existing pending record remains). Each refusal
removes only its exact owned filler files before full CLI compensation. The
normal lifecycle and same-disk reboot must pass afterward without state repair.
The filesystem is bounded to2GiB; the filler requires at most262144 free inodes
at admission and has a120-second deadline. This is virtual ext4 inode exhaustion,
not physical media failure.

The VM-only `deployment-acquisition-failures` scenario runs7 actual first-install
refusals: partial HTTP body, untrusted fixture certificate and bad checksum for
each Core, plus a checksum-approved non-ZIP Xray body. Reuse the existing bounded
loopback HTTPS server and original curl/install/staging. Temporarily hold only
the verified subject cache inode in protected evidence; never overwrite an
unexpected cache destination when restoring it. Require curl18/60 with CLI69,
checksum/staging78, exact transport counts, absent runtime/applied/markers,
original authority/primary NSS/directories/units and peer cache, and terminal
outer rollback. The ZIP case must retain verified bad-cache evidence and all
four actual owned-account APPLIED/RESTORED pairs. Only declared test pins,
transport and original cache fixtures are restored for the normal14 checks;
no service/NSS/runtime/transaction repair is allowed. Then run7 same-disk reboot
checks and the existing image/host cleanup verification. This is controlled
first-install acquisition evidence, not upstream DNS/PKI outage or arbitrary
executable safety. The native CLI driver does not expose this VM-only scenario.

`deployment-version-failures` extends that same VM fixture to9 refusals using
the separately verified official prior assets. The declared current version and
prior asset's correct checksum deliberately disagree for each Core. Actual
staging must diagnose the specific version mismatch and refuse78 before either
managed binary publication, with all4 actual account creation/recovery pairs,
retained verified rejected cache, complete outer compensation and absent runtime.
Then the original approved fixtures permit normal14 checks and7 reboot checks.
The existing7-case acquisition scenario remains available unchanged.

This explicit opt-in test clones a separately prepared trusted Debian 13 boot
fixture. It never bootstraps packages, downloads assets, installs host packages,
binds host directories or changes host accounts/network/firewall configuration.
Default `make check` does not run it. It currently targets the verified hybrid
WSL cgroup layout; another layout fails closed.

`PNM_GUEST_SCENARIO=deployment-progress-readonly` runs the install CLI in its
own private mount namespace. A guarded trace observes the unchanged publisher's
final directory-sync return after uncertainty removal, then binds only its
regular progress journal read-only in that namespace. The real Bash append
encounters EROFS; install must still return0 with its committed-progress warning,
retain a product-verified marker, have no uncertainty or rollback promotion, and
leave the parent's mounts unchanged. The normal14-case lifecycle then checks
real Core/account/configuration/binding/health behavior, adding one refusal
assertion. The same scenario can run under the approved independent-VM lifecycle
worker, followed by the existing7 reboot checks. The bind ends with the owned
CLI namespace; no host or manager namespace is remounted. It is a selected real
derived-journal write refusal, not physical media failure acceptance.

`PNM_GUEST_SCENARIO=deployment-rename-readonly` reuses the publisher-only private
namespace and complete deployment compensation checks. After the actual marker
candidate is written/fsynced/closed, only that publisher sees a read-only bind
of its transaction directory. The observer must identify actual os.replace
EROFS for the exact source and commit.env destination, and remove its owned
mount before returning. CLI73 must accompany full compensation, no marker and
retained forensic uncertainty; the normal14-case retry/lifecycle then runs
without fixture repairs. The independent-VM route additionally runs7 reboot
checks. The original pending-create fault variant remains mapped-container-only;
only explicit late-publisher variants receive the approved VM publisher guard.

`PNM_GUEST_SCENARIO=deployment-marker-failures` runs candidate creation, candidate
write and the established rename refusal in sequence, each through a real install
and complete compensation before the next attempt. Creation enters the owned
read-only directory bind at the actual tempfile.mkstemp call and observes EROFS.
Write validates the new root0600 candidate's exact descriptor/inode, then sets
only the publisher subprocess's soft RLIMIT_FSIZE to0 while preserving its hard
limit and Python's existing ignored SIGXFSZ policy. Actual write/flush must fail
EFBIG; the observer restores and verifies the original limits before writing
evidence, and the parent limits must remain unchanged. Require original73,
retained uncertainty without marker, full resources/NSS/directories/services
compensation and terminal rollback for all three faults, then normal14 lifecycle
and, on the independent VM,7 same-disk reboot checks. No product file API is
replaced. EFBIG is a process-scoped file-size refusal, not physical ENOSPC/EIO.

The separate `guest_vm_boot.py` worker is a boot-only probe for a privately
prepared independent supported Linux VM. The earlier Debian preparation is described in the
[VM plan](../../docs/history/plans/2026-10-25-independent-debian-vm.md).
It does not install PNM or extend the mapped-container acceptance route. Its
read-only guard requires the expected protected worker hash/kernel/root UUID,
QEMU firmware nonce, independent boot ID, systemd PID1, QEMU DMI identity and
loopback-only networking before opening serial or issuing power commands.
Only the exact matching live QEMU/disk owner may approve the bounded serial
handshake. Success requires evidence persistence, actual clean poweroff and host
verification; a ready message alone is insufficient. Ordinary host execution
refuses77 before serial/power controls, covered by the host guard suite. This
worker alone is not a VM launcher; trusted tools, image preparation and owned
storage/process cleanup remain prerequisites.

`guest_vm_lifecycle.py` reuses that guarded serial handshake and the existing
14-case CLI lifecycle on an independent kernel. It grants a mode-0600 approval
record only after the matching live host handshake; the actual cases accept
the VM route only with that boot's instance/boot ID. The mapped-container guard
remains unchanged. The first guest requests reboot; the owner retains the same
anonymous disk while QEMU exits on -no-reboot, then explicitly launches the
second kernel with a fresh nonce. Reboot acceptance compares both changed
service invocations and persisted resource/applied fingerprints, requires stale
URIs to remain withheld through ordinary restart, and checks independent apply
and both real listeners before clean poweroff. Its private records and outputs
may contain credentials and must remain inside the protected guest evidence and
fully encrypted image. Default checks never launch this worker.

`guest_vm_abrupt.py` pauses the unchanged real deployment publisher after marker
rename while uncertainty remains. It persists the observed pre-stop baseline,
rechecks the pending state and announces the window over the same approved
serial channel. The live host owner may then stop only that QEMU with SIGKILL;
the guest never substitutes a CLI signal for stopping its kernel. The next boot
requires intact uncertainty, preserved managed resources and actual fresh
writer/links/show/check refusal without output or mutation. Progress journal
appends may be lost or torn by this stop; the test observes and retains those
bytes instead of repairing them or treating the journal as commit authority.
This is a selected abrupt-VM interruption slice, not physical media or power-loss
acceptance. General account/mount/startup fault helpers remain container-only;
only the publisher observer additionally accepts this boot's approved VM guard.

The same lifecycle VM worker can run the existing `core-update` scenario with
separately verified prior/current assets:14 lifecycle and12 partial-download/
certificate-trust/checksum/update/rollback/swap-forward assertions. The update helper additionally accepts the
approved VM guard; fault-injection helpers keep their original restrictions.
The reboot baseline includes both previous files and checks actual previous
binary versions against previous.env. The HTTPS endpoint remains the private
loopback transport fixture, so this does not prove upstream acquisition or
external client reachability.

Prerequisites are the signed, private rootfs and successful native boot fixture
described in [the preparation plan](../../docs/history/plans/2026-10-23-container-mainflow.md):
root-owned mode-0700 parent, canonical `rootfs`, successful `boot-result.json`,
and the dedicated enabled `pnm-boot-probe.service` that executes
`/usr/bin/python3 /opt/pnm-boot-worker.py`. The rootfs must be a trusted clean
baseline without PNM resources/accounts. Its package executables and services
are trusted input, not authenticated by the JSON report. Supply a separately
trusted root-owned native nspawn executable and the existing exact pinned Core
cache (see `real_core_versions.json` for amd64 or
`real_core_versions_arm64.json` for arm64). The driver selects native architecture
and refuses a foreign manifest; keep separate caches and matching native boot
fixtures. Do not use an arbitrary downloaded image.

For the locally prepared fixture (Linux root shell):

```bash
make test-guest-mainflow \
  PNM_GUEST_BASELINE=/var/tmp/pnm-debian-guest.4w7y455l \
  PNM_NSPAWN=/var/tmp/pnm-container-tools-20261023/tools/usr/bin/systemd-nspawn \
  PNM_REAL_CORE_ASSETS=/var/tmp/pnm-realcore-discovery
```

Set `PNM_GUEST_SCENARIO=deployment-failure` on the same command for the failure
and retry scenario. It first hides openssl only from a private test PATH and
requires refusal before managed writes. A guest-only Xray startup delay then
crosses the supported 30-second deployment commit window, after real dual-Core
post-health. It requires exit77, complete live/resource/account/directory rollback,
no applied or commit promotion, and completed rollback receipts. Only its owned
delay drop-in is removed before retrying the original 14-case main flow. The
default scenario remains `lifecycle`; no production function is replaced.

`PNM_GUEST_SCENARIO=configured-ports` uses TCP10443/UDP18443, occupies unrelated
default443/8443 listeners in the private guest, and first checks that conflicts
on the actual selected ports refuse before any managed write. It then runs the
real installation/lifecycle/restore, verifies actual listeners and URI ports,
and requires both unrelated default sockets to remain untouched. The independent
VM worker also accepts this scenario, requiring14 normal+2 port checks before
its7-check same-disk reboot. The private reboot baseline records the expected
ports after comparing persisted node values; post-reboot listener checks use
TCP10443/UDP18443. The unrelated fixture sockets belong to the pre-reboot process
and are not expected to survive the new kernel.

`PNM_GUEST_SCENARIO=account-reuse` first creates valid system identities only
inside the guarded clean guest. It then runs the existing dependency-refusal,
late deployment compensation and full lifecycle cases. Complete NSS file bytes
and metadata must stay unchanged from that preexisting baseline, real Core
processes must use the expected UID/GID, and all transaction account ledgers must
remain empty. This covers valid reuse; it does not simulate account-tool failures.

`PNM_GUEST_SCENARIO=dependency-refusal` temporarily hides each of the19 declared
preflight prerequisites using only its own private PATH links. The actual JSON
install command must refuse2 in the corresponding class; original authority/NSS
fingerprints, PNM inventory/transaction set and absent Core/account/service state
must remain unchanged. Environment and links are restored per case, followed by
the normal14-case lifecycle. System binaries/packages are never removed or mocked.

`PNM_GUEST_SCENARIO=deployment-startup-failure` rejects the first real Xray start,
then the first HY2 start after Xray activation. Both deployments must restore
authority/NSS bytes and metadata, directory identities, absent Core resources,
inactive/not-found/PID0 services and no applied/commit promotion, with completed
rollback receipts. Safe structured observations are retained before assertions.
The fault fixture never resets failed units itself. The normal14-case lifecycle
then proves a clean retry after both completed compensations.

`PNM_GUEST_SCENARIO=deployment-listener-failure` uses a validated12-second
managed-start delay for each Core. A bounded observer confirms active state and
absent TCP/UDP listening; the failure must return before that managed wrapper
could exec the Core. Both lifecycle phases must complete, then the target Core's
own check and post-health phase fail78. The same full compensation assertions
and subsequent normal14-case lifecycle apply. Probe default delay remains3 seconds.

`PNM_GUEST_SCENARIO=runtime-evidence` restarts each actual Core outside PNM,
requires show/links to retain unconfirmed applied state and withhold only that
Core's URI, and checks that PNM restart cannot promote it. Fully validated apply
then rebuilds the confirmed binding. A separate real flock holder collides with
the writer and protected link reader; both refuse without output/Core changes
or a new transaction, then normal operations resume after release. This covers
held-lock contention and external service restart. The independent VM lifecycle
worker also accepts this existing scenario: require14 normal+5 runtime/lock
checks before the separate7-check same-disk reboot. This does not establish all
timing interleavings, external clients or other supported platforms.

For distinct-version testing, set `PNM_GUEST_SCENARIO=core-update` and
`PNM_PREVIOUS_CORE_ASSETS=/var/tmp/pnm-update-core-assets`. That separately
acquired mode-0700 root-owned cache must match `previous_core_versions.json` on amd64 or
`previous_core_versions_arm64.json` on arm64:
Xray v26.9.30 and HY2 v2.12.3. The existing asset verifier checks both old and
current pairs. The clone initially installs the old pair, then explicitly approves
the current pair only in its own versions.conf. It runs each real Core through
partial-download and certificate-trust refusal, checksum refusal,
different-version update, rollback and rollback swap forward,
checking resource/version/invocation/applied state and the peer's previous-state
metadata as well as its runtime resources. Final links/health must be ready.

This scenario uses real curl/TLS/checksum/staging with a private lo HTTPS CONNECT
fixture that serves only the two checked release assets. Its CA/proxy settings
exist only in CLI process env; host trust/network is unchanged. Only github.com
and the exact release paths are accepted. Headers, connection count, total request
duration and thread/socket retirement are bounded. This transport substitution
does not establish upstream DNS/PKI/download behavior or external clients.

For each Core, the permitted path first returns fewer bytes than Content-Length
with an actual TLS close_notify; real curl must refuse18 and update69. Then the
CLI uses the guest's unchanged public CA bundle, which must reject this fixture's
fresh private self-signed certificate with curl60/update69 before any HTTP GET.
Only one budgeted unknown-CA TLS alert is accepted for that attempt; other server
errors fail the fixture. Both refusals must preserve both Cores' complete state,
previous pair and service invocation, create no publication transaction and leave
no new temporary download directory. Restore only the test transport settings,
then execute the established checksum/update/rollback/swap path. No curl/API or
product result is replaced, and no host/guest system trust store is modified.
The isolated-network regression also checks subsequent normal retrieval and
bounded retirement of all owned sockets/threads. This covers update acquisition;
first-install acquisition/ZIP failures remain separate.

Set `PNM_GUEST_SCENARIO=core-update-failure` with the same previous-asset cache
to add real startup-failure compensation for each Core's update and rollback.
A guest-owned `ExecStartPre` talks to a bounded private lo probe: the first start
fails and the compensation start succeeds. `Restart=no` prevents automatic
restarts from consuming the probe. Binary/configuration/previous metadata,
confirmed applied evidence, the unchanged peer and terminal rollback receipts
are checked before continuing the successful update/rollback sequence. These
failures precede previous-state publication; they do not test its late failure.

Set `PNM_GUEST_SCENARIO=restore-failure` to reject HY2 startup after restoring
the twelve archived resources and starting Xray. Both original generations,
numeric file/directory metadata, identities, service policy and confirmed applied
bindings must recover, then a trusted restore retry must succeed. The probe keeps
the actual service account/capability/filesystem restrictions. Its uniquely owned
drop-in, program, socket and thread are retired after the attempt. Persistent
recovery failure and disk/commit/crash faults require separate scenarios.

Set `PNM_GUEST_SCENARIO=startup-readiness` to wrap each real Core's `ExecStart`
with a three-second delay, preserving its service account and sandbox. The test
calls the production local startup gate and retains structured health results.
The same InvocationID must later remain healthy without another restart or edit;
managed resource/applied bytes and the peer stay unchanged. This intentionally
does not promote evidence after the fixture's external restart. Ordinary
diagnostics remain immediate. The wrapper uses ExecStart because ExecStartPre
would delay systemctl's completion and could not expose this readiness window.

The `core-recovery-failure-xray` and `core-recovery-failure-hysteria2` scenarios
use the same previous-asset cache as `core-update`. After the normal distinct-
version trajectory, both rollback starts are rejected. The target must remain
failed while binary/previous/applied bytes and the peer are preserved. The
`restore-recovery-failure` counterpart checks restored ordinary resources,
reconfirmed Xray and failed HY2, without claiming complete service recovery.
Both remove their owned fault and require real writes/links/show/check to remain
blocked by retained uncertainty, with no protected stdout or state changes.
Expected-failure acceptance is marked `expected_recovery_required=true`; a
passing test result here does not mean the target service is healthy. Execution
status and validation limits are recorded in TASKS, not inferred from this guide.

Each invocation creates a private `pnm-install-guest.*` clone under `/var/tmp`
by default. Optional `PNM_GUEST_WORK_DIR` must be a canonical absolute root-owned
mode0700 POSIX directory. Unsafe paths are refused before fixture access; raw
DrvFS is unsuitable. The driver does not create or mount volumes. Each invocation
also creates a
unique native scope, rotates only that clone's machine ID, copies current PNM
source and checked asset bytes, and compiles the guest scripts before boot.
It replaces only the clone's dedicated test unit with a 690-second limit; the
baseline's 80-second boot probe is too short for lifecycle cases. Guest cases
have a separate 600-second timeout and the host deadline remains 720 seconds.
Both guest identity checks and host observation of the owned payload cgroup
must pass before a private one-use approval enables actual CLI writes.
No production function or account lookup is mocked. The guest has only lo and
uses PNM's verified offline asset cache; no traffic or network acquisition is
tested. Guest poweroff is guarded by its identity; the parent controls only its
own child and, if necessary, the verified transient scope invocation.

The cases cover init/validate/preview/install, actual account/process privilege
and applied binding, links and health, repeat-install refusal, per-Core restart
and changed-config apply with peer preservation, and protected trusted backup/
restore. The fixture deliberately changes its own HY2 password; no deployed
credential is involved. The backup digest is retained separately and checked
before restore. This is local trusted-backup round-trip evidence, not a signature
or adversarial provenance test.

`PNM_GUEST_SCENARIO=tls-access` adds real hysteria-account read failures after
the normal lifecycle. It checks wrong private-key ownership and a non-traversable
TLS directory with correct leaf metadata. Actual check/startup gates must fail
without changing either Core, receipts, NSS or managed file identity, or exposing
credentials. Owned fixture metadata is restored in finally; an actual HY2 restart
then refreshes its applied binding, with Xray unchanged and healthy links/checks.
This does not prove a currently running process has reloaded TLS material.

`PNM_GUEST_SCENARIO=core-interruption` observes delayed real Xray startup, then
signals only the exact CLI child/session created by its call helper. TERM must
preserve143, compensate and restore a confirmed binding with peer unchanged.
SIGKILL must retain the unfinished transaction and prior applied bytes; after
listener stabilization and owned drop-in removal, writer/show/links/check must
refuse70 without output or mutations. The final expected recovery requirement
is an interrupted journal, not a claim of automatic recovery or VM/kernel reboot.
Use `core-interruption-hysteria2` for the corresponding UDP/HY2 case with Xray
as the unchanged peer. Each variant requires a separate fresh guest.

`PNM_GUEST_SCENARIO=restart-readiness` runs the ordinary CLI restart for each
Core with a guest-owned delayed real ExecStart. At command return its actual
TCP/UDP listener must exist, applied binding must match the new invocation,
target resources must be unchanged and the peer untouched. Exactly one startup
attempt is allowed, followed by both links ready after removing the test drop-in.

`PNM_GUEST_SCENARIO=deployment-term` interrupts the exact owned install CLI
session during each Core's first start. It requires143, APPLY_FAILED rc143,
complete original resource/account/service recovery and a normal14-case retry.
`deployment-sigkill` uses a separate fresh guest and kills that CLI group during
the first Xray start. It retains unfinished deployment evidence and no applied/
commit promotion; actual writer/links/show/check must refuse70, identify the
unresolved deployment and disclose no output or mutate candidate state. Its
successful test report explicitly has `mainflow_completed:false` and
`expected_recovery_required:true`. It does not run the normal lifecycle afterward
or perform automatic recovery. Neither variant signals host/user processes.

The parent prints a safe JSON summary and leaves `boot-result.json`, source
hashes and protected evidence under the new fixture. Raw CLI/Core output,
configuration and backups can contain secrets; do not print or publish them.
Successful shutdown must leave the transient scope not-found, no fixture mounts,
and unchanged host account/package databases. Fixtures are retained for review;
there is no automatic recursive cleanup. Time-sync checks are not collected by
the current PNM check dispatcher. Distinct versions and the one deadline-failure
case require their named scenarios above. VM/kernel reboot, other injected
failure positions, deployed-source identity and external clients remain separate.

`test_guest_mainflow_guard.py` runs ten offline checks before boot: explicit
opt-in, enabled assertions, protected regular-file/link behavior, nonblocking
FIFO rejection, retirement of a PIPE-holding descendant on command timeout,
asset header limits, guest-only start-fault refusal before host mutation/network,
custom work-directory safety, and isolated-network asset/TLS positive/refusal/cleanup.
It also checks the scoped publisher observer's path/errno filtering and unchanged
control flow with synthetic exceptions; those checks are not real IO acceptance.
The latter proves a distinct network namespace before raising only that child's
lo; no host socket/interface is created or changed. It covers incomplete CONNECT/
TLS, wrong target/path, and a CA-verified fixed response with complete retirement.
Each CLI call owns a new session; bounded TERM/KILL retires that command group
on timeout, while its Core services remain under the guest systemd manager.

`PNM_GUEST_SCENARIO=core-update-term` adds TERM at actual service startup after
binary publication for each Core's update and rollback. It requires143, restored
binary/config/previous bytes and metadata, the original actual version, refreshed
applied binding, completed compensation and an unchanged peer; the normal
distinct-version matrix then continues. Four separate fresh-guest variants,
`core-update-sigkill-xray`, `core-update-sigkill-hysteria2`,
`core-rollback-sigkill-xray` and `core-rollback-sigkill-hysteria2`, retain the
candidate version and prior applied/previous records without a commit. After
retiring the owned HTTPS asset server, actual writer/links/show/check must refuse70
with the exact unresolved operation and preserve resource identities and runtime
state. These variants report the completed initial main flow separately from
`update_matrix_completed:false` and `expected_recovery_required:true`.
They do not cover late previous/metadata/commit publication or restore interruption.

`PNM_GUEST_SCENARIO=restore-term` changes and applies an actual Xray target so
the trusted archive differs from the pre-operation generation. A guest-owned
three-second ExecStartPre keeps systemctl waiting while the exact CLI session is
signalled, retaining the real Core ExecStart and Type=simple. At each Core's
restore startup, TERM must preserve143, compensate all resource bytes and
metadata, directory identities, NSS and previous state, and confirm both original
runtime bindings/listeners. A trusted restore retry must then succeed.
`restore-sigkill-xray` and `restore-sigkill-hysteria2` each require a fresh guest.
Both retain published archive resources, old applied records and an unfinished
core-restore journal. The Xray window leaves HY2 inactive/PID0; the HY2 window has
both new actual service generations. Once the owned delay/drop-in is removed,
writer/links/show/check refuse70 for that exact unresolved operation without
output or state changes. Reports separate the completed initial lifecycle from
`restore_matrix_completed:false` and `expected_recovery_required:true`.
These are startup-window tests, not partial-file-write or storage durability tests.

`core-publication-previous`, `core-publication-metadata` and
`core-publication-applied` each use a fresh dual-version guest and target one
late publication point for both Cores' update and rollback. A one-use move
launcher enters a separate private mount namespace, binds only the protected
Core-state parent read-only, confirms kernel EROFS and invokes the real mv.
Only the creating child removes its identified bind before returning the actual
move failure. The parent verifies its namespace/mounts were unchanged; subsequent
normal and recovery moves delegate unchanged. Actual CLI73 and stage-specific
errors, original resource/previous pairing, refreshed binding, peer isolation,
terminal rollback and clean swaps forward are required. Protected receipts retain
the real error and cleanup results. No product function is replaced; no host or
parent-guest mount propagation is changed. These are VFS read-only refusal cases,
not physical media, fsync/power-loss durability or commit-journal fault evidence.

`restore-publication` reuses that real EROFS move fixture for the fixed HY2
configuration path after changing/applying the current Xray desired generation.
The archive node must already have APPLIED evidence distinct from the original,
while the failed HY2 target has INTENT without APPLIED. Ordinary WRITE count must
be between0 and the archive resource count. Complete original resource bytes and
metadata, directory identities, NSS, both fresh bindings and healthy links/checks
must recover without commit/uncertainty; a trusted restore retry must succeed.
Safe `restore-partial-publication.json` records counts and the retired EROFS
receipt. This adds partial-publication coverage; the existing `restore-failure`
startup mode remains separate, and physical/persistent storage or commit faults
are not inferred from this transient refusal.

`deployment-commit-readonly` delegates Python invocations unchanged until the
exact protected deployment publisher follows COMMIT_INTENT and both applied
writes. The original stdin program then runs in a private child namespace with
its transaction directory bound read-only. A scoped interpreter trace observes
the real pending-file EROFS without replacing file APIs or program results.
Require the real publisher/CLI73, completed post-health and whole original
resource/NSS/directory/unit compensation, no marker/uncertainty/applied residue,
then the complete healthy normal main flow. Only the creating child removes the
bind; parent mounts remain unchanged. A separate restore-publication run checks
the shared bind extraction's existing move path. This is before marker publication;
later rename/fsync uncertainty and physical durability remain separate.

`deployment-late-sigkill` requires a fresh guest. A scoped publisher interpreter
trace pauses at the actual post-rename `sync_directory` call, before its body,
only while both marker and uncertainty record exist and the temporary name has
been cleared. A complete root0600 receipt authorizes the existing exact live
CLI SID/PGID watcher to send SIGKILL; the pause expires after30 seconds if missed.
No filesystem API or publisher stdin is replaced. Require real -9, unique final
COMMIT_INTENT, both applied writes and no COMMIT/rollback, a marker verified by
the real product helper and retained uncertainty. Both real enabled Core
generations must match their applied configuration hashes/InvocationIDs and have
listeners. After restoring PATH, four fresh protected commands must refuse70
without output or persisted/runtime/resource changes. The fixture intentionally
retains recovery state and reports `mainflow_completed:false` and
`expected_recovery_required:true`; it is not fsync failure, power loss or VM reboot.

`account-creation-failure` starts from a fresh guest and refuses only the exact
second identity's normal `groupadd` and `useradd` argv, separately. The real Xray
identity must already exist; the Hysteria user must be absent and its group must
match the intended creation point. Each real shadow tool runs under a private
child read-only `/etc` bind. Record a kernel EROFS probe and the actual tool's
nonzero result separately; do not label that probe an observed tool syscall.
Only that child retires its exact bind, and parent mounts remain unchanged.
Require CLI70,2/3 actual APPLIED identities respectively with matching RESTORED
receipts, target INTENT without APPLIED, terminal rollback, original primary NSS
bytes/modes/UIDs/GIDs and authority/directory/service baseline, absent managed
resources and no commit/applied promotion. Restore PATH between failures, then
run the complete normal lifecycle and trusted restore. Ancillary shadow backup
files, other NSS backends and account deletion failures are separate assertions.

`account-deletion-userdel` and `account-deletion-groupdel` each require a fresh
guest. Combine the real precommit publisher EROFS73 with a real shadow deletion
tool refusal in the reviewed child read-only `/etc` namespace. Exact target argv,
NSS removal point and both units already not-found/inactive/PID0 are required.
The groupdel fixture sets the real guest `USERGROUPS_ENAB=no` before its baseline,
retaining file ownership/mode/identity and including login.defs in resource
comparisons. Debian's default yes lets userdel remove the empty private group,
which would skip PNM's explicit groupdel call; that default remains in userdel
acceptance. This is a guest policy branch, not a product argv change.
CLI70 must retain original73/recovery70, RECOVERY_REQUIRED and owned APPLIED
receipts without RESTORED for precisely the remaining Hysteria user+group or
group alone. Original ordinary resources/services must recover without a marker
or commit; primary NSS and owned directories are explicitly not fully recovered.
After restoring both PATH scopes, four fresh protected commands refuse70 with
the exact unresolved deployment reason and no stdout. Compare PNM receipts,
primary NSS, resources, directory identities/metadata and units for no mutation.
Retain the unresolved guest and report `mainflow_completed:false` with
`expected_recovery_required:true`. Re-run creation-failure acceptance after
changing the shared tool fixture; do not infer other NSS/media/VM acceptance.
