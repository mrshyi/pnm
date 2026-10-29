# Contributing

Keep changes within the Xray and Hysteria2 lifecycle scope. Do not add remote access-plane management or unrelated host-maintenance commands without an explicit project decision.

Start with `AGENTS.md` and the current phase/blockers in [docs/TASKS.md](docs/TASKS.md).
Use [Architecture](docs/ARCHITECTURE.md) for implemented behavior and
[Acceptance plan](docs/ACCEPTANCE_PLAN.md) for test IDs and closure criteria.
[Historical records](docs/history/README.md) are read on demand; they do not
authorize commits, provisioning, fault injection or production changes.

## Linux workspace

Development checks run on Linux, including an Ubuntu ARM64 cloud workspace.
Deployment targets are Debian 12/13 and Ubuntu 22.04/24.04 **amd64/arm64** with
systemd. Native L1 results do not establish managed installation acceptance on
either architecture; record each OS/architecture separately.
Native Windows/Git Bash test shims are no longer maintained.

Before selecting checks, inspect the current execution environment:

```bash
git status --short --branch
git log -1 --oneline
uname -sm
id
ps -p 1 -o comm=
openssl version
```

The ordinary L1 suite needs Bash, make, ripgrep, Python 3, jq, OpenSSL, curl,
zip/unzip, tar, flock, coreutils and the systemd command-line tools used by
fixtures (including `systemd-analyze`). ShellCheck is a separate required gate.
An installed `systemctl` does not imply a running systemd manager. Check available
tools without installing anything:

```bash
command -v bash make rg python3 jq openssl curl zip unzip tar flock \
  sha256sum stat date ss systemctl systemd-analyze runuser shellcheck
```

Report missing tools. If an approved tool was unpacked outside the checkout,
prepend its actual `bin` directory to `PATH` for that check and record its version.
Do not hardcode a previous session's `/tmp` path or change the host automatically.

## Repository gates

Run from the project root as the normal workspace user:

```bash
make check
make shellcheck
make release-check
```

`make check` runs syntax, security scanning and the unit/mock suites.
CI runs the same gates on explicit `ubuntu-22.04` and `ubuntu-24.04` amd64 runners and their `-arm` ARM64 counterparts,
using [GitHub's runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and recording OS, Bash, Python, OpenSSL and systemd versions. The service suite invokes
the real `systemd-analyze verify` against generated units with temporary Core
paths and isolated target fixtures; it starts no service. Platform tests accept
only approved release/architecture pairs and reject derivatives and other versions.
The check/ShellCheck/release-check steps are L1 checks. On the disposable
GitHub-hosted Ubuntu runners, CI first runs the existing CLI/read-access/TLS-access/
transaction/Profile/recovery-diagnostic suites as root to exercise their privileged
branches and actual root ownership of private fixtures. Profile service controls
remain simulated and recovery fixtures do not replay host operations. Access probes
use nobody with private files; NSS names remain test mappings and no accounts are
created. It then runs `sudo make test-systemd`
against owned temporary units with unprivileged Python TCP/UDP listeners, followed
by `make test-real-cores` with root-private, hash-verified pinned test assets and
private network namespaces. These integration steps do not install managed PNM,
change production services, reboot the runner or prove external connectivity.
Check actual job results before claiming either runner or integration step passed.

The workflow also defines Debian12/13 native amd64/arm64 jobs using the official
`debian:12-slim` and `debian:13-slim` containers on the corresponding Ubuntu24.04 amd64/arm64 runner.
Dependencies are installed inside the disposable job container. Gates,
ShellCheck, offline main-flow preparation and loopback acquisition run as nobody
against a private source copy that excludes `.git`; the original checkout is
retained for the six existing root access/transaction/Profile/recovery suites.
No test user is created. Logs record the actual Debian release, architecture,
source commit, PID1 and tool versions. These containers are not privileged or
booted with systemd: they cover Debian userspace, crypto, static unit validation
and private-file permission behavior, not real service startup, managed accounts,
Core namespace traffic, reboot or full Debian platform acceptance. Those checks
still require an authorized disposable supported systemd environment. A defined
Debian job is not a successful run; results remain in TASKS.

`make release-check` adds release scanning and repeats `make check`; it does not
publish anything, and its repeated tests are not additional independent coverage.
Keep each gate's exit code, suite totals and explicit skips. A non-root run may
pass while root-only bodies/suites are skipped; do not report those as executed.
Use a private temporary directory and `umask 077` for retained logs. Tests must
work under restrictive umasks rather than assuming newly created files are0644.

Safe additional offline checks are:

```bash
python3 -B tests/integration/test_guest_mainflow_guard.py
python3 -B tests/integration/test_real_core_refusal_guard.py
```

These check harness refusal behavior, copied-source identity and guest platform
policy; they do not boot a guest or validate actual Core traffic. The main-flow
preparation suite also runs in Ubuntu CI without deployment. Record root-only skips.

`make test-asset-network` runs non-root, loopback-only real curl/TLS acquisition
checks against synthetic assets, reusing the existing HTTPS fixture. It covers
successful private publication, checksum refusal, truncated HTTP bodies,
untrusted certificates and a controlled TLS-handshake timeout for both Cores.
Two additional503 cases retain the production retry flags: two transient replies
then success, or three failures exhausting the initial attempt plus two retries.
It needs permission to bind a local socket; it does not install or execute Cores.
The test curl wrapper disables curlrc; fault-injection cases also disable retries.
All cases use test-only transfer limits. The503 cases establish the declared
retry count, without testing default overall deadlines, Retry-After behavior,
other retryable statuses or upstream DNS outages. Ubuntu CI runs this target
separately from the L1 suites.

## Integration and acceptance boundaries

| Layer | Environment | Boundary |
|---|---|---|
| L1 | Linux workspace, including ARM64/non-root | Real temporary files/crypto and selected loopback transport; managed service/account observations may be mocked and skips remain visible |
| L2 | Approved disposable supported Ubuntu/Debian amd64/arm64/systemd environment | Real accounts, pinned Core programs, units, listeners, fault recovery and same-disk reboot |
| Other supported platforms | Separate execution for each remaining supported release/architecture pair | Their own acceptance; os-release fixtures are L1 only |
| L3 | Authorized targets and controlled external clients | Separate Xray REALITY and HY2 handshakes and traffic |

The `test-systemd`, `test-real-cores`, `test-guest-mainflow` and
`test-commit-storage` targets are opt-in. Do not run them on a shared cloud
development host. Prepare and authorize the appropriate disposable environment,
check existing identity/cleanup guards and use approved fixed assets first.
See [the guest guide](tests/integration/GUEST_MAINFLOW.md). Missing root, namespaces,
systemd, KVM or assets is a blocked prerequisite, not a passing integration result.

Do not commit node configuration, credentials, private keys, generated backups,
bytecode caches or test logs. Add focused regression coverage for behavior changes.
Report sanitized errors when a gate cannot run. Update current results in
`docs/TASKS.md`; retain only useful historical evidence in `docs/history/`.
