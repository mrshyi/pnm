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
source "$PROJECT_ROOT/adapters/network.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT
pnm_require_root() { return 0; }
pnm_core_backup_source() { printf '%s/%s\n' "$fixture_root/host" "$1"; }
pnm_systemd_active_state() { printf 'active\n'; }
pnm_systemd_enabled_state() { printf 'enabled\n'; }

prepare_backup_fixture() {
    local file
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    PNM_LOCK_FILE="$fixture_root/lock" PNM_STATE_DIR="$fixture_root/state"
    destination="$fixture_root/backup.tar.gz"
    PNM_CONFIG_DIR="$fixture_root/host/etc/pnm"
    PNM_XRAY_BIN="$fixture_root/host/usr/local/bin/xray"
    PNM_HY2_BIN="$fixture_root/host/usr/local/bin/hysteria"
    PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
    for file in etc/pnm/node.conf etc/pnm/versions.conf etc/pnm/secrets/reality.env etc/pnm/secrets/hysteria.env \
        usr/local/etc/xray/config.json etc/hysteria/config.yaml etc/hysteria/tls/server.crt etc/hysteria/tls/server.key \
        usr/local/bin/xray usr/local/bin/hysteria etc/systemd/system/xray.service etc/systemd/system/hysteria-server.service; do
        mkdir -p -- "$fixture_root/host/$(dirname -- "$file")"
        printf 'private synthetic fixture\n' >"$fixture_root/host/$file"
    done
    cp "$TEST_ROOT/fixtures/config-secrets/node.conf" "$PNM_CONFIG_DIR/node.conf"
    sed -i 's/XRAY_PORT=443/XRAY_PORT=1443/;s/HY2_PORT=8443/HY2_PORT=18443/' "$PNM_CONFIG_DIR/node.conf"
    printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"$PNM_XRAY_BIN"
    printf '#!/usr/bin/env bash\nprintf "Version: 2.3.4\\n"\n' >"$PNM_HY2_BIN"
    chmod 0755 "$PNM_XRAY_BIN" "$PNM_HY2_BIN"
    trap 'pnm_cleanup' EXIT
}

