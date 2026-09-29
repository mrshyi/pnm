# Proxy Node Manager

**Release status: 0.16.0-rc.1 (release candidate).** The automated checks pass, but production readiness still requires a Debian 13 deployment, reboot-persistence checks, and external tests of both protocols.

PNM manages the lifecycle of two independent proxy cores on one Debian 13 VPS:

- Xray-core: VLESS + REALITY on TCP/443
- Official Hysteria2: QUIC on UDP/8443

PNM does not forward traffic. It installs pinned binaries, renders and validates each configuration, controls the corresponding systemd service, and manages secret-bearing backups.

## Commands

- `pnm status [--json]`: read-only Xray and Hysteria2 status
- `pnm check [--quiet|--json]`: read-only proxy health checks
- `pnm install --apply --yes`: install/configure both cores using approved versions
- `pnm apply xray|hy2`: transactionally apply one rendered configuration
- `pnm restart xray|hy2`, `pnm log xray|hy2`: operate on one core only
- `pnm update xray|hy2 [--version V]`: update one core using its pinned SHA-256
- `pnm rollback xray|hy2`: restore that core's previous binary after an update
- `pnm backup [archive]`, `pnm restore archive`: create or restore a mode-0600 backup
- `pnm uninstall xray|hy2 --yes`: back up and remove one core

Each update changes one core per command. Failed configuration changes and updates restore that core's prior files or binary and check service health.

## Run from source

```bash
sudo ./bin/pnm install --apply --yes
./bin/pnm check
```

## Tests

```bash
make check
make shellcheck
make release-check
```

## Security and releases

- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability.
- Review [CHANGELOG.md](CHANGELOG.md) for release changes and [docs/RELEASING.md](docs/RELEASING.md) before creating a tag.
- Backups contain credentials and private keys. Keep them out of GitHub issues, pull requests, and source control.
- PNM is intended for Debian 13 with systemd. The test suite does not replace live VPS or external client acceptance tests.

Default configuration paths:

- `/etc/pnm/node.conf`
- `/etc/pnm/versions.conf`

Update versions must be approved by recording the version and independently verified SHA-256 in `versions.conf`. PNM does not follow a moving `latest` release. Backups contain Secrets and must be stored as sensitive data.
