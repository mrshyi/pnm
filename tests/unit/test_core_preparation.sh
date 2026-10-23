#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/lib/lifecycle.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT
pnm_require_root() { return 0; }
pnm_systemd_available() { return 0; }
pnm_systemctl() { return 0; }

prepare_fixture() {
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    PNM_STATE_DIR="$fixture_root/state" PNM_LOCK_FILE="$fixture_root/lock"
    PNM_XRAY_CONFIG="$fixture_root/config.json" PNM_HY2_CONFIG="$fixture_root/config.yaml"
    PNM_ASSUME_YES=1
    preparation_called=no preparation_locked=no
}
probe_preparation() {
    preparation_called=yes
    if flock -n "$PNM_LOCK_FILE" true; then preparation_locked=no; else preparation_locked=yes; fi
    return 69
}
pnm_core_lifecycle_snapshot() { probe_preparation; }
pnm_load_node_config() { probe_preparation; }
pnm_core_backup() { probe_preparation; }

dispatch_operation() {
    case "$1" in
        restart) pnm_core_restart xray ;;
        apply) pnm_core_apply_config xray ;;
        uninstall) pnm_core_uninstall xray ;;
        lifecycle) pnm_core_lifecycle_apply xray ;;
        *) return 64 ;;
    esac
}

test_preparation_is_locked_for_all_remaining_core_writers() {
    local operation
    for operation in restart apply uninstall lifecycle; do
        prepare_fixture
        run_capture dispatch_operation "$operation"
        [[ "$RUN_RC" != 0 ]] || return 1
        assert_eq yes "$preparation_called" "$operation must reach the private preparation probe" || return 1
        assert_eq yes "$preparation_locked" "$operation preparation must exclude another writer" || return 1
        assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    done
}
test_contention_precedes_all_preparation() {
    local operation holder
    for operation in restart apply uninstall lifecycle; do
        prepare_fixture
        exec {holder}>"$PNM_LOCK_FILE"
        flock -n -x "$holder" || return 1
        run_capture dispatch_operation "$operation"
        flock -u "$holder"; exec {holder}>&-
        assert_eq 73 "$RUN_RC" "$operation must refuse the competing writer" || return 1
        assert_eq no "$preparation_called" || return 1
        assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    done
}
test_pending_recovery_precedes_all_preparation() {
    local operation
    pnm_tx_assert_no_pending_deployment() { return 70; }
    for operation in restart apply uninstall lifecycle; do
        prepare_fixture
        run_capture dispatch_operation "$operation"
        assert_eq 70 "$RUN_RC" "$operation must refuse pending recovery" || return 1
        assert_eq no "$preparation_called" || return 1
        assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    done
}
test_config_recovery_preserves_original_numeric_metadata() {
    local original_attributes
    prepare_fixture
    pnm_core_resolve xray || return 1
    PNM_LIFECYCLE_PRE_ACTIVE=inactive
    printf 'original\n' >"$PNM_CORE_CONFIG"
    if ((EUID == 0)); then command chown "$(id -u nobody):$(id -g nobody)" "$PNM_CORE_CONFIG"; fi
    chmod 0751 "$PNM_CORE_CONFIG"
    original_attributes="$(stat -c '%a:%u:%g' "$PNM_CORE_CONFIG")"
    printf 'candidate\n' >"$fixture_root/candidate"
    # Only map named service identities; transaction numeric ownership is real.
    chown() {
        local owner=$1
        shift
        case "$owner" in root:xray|hysteria:hysteria) owner="$EUID:$(id -g)" ;; esac
        command chown "$owner" "$@"
    }
    pnm_tx_begin core-config-xray || return 1
    pnm_tx_add_rollback pnm_core_restore_config || return 1
    pnm_tx_write_file "$fixture_root/candidate" "$PNM_CORE_CONFIG" config 0640 required || return 1
    pnm_tx_rollback || return 1
    pnm_tx_close || return 1
    assert_eq original "$(<"$PNM_CORE_CONFIG")" || return 1
    assert_eq "$original_attributes" "$(stat -c '%a:%u:%g' "$PNM_CORE_CONFIG")"
}

