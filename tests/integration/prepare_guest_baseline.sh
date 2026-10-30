#!/usr/bin/env bash
# Prepare a native signed-package rootfs only on an opted-in disposable CI runner.
set -Eeuo pipefail
umask 077

if [[ "${PNM_RUN_GUEST_PREPARE:-0}" != 1 || "${GITHUB_ACTIONS:-}" != true ||
      "${RUNNER_ENVIRONMENT:-}" != github-hosted ]] || ((EUID != 0)); then
    printf 'Guest preparation requires explicit opt-in on a disposable GitHub-hosted root runner.\n' >&2
    exit 77
fi
[[ $# == 2 ]] || { printf 'Usage: prepare_guest_baseline.sh OS BASELINE\n' >&2; exit 64; }
case "$1" in
    debian12) image=debian:12-slim; os_id=debian; version=12 ;;
    debian13) image=debian:13-slim; os_id=debian; version=13 ;;
    ubuntu22) image=ubuntu:22.04; os_id=ubuntu; version=22.04 ;;
    ubuntu24) image=ubuntu:24.04; os_id=ubuntu; version=24.04 ;;
    *) exit 64 ;;
esac
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$repo/lib/common.sh"
arch="$(pnm_arch)"
[[ "$(cat /proc/1/comm)" == systemd ]] || exit 69
for tool in docker systemd-nspawn python3 tar; do command -v "$tool" >/dev/null || exit 69; done
baseline="$2"
pnm_validate_managed_path "$baseline" || exit 78
[[ "$baseline" == /var/tmp/pnm-ci-mainflow.*/baseline && ! -e "$baseline" ]] || exit 78
parent="$(dirname -- "$baseline")"
[[ -d "$parent" && "$(stat -c '%a:%u' -- "$parent")" == 700:0 ]] || exit 77
[[ "$(realpath -- "$parent")" == "$parent" ]] || exit 78
[[ "$(docker info --format '{{.Architecture}}')" == "$(uname -m)" ]] || exit 78
mkdir -m 0700 -- "$baseline" "$baseline/rootfs"

# Resolve the official tag once, then create only from that immutable local ID.
docker pull --platform "linux/$arch" "$image"
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
[[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 78
[[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image_id")" == "linux/$arch" ]] || exit 78
digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$image_id")"
[[ "$digest" == *@sha256:* ]] || exit 78
nonce="$(cat /proc/sys/kernel/random/uuid)"
container=''
cleanup() {
    local rc=$?
    trap - EXIT
    if [[ -n "$container" ]]; then
        if [[ "$(docker inspect --format '{{index .Config.Labels "io.pnm.fixture"}}' "$container")" == "$nonce" &&
              "$(docker inspect --format '{{.Image}}' "$container")" == "$image_id" ]]; then
            docker rm --force "$container" >/dev/null || rc=70
        else
            printf 'Fixture ownership mismatch; container retained for review.\n' >&2
            rc=70
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT
# No privileged mode, host bind mounts, host sockets or host PID/network namespace.
container="$(docker create --name "pnm-build-$nonce" --label "io.pnm.fixture=$nonce" \
    --env DEBIAN_FRONTEND=noninteractive "$image_id" bash -euc '
        umask 022
        apt-get update
        apt-get install --yes --no-install-recommends systemd-sysv dbus python3 \
            bash ca-certificates curl openssl zip unzip tar util-linux iproute2 passwd tzdata
        apt-get clean
        dpkg-query -W > /opt/pnm-template-packages.txt
    ')"
timeout 15m docker start --attach "$container"
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$container")" == 0 ]] || exit 70
docker export "$container" | tar --extract --numeric-owner --directory "$baseline/rootfs"

python3 - "$baseline" "$os_id" "$version" "$arch" "$image_id" "$digest" <<'PY'
import json, os, pathlib, stat, sys, uuid
base=pathlib.Path(sys.argv[1]); root=base/'rootfs'
# Docker export need not include a root-directory entry; guest users need search access.
root_mode_before=stat.S_IMODE(root.stat().st_mode)
root.chmod(0o755)
print(f'Template root mode normalized: {root_mode_before:04o} -> 0755',flush=True)
for name in ('etc','opt','var/lib','var/lib/dbus','var/tmp','etc/systemd/system',
             'etc/systemd/system/multi-user.target.wants'):
    path=root/name
    path.mkdir(parents=True,exist_ok=True)
    assert path.resolve()==path and path.is_dir(), 'unsafe template directory'
release=(root/'etc/os-release').resolve()
assert release.is_relative_to(root), 'unsafe OS identity path'
values={k:v.strip('"') for k,v in (line.split('=',1) for line in release.read_text().splitlines() if '=' in line)}
assert (values['ID'],values['VERSION_ID'])==tuple(sys.argv[2:4]), 'template OS mismatch'
for name in ('etc/passwd','etc/group','etc/shadow','etc/gshadow'):
    path=root/name
    assert path.is_file() and not path.is_symlink(), 'unsafe account database'
assert not any((root/p).exists() or (root/p).is_symlink()
               for p in ('etc/pnm','var/lib/pnm','usr/local/bin/xray','usr/local/bin/hysteria'))
accounts={line.split(':',1)[0] for line in (root/'etc/passwd').read_text().splitlines()}
assert not accounts.intersection(('xray','hysteria')), 'template has managed accounts'
for name, content in [('etc/machine-id',uuid.uuid4().hex+'\n'),
                      ('etc/systemd/system/pnm-boot-probe.service',
                       '[Unit]\nDescription=PNM private boot probe\nAfter=basic.target\n'
                       '[Service]\nExecStart=/usr/bin/python3 /opt/pnm-boot-worker.py\n'
                       '[Install]\nWantedBy=multi-user.target\n')]:
    path=root/name
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_NOFOLLOW,0o644)
    with os.fdopen(fd,'w') as stream:
        assert stat.S_ISREG(os.fstat(stream.fileno()).st_mode)
        stream.truncate(0); stream.write(content)
link=root/'etc/systemd/system/multi-user.target.wants/pnm-boot-probe.service'
assert not link.exists() and not link.is_symlink()
link.symlink_to('../pnm-boot-probe.service')
# A source/architecture receipt is not a boot-success receipt.
receipt=dict(zip(('os','version','architecture','image_id','image_digest'),sys.argv[2:]))
receipt.update(root_mode_before=f'{root_mode_before:04o}',root_mode='0755')
(base/'template.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
printf 'Prepared native template; boot verification still required: %s\n' "$baseline"
