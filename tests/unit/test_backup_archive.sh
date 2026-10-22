#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT

pnm_require_root() { return 0; }
pnm_platform_supported() { return 0; }
pnm_make_temp_dir() { mktemp -d "$suite_root/stage.XXXXXXXX"; }
# Archive parsing tests stop before candidate execution or managed-path writes.
pnm_core_restore_validate_staged() { validation_reached=1; return 78; }
# Root ownership is simulated only when the suite runs as an unprivileged user.
stat() {
    if ((EUID != 0)) && [[ "$1" == -c && "$2" == '%a:%u' ]]; then
        command stat -c '%a:0' -- "$4"
    else
        command stat "$@"
    fi
}

make_backup_archive() {
    python3 - "$1" "$2" <<'PY'
import io
import pathlib
import sys
import tarfile

destination, scenario = sys.argv[1:]
paths = ["etc/pnm/node.conf", "etc/pnm/versions.conf", "etc/pnm/secrets/reality.env",
         "etc/pnm/secrets/hysteria.env", "usr/local/etc/xray/config.json",
         "etc/hysteria/config.yaml", "etc/hysteria/tls/server.crt", "etc/hysteria/tls/server.key",
         "usr/local/bin/xray", "usr/local/bin/hysteria",
         "etc/systemd/system/xray.service", "etc/systemd/system/hysteria-server.service"]
with tarfile.open(destination, "w:gz", format=tarfile.USTAR_FORMAT) as archive:
    def add(name, content=b"non-executable fixture\n", kind=tarfile.REGTYPE):
        item = tarfile.TarInfo(name)
        item.type = kind
        item.mode = 0o600
        item.size = len(content) if kind == tarfile.REGTYPE else 0
        item.linkname = "../../outside" if kind == tarfile.SYMTYPE else ""
        archive.addfile(item, io.BytesIO(content) if kind == tarfile.REGTYPE else None)

    manifest = b"CONTAINS SECRETS\n"
    if scenario == "oversized-manifest":
        manifest += b"x" * 65536
    add("MANIFEST.txt", manifest)
    for path in paths:
        if scenario == "missing-tls" and path.endswith("server.key"):
            continue
        name = "/" + path if scenario == "absolute" else "./" + path
        kind = tarfile.SYMTYPE if scenario == "symlink" and path.endswith("server.key") else tarfile.REGTYPE
        add(name, kind=kind)
    if scenario == "duplicate":
        add("./etc/pnm/node.conf")
    elif scenario == "root-file":
        add("./", b"unexpected root payload")
    elif scenario in ("root-directory-payload", "directory-payload"):
        item = tarfile.TarInfo("./" if scenario == "root-directory-payload" else "unused-directory")
        item.type = tarfile.DIRTYPE
        item.size = 1
        archive.addfile(item, io.BytesIO(b"x"))
    elif scenario == "duplicate-manifest":
        add("./MANIFEST.txt", manifest)
    elif scenario == "traversal":
        add("../outside")
    elif scenario == "unknown-file":
        add("etc/unknown")
    elif scenario == "too-many-members":
        for index in range(65):
            add(f"unused-{index}", kind=tarfile.DIRTYPE)
pathlib.Path(destination).chmod(0o600)
PY
}

test_complete_archive_reaches_isolated_validation() {
    local archive="$suite_root/valid.tar.gz" validation_reached=0 rc
    make_backup_archive "$archive" valid || return 1
    if pnm_core_restore "$archive"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 1 "$validation_reached"
}

test_unsafe_archives_stop_before_candidate_execution() {
    local scenario archive validation_reached rc
    for scenario in root-file root-directory-payload directory-payload oversized-manifest missing-tls absolute symlink duplicate duplicate-manifest traversal unknown-file too-many-members; do
        archive="$suite_root/$scenario.tar.gz"
        validation_reached=0
        make_backup_archive "$archive" "$scenario" || return 1
        if pnm_core_restore "$archive"; then rc=0; else rc=$?; fi
        assert_eq 78 "$rc" "$scenario must fail" || return 1
        assert_eq 0 "$validation_reached" "$scenario must stop before candidate validation/execution" || return 1
    done
}

run_test 'complete backup reaches isolated validation without executing candidates' test_complete_archive_reaches_isolated_validation
run_test 'unsafe backup archives stop before candidate execution' test_unsafe_archives_stop_before_candidate_execution
finish_tests