test_preparation_retains_the_callers_lock_level() {
    local operation
    for operation in restart apply uninstall lifecycle; do
        prepare_fixture
        pnm_lock_acquire exclusive || return 1
        run_capture dispatch_operation "$operation"
        [[ "$RUN_RC" != 0 ]] || return 1
        assert_eq yes "$preparation_locked" || return 1
        assert_eq 1 "$PNM_LOCK_DEPTH" || return 1
        if flock -n "$PNM_LOCK_FILE" true; then return 1; fi
        pnm_lock_release || return 1
        flock -n "$PNM_LOCK_FILE" true || return 1
    done
}

test_uninstall_close_failure_retains_staging_and_reports_failure() {
    prepare_fixture
    PNM_CONFIG_DIR="$fixture_root/config"
    PNM_XRAY_BIN="$fixture_root/xray"
    pnm_core_backup() { PNM_CORE_BACKUP_PATH="$fixture_root/backup"; }
    pnm_core_lifecycle_snapshot() { return 0; }
    pnm_tx_begin() { PNM_TX_ACTIVE=1; }
    pnm_tx_add_rollback() { return 0; }
    pnm_tx_run() { return 0; }
    pnm_tx_commit() { return 0; }
    pnm_tx_close() { PNM_TX_ACTIVE=0; return 70; }
    pnm_systemd_daemon_reload() { return 0; }
    # Never move any host file, including the fixed standard unit path.
    mv() { return 0; }
    run_capture pnm_core_uninstall xray
    assert_eq 70 "$RUN_RC" || return 1
    assert_not_contains "$RUN_OUTPUT" 'removed; rollback backup' || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    [[ -n "$(find "$PNM_STATE_DIR/uninstall" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]
}

test_lifecycle_dry_run_journal_failure_is_propagated_and_closed() {
    prepare_fixture
    PNM_DRY_RUN=1
    pnm_core_lifecycle_snapshot() {
        PNM_LIFECYCLE_UNIT=xray.service PNM_LIFECYCLE_PRE_ACTIVE=inactive PNM_LIFECYCLE_PRE_ENABLED=disabled
    }
    pnm_tx_journal() { [[ "$1" != PLAN ]] || return 73; }
    run_capture pnm_core_lifecycle_apply xray
    assert_eq 73 "$RUN_RC" || return 1
    assert_eq 0 "$PNM_TX_ACTIVE" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
}

test_uninstall_preparation_cleanup_preserves_the_primary_error() {
    local fault expected failed=0
    for fault in snapshot begin; do
        prepare_fixture
        pnm_core_backup() { PNM_CORE_BACKUP_PATH="$fixture_root/backup"; }
        pnm_core_lifecycle_snapshot() { [[ "$fault" != snapshot ]] || return 69; }
        pnm_tx_begin() { return 73; }
        run_capture pnm_core_uninstall xray
        if [[ "$fault" == snapshot ]]; then expected=69; else expected=73; fi
        assert_eq "$expected" "$RUN_RC" "uninstall $fault failure must survive rmdir" || failed=1
        assert_eq 0 "$PNM_LOCK_DEPTH" || failed=1
    done
    return "$failed"
}

run_test 'uninstall preparation cleanup preserves snapshot and transaction errors' test_uninstall_preparation_cleanup_preserves_the_primary_error
run_test 'uninstall close failure retains private staging and suppresses success' test_uninstall_close_failure_retains_staging_and_reports_failure
run_test 'lifecycle dry-run journal failure closes and propagates' test_lifecycle_dry_run_journal_failure_is_propagated_and_closed
run_test 'remaining Core preparation preserves a callers reentrant lock' test_preparation_retains_the_callers_lock_level
run_test 'remaining Core preparation excludes independent writers' test_preparation_is_locked_for_all_remaining_core_writers
run_test 'remaining Core writers refuse contention before preparation' test_contention_precedes_all_preparation
run_test 'remaining Core writers refuse pending recovery before preparation' test_pending_recovery_precedes_all_preparation
run_test 'configuration compensation preserves original numeric metadata' test_config_recovery_preserves_original_numeric_metadata
finish_tests
