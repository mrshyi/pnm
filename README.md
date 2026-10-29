# Proxy Node Manager

**Release status: 0.16.0-rc.1 (release candidate).** The automated checks pass, but production readiness still requires a supported-distribution deployment, reboot-persistence checks, and external tests of both protocols.

PNM manages the lifecycle of two independent proxy cores on one supported Debian or Ubuntu VPS:

- Xray-core: VLESS + REALITY on TCP/443 by default
- Official Hysteria2: QUIC on UDP/8443 by default

PNM does not forward traffic. It installs pinned binaries, renders and validates each configuration, controls the corresponding systemd service, and manages secret-bearing backups.

Target deployment platforms: Debian 12/13 and Ubuntu 22.04/24.04, amd64 and arm64, with systemd. ARM64 compatibility is implemented; actual per-platform acceptance is tracked in [TASKS](docs/TASKS.md).

Ubuntu 22.04 LTS and 24.04 LTS use architecture-specific pinned Core assets, the same service-account
policy and independent systemd units. TLS checks handle OpenSSL 3.0 hostname
results and default certificate-date output. CI targets both Ubuntu versions
explicitly and records their tool versions; the default tests include real
certificate checks and isolated static systemd unit validation. CI configuration
does not establish completed installation, reboot or external-client acceptance;
see [current evidence](docs/TASKS.md). The cloud ARM64 workspace remains a development environment, not a deployment acceptance target.

