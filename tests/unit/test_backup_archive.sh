#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT
PNM_LOCK_FILE="$suite_root/pnm.lock" PNM_STATE_DIR="$suite_root/state"

pnm_require_root() { return 0; }
pnm_platform_supported() { return 0; }
pnm_make_temp_dir() { local created_stage; created_stage="$(mktemp -d "$suite_root/stage.XXXXXXXX")" || return $?; printf -v "$1" '%s' "$created_stage"; }
# Archive parsing tests stop before candidate execution or managed-path writes.
pnm_core_restore_validate_staged() { validation_reached=1; return 78; }
# Root ownership is simulated only when the suite runs as an unprivileged user.
stat() {
    if ((EUID != 0)) && [[ "$1" == -c && "$2" == '%a:%u:%d:%i' ]]; then
        command stat -c '%a:0:%d:%i' -- "$4"
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

prepare_resource_probe() {
    resource_probe_dir="$(mktemp -d "$suite_root/probe.XXXXXXXX")"
    resource_metrics="$resource_probe_dir/metrics"
    resource_outer_as=201326592 resource_outer_cpu=''
    cat >"$resource_probe_dir/sitecustomize.py" <<'PY'
import atexit
import os
import resource

def record_limits():
    with open(os.environ["PNM_TEST_RESOURCE_METRICS"], "w", encoding="ascii") as stream:
        stream.write(f"{resource.getrlimit(resource.RLIMIT_AS)[0]}|{resource.getrlimit(resource.RLIMIT_CPU)[0]}\n")

atexit.register(record_limits)
PY
    python3() {
        # Bound even the pre-fix interpreter to 192 MiB so a failing regression
        # cannot exhaust the WSL host. exec preserves the actual parser's stdin.
        PYTHONPATH="$resource_probe_dir" PNM_TEST_RESOURCE_METRICS="$resource_metrics" \
            PNM_TEST_OUTER_AS="$resource_outer_as" PNM_TEST_OUTER_CPU="$resource_outer_cpu" \
            command python3 -c 'import os, resource, sys
limit = int(os.environ["PNM_TEST_OUTER_AS"])
resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
cpu = os.environ["PNM_TEST_OUTER_CPU"]
if cpu:
    resource.setrlimit(resource.RLIMIT_CPU, (int(cpu), int(cpu)))
os.execv(sys.executable, [sys.executable, *sys.argv[1:]])' "$@"
    }
}

test_parser_has_finite_memory_and_cpu_budgets_before_validation() {
    local archive="$suite_root/budget.tar.gz" validation_reached=0 rc memory cpu
    prepare_resource_probe || return 1
    make_backup_archive "$archive" valid || return 1
    if pnm_core_restore "$archive"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 1 "$validation_reached" || return 1
    IFS='|' read -r memory cpu <"$resource_metrics"
    assert_eq 134217728 "$memory" 'archive parser must limit its own address space' || return 1
    assert_eq 30 "$cpu" 'archive parser must limit its own CPU time'
}

test_parser_preserves_stricter_inherited_resource_limits() {
    local archive="$suite_root/inherited-budget.tar.gz" validation_reached=0 rc memory cpu
    prepare_resource_probe || return 1
    resource_outer_as=100663296 resource_outer_cpu=10
    make_backup_archive "$archive" valid || return 1
    if pnm_core_restore "$archive"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 1 "$validation_reached" || return 1
    IFS='|' read -r memory cpu <"$resource_metrics"
    assert_eq 100663296 "$memory" || return 1
    assert_eq 10 "$cpu"
}

make_extension_archive() {
    command python3 - "$1" "$2" <<'PY'
import io
import pathlib
import sys
import tarfile

class ZeroReader(io.RawIOBase):
    def read(self, size=-1):
        if size < 0 or size > 1024 * 1024:
            raise ValueError("fixture producer must stream bounded chunks")
        return b"\0" * size

with tarfile.open(sys.argv[1], "w:gz", format=tarfile.USTAR_FORMAT) as archive:
    count = 2000 if sys.argv[2] == "pax-chain" else 1
    for _ in range(count):
        item = tarfile.TarInfo("././@Extension")
        item.type = tarfile.GNUTYPE_LONGNAME if sys.argv[2] == "gnu" else tarfile.XGLTYPE
        item.size = 0 if count > 1 else 192 * 1024 * 1024
        archive.addfile(item, ZeroReader())
pathlib.Path(sys.argv[1]).chmod(0o600)
PY
}

test_internal_tar_extensions_fail_cleanly_without_candidate_execution() {
    local scenario archive validation_reached
    prepare_resource_probe || return 1
    for scenario in pax gnu pax-chain; do
        archive="$suite_root/extension-$scenario.tar.gz"
        validation_reached=0
        make_extension_archive "$archive" "$scenario" || return 1
        run_capture pnm_core_restore "$archive"
        assert_eq 78 "$RUN_RC" || return 1
        assert_eq 0 "$validation_reached" || return 1
        assert_not_contains "$RUN_ERROR" 'Traceback' "$scenario must fail without an uncaught exception" || return 1
    done
}

test_checked_archive_identity_survives_replacement() {
    local scenario=$1 archive="$suite_root/identity-$1.tar.gz" replacement="$suite_root/replacement-$1.tar.gz" validation_reached=0
    make_backup_archive "$archive" valid || return 1
    make_backup_archive "$replacement" valid || return 1
    python3() {
        # Replace only at the real parser launch boundary, after the shell stat.
        if [[ "${2-}" == "$archive" && "${3-}" == "$suite_root/stage."* ]]; then
            case "$scenario" in
                inode) mv -f -- "$replacement" "$archive" ;;
                symlink) rm -- "$archive"; ln -s -- "$replacement" "$archive" ;;
                fifo) rm -- "$archive"; mkfifo -m 0600 -- "$archive" ;;
                mode) chmod 0644 -- "$archive" ;;
            esac
        fi
        # The old FIFO parser must not hang the test runner.
        command timeout 5s python3 "$@"
    }
    run_capture pnm_core_restore "$archive"
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq 0 "$validation_reached" || return 1
    assert_contains "$RUN_ERROR" 'invalid backup:' || return 1
    assert_not_contains "$RUN_ERROR" Traceback
}

test_archive_replaced_with_another_regular_file() { test_checked_archive_identity_survives_replacement inode; }
test_archive_replaced_with_a_symlink() { test_checked_archive_identity_survives_replacement symlink; }
test_archive_replaced_with_a_fifo() { test_checked_archive_identity_survives_replacement fifo; }
test_archive_permissions_changed_after_check() { test_checked_archive_identity_survives_replacement mode; }

run_test 'checked archive identity rejects replacement with another regular file' test_archive_replaced_with_another_regular_file
run_test 'checked archive identity rejects replacement with a symlink' test_archive_replaced_with_a_symlink
run_test 'checked archive identity rejects a FIFO without waiting for a writer' test_archive_replaced_with_a_fifo
run_test 'opened archive must retain protected permissions' test_archive_permissions_changed_after_check
run_test 'complete backup reaches isolated validation without executing candidates' test_complete_archive_reaches_isolated_validation
run_test 'unsafe backup archives stop before candidate execution' test_unsafe_archives_stop_before_candidate_execution
run_test 'archive parser sets finite memory and CPU budgets' test_parser_has_finite_memory_and_cpu_budgets_before_validation
run_test 'archive parser preserves stricter inherited resource budgets' test_parser_preserves_stricter_inherited_resource_limits
run_test 'tar internal extension exhaustion fails cleanly before validation' test_internal_tar_extensions_fail_cleanly_without_candidate_execution
finish_tests
