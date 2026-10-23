# Isolated Debian main-flow acceptance

Goal: extend the existing WSL evidence to actual managed accounts and PNM
installation/lifecycle inside a disposable filesystem and a separate systemd
instance. User authorization covers consecutive main-flow stages and local commits.
This does not authorize host account/service/network changes or release work.

Design: use Debian's native systemd-nspawn with a fresh signed-repository Debian
rootfs, private network and verified PID/mount/user/cgroup isolation,
no host directory or manager-bus binds, no journal linking and no machine
registration. Download/extract tools privately rather than installing them on the
host. An unshare-only custom init/rootfs framework would duplicate native tooling;
a disposable VM remains the fallback when native isolation cannot be established.
Do not weaken host isolation to force a test to pass.

Prerequisite observations (2026-10-23): WSL systemd is running; mount/PID/user/cgroup
namespace probes exit 0. The cgroup parent is a read-only tmpfs with writable
legacy controllers and a writable unified child: this is a hybrid WSL layout,
not proof that a nested Debian systemd will boot correctly. No nspawn/container/
bootstrap/VM tool is installed. Free space is sufficient for a private rootfs.

Tool metadata from the local configured Debian APT index (not a freshness claim):

| Package | Version | Size | SHA-256 |
|---|---|---|---|
| systemd-container amd64 | 257.13-1~deb13u1 | 674812 | b4872b189204a8a3fcd2203d7b225cf623c3fe4c5e23abfe33296c0bf5000ee2 |
| debootstrap all | 1.0.141 | 50094 | 8c02cb8ad712eb67afb0d23fab175c562804cc97eda70b70cb0f3bc2a21732d7 |
| wget amd64 | 1.25.0-2 | 984500 | 5649cad63c781b2dcf5a7b87d70b3bf789291cd0d6bcabc4d521211f94980683 |
| xz-utils amd64 | 5.8.1-1+deb13u1 | 659488 | 9e0a39d95373afdaad3c9dfaab3c8b0beb9a2c4654e6be10b4bcf458509a3217 |

Stages and stop conditions:

- [x] Download exact packages into a root-owned 0700 temporary
  directory; check size/digest before extraction or execution. Record actual
  prerequisites, review and commit this preparation stage.
- [x] Bootstrap Debian trixie with archive signature verification; install only
  guest prerequisites. The host performs only `--foreign` verification/download/
  extraction; `--second-stage` package scripts run in the isolated guest. Never
  copy host credentials or bind host /etc, /var, /run, physical devices, sockets
  or homes. Native private /dev may contain standard pseudo-devices, not host disks.
- [ ] Boot a randomly named, time-bounded test container. Before PNM writes,
  verify distinct host/guest mount, PID, network, user and cgroup namespaces plus
  manager identity. Guest UID mappings must not grant host-root capabilities;
  only the guest's delegated cgroup subtree may be writable. Require private
  guest network interfaces and protected filesystem ownership. A missing gate
  stops the stage without silently disabling user/cgroup isolation. A boot or
  isolation failure remains an environment limitation and must
  not be reported as application failure or success.
- [ ] If isolation passes, reuse the pinned verified Core assets and current PNM
  source. In the guest only, verify actual account provisioning/reuse, unit/Core
  startup, applied/config state, then scoped apply/restart/backup/restore/recovery
  cases. The network fetch boundary may use a narrowly identified local adapter
  fixture; keep production validators/transactions/files/accounts/systemd real.
  Design/review each case before execution and commit verified increments.
- [ ] Stop only the registered test container/scope after verifying its identity.
  Confirm exit and private mount cleanup before deleting any owned fixture.
  Retain protected failure evidence; never perform broad cleanup or host reboot.

Reuse `tests/integration/real_core_versions.json` and the existing transaction,
systemd and Core harness patterns. Add an opt-in integration entry only after
the isolated boot is demonstrated; default checks never acquire packages or boot
containers. Do not change production architecture, CLI, VERSION or managed pins.
Record the latest outcome and remaining prerequisites in TASKS. Container restart
cannot prove VM/kernel reboot; private local clients cannot prove external L3.

Preparation result: direct Debian CDN APT (including an IPv4-only retry) timed
out; native Windows HTTPS was reset. The HTTPS TUNA mirror listed in
[Debian's official mirror list](https://www.debian.org/mirror/list) supplied the
exact bytes. Both sizes/digests above match before extraction. Packages were
extracted only under `/var/tmp/pnm-container-tools-20261023/tools`; no dpkg install
or maintainer script ran. The privately extracted nspawn reports 257.13-1~deb13u1
and debootstrap reports 1.0.141, both exit 0. This proves tool availability only;
no guest rootfs/container/account/Core lifecycle has been tested in this stage.

Rootfs-stage result: a minimal native `--as-pid2` probe and then the new rootfs
both pass distinct mount/PID/network/user/cgroup namespace checks, a single
nonzero-host-base UID mapping, and only lo. Host-side mountinfo confirms writable
systemd/unified cgroups are rooted at the owned scope/payload; all 18 checked
controller paths are accounted for and outside controllers are not writable by
guest root. `/sys/fs/cgroup` itself is the guest's private tmpfs. Probe exit releases
the scope and leaves no fixture mounts. Intermediate incomplete diagnostics are
not counted; final strict observations use `set -eu` and explicit assertions.

The new rootfs is `/var/tmp/pnm-debian-guest.4w7y455l/rootfs`. Its foreign bootstrap
exits 0 with `Valid Release signature`. The separately repeated preconfigure gate
passes. Native automatic ownership uses an idmapped mount: backing root remains
host UID 0, while guest root is 0 and maps to host UID 1069219840 for this fixture;
backing ownership must not be mistaken for the guest's effective host identity.
The isolated second stage exits 0 with `Base system installed successfully`.
Its own policy-rc.d forbids service starts during setup. Host passwd/group/shadow/
gshadow and dpkg status digests remain unchanged (no digest/content disclosure).
Final scope is not-found and no fixture mount remains. Evidence in that parent:
`bootstrap.log`, `preconfigure-gate-host.json`, `ownership-map.log`, `configure.log`
and `configure-result.json`. wget/xz were also privately verified/extracted;
existing sqv performed signature verification. No host tools were installed.
This establishes rootfs preparation and shell isolation, not a booted guest
systemd or PNM managed-account/lifecycle acceptance. Full boot is next.