The CI workflow also defines Debian12/13 native amd64/arm64 container gates with separate
non-root and root fixture checks. Container results do not establish Debian
systemd startup, managed installation or reboot acceptance; see
[test boundaries](CONTRIBUTING.md#repository-gates).

## Commands

- `pnm status [--json]`: read-only Xray and Hysteria2 status
- `pnm [--quiet|--json] check [--resources]`: read-only proxy health checks, with optional resource observations
- `pnm node init`: interactively initialize the single VPS node
- `pnm node change`: replace an uncommitted single-node configuration
- `pnm --json node show`: show the desired node state without secrets
- `pnm node links`: print VLESS + REALITY and Hysteria2 client import links
- `pnm --json node validate`: validate both desired-state files
- `pnm install --apply --yes`: install/configure both cores using approved versions
- `pnm profile show`, `pnm profile set dual|reality|hy2 --yes`: inspect or switch active cores on an installed node
- `pnm recovery list`, `pnm recovery inspect TRANSACTION_ID`: read sanitized transaction diagnostics, including blocked transactions
- `pnm apply xray|hy2`: transactionally apply one rendered configuration
- `pnm restart xray|hy2`, `pnm log xray|hy2`: operate on one core only
- `pnm update xray|hy2 [--version V]`: update one core using its pinned SHA-256
- `pnm rollback xray|hy2`: restore that core's previous binary after an update
- `pnm backup [archive]`, `pnm restore archive`: create or restore a mode-0600 backup
- `pnm uninstall xray|hy2 --yes`: back up and remove one core

Each update changes one core per command. Failed configuration changes and updates restore that core's prior files or binary and check service health.

Backups include Core binaries and must be restored on the same architecture. Foreign-architecture ELF candidates are rejected before execution or managed-resource writes; cross-architecture migration is not supported.

Restore accepts operator-verified trusted PNM backups. Candidate validation executes the packaged Core binaries as root. Record the backup's SHA-256 when it is created, retain that digest in a separate trusted record, and compare it again before restoration:

```bash
sudo sha256sum -- /root/pnm-backup.tar.gz
```

Keep backups root-owned with mode 0600 because they contain credentials. Ownership, permissions and a checksum stored only inside the same archive do not authenticate its origin. The parser limits itself to 128 MiB of address space and 30 seconds of CPU time (or stricter inherited limits); these protect parsing resources and do not sandbox candidate execution or verify provenance.

## Run from source

```bash
sudo ./bin/pnm node init
sudo ./bin/pnm node validate
sudo ./bin/pnm install --dry-run
sudo ./bin/pnm install --apply --yes
sudo ./bin/pnm check
```

This runs PNM from a source checkout on a supported host. It requires root privileges and the pinned asset versions in `versions.conf`. It does not modify SSH or UFW.

## Configure one node

PNM manages one node per VPS. Initialize its desired state before the first core installation:

```bash
sudo pnm node init
sudo pnm node validate
sudo pnm install --dry-run
sudo pnm install --apply --yes
```

`pnm node init` prompts for the VPS public address, region, timezone, REALITY SNI and target, listen ports, TLS mode, and the exact pinned Xray/Hysteria2 versions with their independently verified SHA-256 values. New nodes default to `www.cloudflare.com` for both REALITY SNI and target host; this is a candidate default, not a guarantee that Cloudflare is reachable or REALITY-compatible on every network. Choose a public certificate name appropriate for your network. REALITY SNI and target may be different when explicitly configured. Existing node settings, including Microsoft values, are preserved and are not migrated by upgrades. It writes `/etc/pnm/node.conf` and `/etc/pnm/versions.conf` transactionally with mode `0600`. Do not enter placeholders such as `<VERSION>` or `<SHA256>`; angle brackets are intentionally rejected as unsafe configuration values.

The wizard defaults to `vps`, `UTC`, REALITY `www.cloudflare.com:443`, Xray TCP/443, Hysteria2 UDP/8443, and `selfsigned-pin`. It also queries the latest stable Xray and Hysteria2 release metadata and official SHA-256 files, then displays concrete version/hash values as defaults. Press Enter to accept them, or override them with the corresponding option. The saved `versions.conf` always contains concrete pinned values; the moving `latest` label is never used as an asset URL or written to disk.

If the release lookup is unavailable, interactive setup continues and requires both pinned version/hash pairs to be entered manually. Non-interactive setup does not perform a network lookup and requires explicit `--xray-version`, `--xray-sha256`, `--hy2-version`, and `--hy2-sha256` flags.

For automation, pass the same values as flags. `pnm node add` is an alias for `init`; `pnm node info` is an alias for `show`. `pnm node change` only replaces a node that has not yet been committed by a successful installation. For an installed node, update `/etc/pnm/node.conf` with the reviewed REALITY SNI and target, then run `sudo pnm apply xray`; this validates and applies the rendered candidate transactionally. `pnm node show` reports saved values, runtime configuration values, service state, and drift. `pnm node links` refuses to print links if the runtime Xray configuration differs from the saved configuration.

Before changing an installed node, keep a copy of `node.conf`. If validation or service restart fails, `pnm apply xray` restores the previous runtime Xray file and restarts the prior service; the proposed `node.conf` remains the desired state for retry. `pnm node show` reports this drift and `pnm node links` refuses to emit links until the files match. To revert the entire change, restore the saved `node.conf` and run `sudo pnm apply xray` again. Do not rerun installation to change REALITY settings.

For an `external-ca` node, choose that TLS mode during initialization and set
`--hy2-server-name` to a DNS SAN in your certificate. Supply the certificate chain
and matching private key when previewing or applying installation:

```bash
sudo pnm install --dry-run --tls-cert /root/tls/fullchain.pem --tls-key /root/tls/privkey.pem
sudo pnm install --apply --yes --tls-cert /root/tls/fullchain.pem --tls-key /root/tls/privkey.pem
```

Both inputs must be readable regular files; symbolic links are rejected. PNM
checks the pair and TLS server name before deployment, imports them into its
managed TLS paths, and preserves the source files. The two options must be
supplied together and apply to `external-ca` nodes. Self-signed nodes retain
the existing installation command without these options.
The interactive menu's installation option asks for both file paths on a new
external-ca node and uses the same installation checks. Ending input before both
paths are supplied cancels that installation attempt.

## Select active cores

First complete the existing dual-Core installation. Then select the services
you want active:

```bash
sudo pnm profile set reality --yes  # Xray VLESS + REALITY only
sudo pnm profile set hy2 --yes      # Hysteria2 only
sudo pnm profile set dual --yes     # Both cores
sudo pnm --json profile show
```

The menu also offers **Switch Profile** with an explicit confirmation. Switching
retains both binaries, runtime configurations, accounts, TLS files and credentials;
it does not download, reinstall or uninstall either Core. A Core that remains
enabled is not restarted. The selected services must pass local health checks
before the desired profile is committed. Failure restores the prior service
policy and node configuration through the existing transaction mechanism.

The optional `PNM_PROFILE` field lives in `node.conf`; older files without it mean
`dual`. `profile show` reports desired and actual service state separately.
`check` verifies that excluded services are inactive and disabled, and `node links`
omits their links. `apply`, `restart`, `update` and `rollback` refuse excluded
cores; select a profile that enables them first. Restore follows the profile in
the trusted backup. First-install provisioning still prepares both Cores and
requires both approved version/hash pairs and the configured TLS inputs.

## Read-only resource checks

```bash
sudo pnm --json status
sudo pnm --json check --resources
sudo pnm --quiet check --resources
```

Status separates the desired Profile from actual services and probes the ports
in the validated node configuration. Unavailable configuration leaves Profile,
port and desired-selection information unknown; default ports are not guessed.
JSON retains `pnm.status.v1` with additive `desired_profile`, Core `port` and
`desired_enabled` fields. Root status uses the existing deployment read lock.

`--resources` adds visible `/proc` memory, Swap, load and OOM observations to the
existing check output. It warns below10% available memory/free Swap, when the
15-minute load exceeds the visible logical CPU count, or when the cumulative
kernel OOM-kill count is nonzero. No Swap is SKIP; missing counters are UNKNOWN.
OOM counts cover the system since boot and do not identify a PNM Core. Load is
not CPU usage, and these system counters do not represent container resource
quotas. Existing exit codes remain0 OK,1 WARN/UNKNOWN,2 FAIL; ordinary `check`
does not add these observations. Neither local health nor resource checks prove
public client connectivity. Optional external checks remain deferred.

## Inspect retained recovery evidence

If ordinary commands refuse an unresolved transaction, use the recovery menu
option or these root-only commands:

```bash
sudo pnm recovery list
sudo pnm --json recovery inspect TRANSACTION_ID
```

Replace `TRANSACTION_ID` with an ID from the list. Diagnostics report the existing
parser's transaction state, operation and file/directory change count, together
with whether transaction evidence currently blocks writes. That count does not
include service/account changes or certify successful recovery. No snapshots,
journal details, configuration contents or credentials are printed.

The diagnostic reader takes the existing shared lock and remains available when
the normal pending-transaction guard refuses other reads. It does not replay,
roll back, repair or clear evidence. Exit0 means the transaction guard is clear,
1 means writes are blocked,69 means the requested ID was not found, and78 means
evidence is invalid; unsafe store permissions refuse with77. A clear transaction
guard does not establish service health or satisfy other write preconditions.
Keep retained evidence private for operator review.

Firewall management remains manual. Installation, Profile changes, restore and
recovery diagnostics do not create, adopt, delete or reset firewall rules.
Encrypted-backup key custody and automatic cross-process recovery remain deferred.

## Install and use PNM on a VPS

Use a supported Debian 12/13 or Ubuntu 22.04/24.04 amd64/arm64 host with systemd, root access, and an internet connection. The installer needs `curl` and `tar`; core installation checks for its required tools, including `unzip` for the Xray archive.

To install the PNM CLI and runtime library under `/usr/local/lib/pnm` and create `/usr/local/bin/pnm`, download the installer to a temporary file and execute it as root:

```bash
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/mrshyi/pnm/main/install.sh \
  --output /tmp/pnm-install.sh && sudo bash /tmp/pnm-install.sh
```

The installer downloads the repository archive from `PNM_REF` (default: `main`). For a reproducible deployment, set `PNM_REF` to a reviewed tag or commit and inspect the downloaded installer before running it. For example, after downloading and reviewing the script, install a specific ref with `sudo env PNM_REF=reviewed-ref bash /tmp/pnm-install.sh` (replace `reviewed-ref` with the selected tag or commit).

Then initialize, review, and install the node:

```bash
sudo pnm node init
sudo pnm node validate
sudo pnm install --dry-run
sudo pnm install --apply --yes
```

The initialization wizard asks for the public address, region, timezone, REALITY server name and target, listener ports, TLS mode, and pinned Core versions and checksums. See [Configure one node](#configure-one-node) for the defaults and non-interactive options. The first installation generates the node credentials securely; valid existing credentials are reused on retries and reinstalls. Invalid existing credentials stop installation rather than being replaced.

After installation, check the services and print client import links:

```bash
sudo pnm status
sudo pnm check
sudo pnm node show
sudo pnm node links
```

The default listeners are Xray TCP/443 and Hysteria2 UDP/8443. PNM does not change SSH or firewall rules, so ensure those listener ports are reachable through your host and provider firewall. Client links contain credentials; transfer and store them as secrets. If the saved public address is unavailable, supply one with `sudo pnm node links --address ADDRESS`.

## Tests

See [Contributing](CONTRIBUTING.md) for Linux/cloud development prerequisites,
non-root skips and the separate amd64 integration acceptance requirements.

```bash
make check
make shellcheck
make release-check
```

## Security and releases

- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability.
- Review [CHANGELOG.md](CHANGELOG.md) for release changes and [docs/RELEASING.md](docs/RELEASING.md) before creating a tag.
- Backups contain credentials and private keys. Keep them out of GitHub issues, pull requests, and source control.
- PNM is intended for the supported Debian/Ubuntu versions above with systemd. The test suite does not replace live VPS or external client acceptance tests.

Default configuration paths:

- `/etc/pnm/node.conf`
- `/etc/pnm/versions.conf`

Update versions must be approved by recording the version and independently verified SHA-256 in `versions.conf`. PNM does not follow a moving `latest` release. Backups contain Secrets and must be stored as sensitive data.