test_backup_lock_precedes_preparation() {
    local holder
    prepare_backup_fixture
    exec {holder}>"$PNM_LOCK_FILE"
    flock -n -x "$holder" || return 1
    run_capture pnm_core_backup "$destination"
    flock -u "$holder"; exec {holder}>&-
    assert_eq 73 "$RUN_RC" || return 1
    [[ ! -e "$destination" && ${#PNM_CLEANUP_PATHS[@]} == 0 ]]
}

test_pending_recovery_precedes_preparation() {
    prepare_backup_fixture
    pnm_tx_assert_no_pending_deployment() { return 70; }
    run_capture pnm_core_backup "$destination"
    assert_eq 70 "$RUN_RC" || return 1
    [[ ! -e "$destination" && ${#PNM_CLEANUP_PATHS[@]} == 0 && $PNM_LOCK_DEPTH == 0 ]]
}

test_manifest_and_archive_use_the_same_snapshot() {
    local result='' manifest competitor stage
    prepare_backup_fixture
    install() {
        # All copies must exclude an independent cooperating writer.
        if flock -n "$PNM_LOCK_FILE" true; then return 91; fi
        command install "$@"
    }
    pnm_binary_version() {
        [[ "$1" != "$PNM_XRAY_BIN" && "$1" != "$PNM_HY2_BIN" ]] || return 92
        command bash "$1" version | head -n 1
    }
    pnm_core_backup "$destination" >/dev/null || return 1
    result="$PNM_CORE_BACKUP_PATH"
    assert_eq "$destination" "$result" || return 1
    manifest="$(tar -xOzf "$destination" ./MANIFEST.txt)" || return 1
    assert_contains "$manifest" 'TCP_PORT=1443' || return 1
    assert_contains "$manifest" 'UDP_PORT=18443' || return 1
    assert_contains "$manifest" 'XRAY_VERSION=Xray 1.2.3' || return 1
    assert_contains "$manifest" 'HY2_VERSION=Version: 2.3.4' || return 1
    assert_eq "600:$EUID" "$(stat -c '%a:%u' "$destination")" || return 1
    assert_eq 1 "${#PNM_CLEANUP_PATHS[@]}" || return 1
    stage=${PNM_CLEANUP_PATHS[0]}
    [[ -d "$stage" && $PNM_LOCK_DEPTH == 0 ]] || return 1
    competitor="$(tar -xOzf "$destination" ./etc/pnm/node.conf)" || return 1
    assert_contains "$competitor" 'XRAY_PORT=1443'
}

test_unsafe_source_ancestor_is_rejected() {
    prepare_backup_fixture
    mv "$fixture_root/host/etc/pnm/secrets" "$fixture_root/secrets"
    ln -s "$fixture_root/secrets" "$fixture_root/host/etc/pnm/secrets"
    run_capture pnm_core_backup "$destination"
    assert_eq 78 "$RUN_RC" || return 1
    [[ ! -e "$destination" && $PNM_LOCK_DEPTH == 0 ]]
}

test_late_destination_is_not_overwritten() {
    prepare_backup_fixture
    tar() { printf 'external destination\n' >"$destination"; command tar "$@"; }
    run_capture pnm_core_backup "$destination"
    assert_eq 73 "$RUN_RC" || return 1
    assert_eq 'external destination' "$(<"$destination")" || return 1
    [[ -z "$(find "$fixture_root" -maxdepth 1 -name '.pnm-backup.*' -print -quit)" ]]
}

test_failed_archiving_leaves_no_published_or_partial_output() {
    prepare_backup_fixture
    tar() { return 73; }
    run_capture pnm_core_backup "$destination"
    assert_eq 73 "$RUN_RC" || return 1
    [[ ! -e "$destination" && -z "$(find "$fixture_root" -maxdepth 1 -name '.pnm-backup.*' -print -quit)" && $PNM_LOCK_DEPTH == 0 ]]
}

test_uninstall_requests_backup_in_its_own_shell() {
    local backup_called=0
    prepare_backup_fixture
    PNM_ASSUME_YES=1
    pnm_core_backup() { backup_called=1; [[ $# == 1 ]] || return 91; return 77; }
    run_capture pnm_core_uninstall xray
    assert_eq 1 "$backup_called" || return 1
    assert_eq 77 "$RUN_RC"
}

test_cli_backup_retains_stdout_path() {
    prepare_backup_fixture
    run_capture pnm_core_backup "$destination"
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq "$destination" "$RUN_OUTPUT"
}

test_relative_destination_remains_supported() {
    prepare_backup_fixture
    cd "$fixture_root" || return 1
    run_capture pnm_core_backup backup.tar.gz
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq backup.tar.gz "$RUN_OUTPUT" || return 1
    [[ -f backup.tar.gz ]]
}

run_test 'backup supports an ordinary relative destination' test_relative_destination_remains_supported
run_test 'backup takes its lock before staging or output' test_backup_lock_precedes_preparation
run_test 'backup refuses pending recovery before staging or output' test_pending_recovery_precedes_preparation
run_test 'backup manifest uses the locked staged snapshot and retains caller cleanup' test_manifest_and_archive_use_the_same_snapshot
run_test 'backup refuses a symlink source ancestor' test_unsafe_source_ancestor_is_rejected
run_test 'backup publication preserves a late-created destination' test_late_destination_is_not_overwritten
run_test 'failed archive creation leaves no published or partial output' test_failed_archiving_leaves_no_published_or_partial_output
run_test 'uninstall prepares its backup in the same shell and preserves errors' test_uninstall_requests_backup_in_its_own_shell
run_test 'backup CLI still prints exactly its archive path' test_cli_backup_retains_stdout_path
finish_tests
