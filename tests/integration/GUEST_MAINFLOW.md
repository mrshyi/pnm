# Private guest main-flow checks

This explicit opt-in test clones a separately prepared trusted Debian 13 boot
fixture. It never bootstraps packages, downloads assets, installs host packages,
binds host directories or changes host accounts/network/firewall configuration.
Default `make check` does not run it. It currently targets the verified hybrid
WSL cgroup layout; another layout fails closed.

Prerequisites are the signed, private rootfs and successful native boot fixture
described in [the preparation plan](../../docs/superpowers/plans/2026-10-23-container-mainflow.md):
root-owned mode-0700 parent, canonical `rootfs`, successful `boot-result.json`,
and the dedicated enabled `pnm-boot-probe.service` that executes
`/usr/bin/python3 /opt/pnm-boot-worker.py`. The rootfs must be a trusted clean
baseline without PNM resources/accounts. Its package executables and services
are trusted input, not authenticated by the JSON report. Supply a separately
trusted root-owned native nspawn executable and the existing exact pinned Core
cache (see `real_core_versions.json`). Do not use an arbitrary downloaded image.

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
and requires both unrelated default sockets to remain untouched.

`PNM_GUEST_SCENARIO=runtime-evidence` restarts each actual Core outside PNM,
requires show/links to retain unconfirmed applied state and withhold only that
Core's URI, and checks that PNM restart cannot promote it. Fully validated apply
then rebuilds the confirmed binding. A separate real flock holder collides with
the writer and protected link reader; both refuse without output/Core changes
or a new transaction, then normal operations resume after release. This covers
held-lock contention and external service restart, not all timing interleavings
or VM/kernel reboot.

For distinct-version testing, set `PNM_GUEST_SCENARIO=core-update` and
`PNM_PREVIOUS_CORE_ASSETS=/var/tmp/pnm-update-core-assets`. That separately
acquired mode-0700 root-owned cache must match `previous_core_versions.json`:
Xray v26.9.30 and HY2 v2.12.3. The existing asset verifier checks both old and
current pairs. The clone initially installs the old pair, then explicitly approves
the current pair only in its own versions.conf. It runs each real Core through
checksum refusal, different-version update, rollback and rollback swap forward,
checking resource/version/invocation/applied state and the peer's previous-state
metadata as well as its runtime resources. Final links/health must be ready.

This scenario uses real curl/TLS/checksum/staging with a private lo HTTPS CONNECT
fixture that serves only the two checked release assets. Its CA/proxy settings
exist only in CLI process env; host trust/network is unchanged. Only github.com
and the exact release paths are accepted. Headers, connection count, total request
duration and thread/socket retirement are bounded. This transport substitution
does not establish upstream DNS/PKI/download behavior or external clients.

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

The parent prints a safe JSON summary and leaves `boot-result.json`, source
hashes and protected evidence under the new fixture. Raw CLI/Core output,
configuration and backups can contain secrets; do not print or publish them.
Successful shutdown must leave the transient scope not-found, no fixture mounts,
and unchanged host account/package databases. Fixtures are retained for review;
there is no automatic recursive cleanup. Time-sync checks are not collected by
the current PNM check dispatcher. Distinct versions and the one deadline-failure
case require their named scenarios above. VM/kernel reboot, other injected
failure positions, deployed-source identity and external clients remain separate.

`test_guest_mainflow_guard.py` runs nine offline checks before boot: explicit
opt-in, enabled assertions, protected regular-file/link behavior, nonblocking
FIFO rejection, retirement of a PIPE-holding descendant on command timeout,
asset header limits, guest-only start-fault refusal before host mutation/network,
custom work-directory safety, and isolated-network asset/TLS positive/refusal/cleanup.
The latter proves a distinct network namespace before raising only that child's
lo; no host socket/interface is created or changed. It covers incomplete CONNECT/
TLS, wrong target/path, and a CA-verified fixed response with complete retirement.
Each CLI call owns a new session; bounded TERM/KILL retires that command group
on timeout, while its Core services remain under the guest systemd manager.
