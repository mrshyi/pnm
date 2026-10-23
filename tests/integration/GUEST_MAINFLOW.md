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

Each invocation creates a new private `/var/tmp/pnm-install-guest.*` clone and
unique native scope, rotates only that clone's machine ID, copies current PNM
source and checked asset bytes, and compiles the guest scripts before boot.
It replaces only the clone's dedicated test unit with a 390-second limit; the
baseline's 80-second boot probe is too short for lifecycle cases. Guest cases
have a separate 300-second timeout and the host deadline remains 420 seconds.
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

The parent prints a safe JSON summary and leaves `boot-result.json`, source
hashes and protected evidence under the new fixture. Raw CLI/Core output,
configuration and backups can contain secrets; do not print or publish them.
Successful shutdown must leave the transient scope not-found, no fixture mounts,
and unchanged host account/package databases. Fixtures are retained for review;
there is no automatic recursive cleanup. Time-sync checks are not collected by
the current PNM check dispatcher. VM/kernel reboot, update versions, injected
failure recovery, deployed-source identity and external clients remain separate.

`test_guest_mainflow_guard.py` runs five offline checks before boot: explicit
opt-in, enabled assertions, protected regular-file/link behavior, nonblocking
FIFO rejection, and retirement of a PIPE-holding descendant on command timeout.
Each CLI call owns a new session; bounded TERM/KILL retires that command group
on timeout, while its Core services remain under the guest systemd manager.
