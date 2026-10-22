#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"
# Reuse the trusted, non-executable archive fixture generator, not archive data.
source <(sed -n '/^make_backup_archive() {$/,/^}$/p' "$TEST_ROOT/unit/test_backup_archive.sh")
for name in pnm_core_restore_prepare_directory pnm_core_restore_write_file pnm_core_restore_rollback pnm_core_record_applied_config pnm_tx_commit pnm_tx_close; do
    source <(declare -f "$name" | sed "1s/$name/pnm_test_real_$name/")
done

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT

prepare_flow_fixture() {
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    fixture_host="$fixture_root/host"
    PNM_STATE_DIR="$fixture_root/state" PNM_LOCK_FILE="$fixture_root/lock/pnm.lock"
    PNM_XRAY_CONFIG="$fixture_host/usr/local/etc/xray/config.json"
    PNM_HY2_CONFIG="$fixture_host/etc/hysteria/config.yaml"
    PNM_XRAY_BIN="$fixture_host/usr/local/bin/xray" PNM_HY2_BIN="$fixture_host/usr/local/bin/hysteria"
    mkdir -p "$fixture_host/etc/pnm/secrets" "$fixture_host/etc/hysteria/tls" \
        "$fixture_host/usr/local/etc/xray" "$fixture_host/usr/local/bin" "$fixture_host/etc/systemd/system"
    local relative
    for relative in etc/pnm/node.conf etc/pnm/versions.conf etc/pnm/secrets/reality.env \
        etc/pnm/secrets/hysteria.env usr/local/etc/xray/config.json etc/hysteria/config.yaml \
        etc/hysteria/tls/server.crt etc/hysteria/tls/server.key usr/local/bin/xray usr/local/bin/hysteria \
        etc/systemd/system/xray.service etc/systemd/system/hysteria-server.service; do
        printf 'original %s\n' "$relative" >"$fixture_host/$relative"
        chmod 0600 "$fixture_host/$relative"
    done
    declare -gA fixture_active=([xray.service]=active [hysteria-server.service]=active)
    declare -gA fixture_enabled=([xray.service]=disabled [hysteria-server.service]=enabled)
    declare -gA fixture_loaded=([xray.service]=loaded [hysteria-server.service]=loaded)
    declare -gA fixture_restarts=([xray.service]=0 [hysteria-server.service]=0)
    declare -gA fixture_invocations=([xray.service]=0123456789abcdef0123456789abcdef [hysteria-server.service]=0123456789abcdef0123456789abcdef)
    mkdir "$fixture_host/etc/systemd/system/multi-user.target.wants"
    ln -s ../hysteria-server.service "$fixture_host/etc/systemd/system/multi-user.target.wants/hysteria-server.service"
    fixture_health_failures=0 fixture_stage_checked=0 fixture_require_stopped=0
    fixture_late_failure='' fixture_recovering=0 fixture_ignore_recovery=0 fixture_ignore_recovery_stop=0
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG"
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG"
    make_backup_archive "$fixture_root/archive.tar.gz" valid
}

pnm_require_root() { return 0; }
pnm_platform_supported() { return 0; }
stat() {
    local target="${!#}"
    # CI runs unprivileged: simulate only the root policy at the two host I/O
    # boundaries, while transaction metadata stays real. Root runs use real IDs.
    if ((EUID != 0)) && [[ "$1" == -c ]]; then
        if [[ "$2" == '%a:%u:%d:%i' && "$target" == "$fixture_root/archive.tar.gz" ]]; then
            command stat -c '%a:0:%d:%i' -- "$target"
            return $?
        elif [[ "$2" == '%u:%g' && "$target" == "$fixture_host/"* && -d "$target" ]]; then
            printf '0:0\n'
            return 0
        fi
    fi
    command stat "$@"
}
pnm_make_temp_dir() { local created_stage; created_stage="$(mktemp -d "$fixture_root/stage.XXXXXXXX")" || return $?; printf -v "$1" '%s' "$created_stage"; }
pnm_core_restore_validate_staged() { fixture_stage_checked=1; return 0; }
pnm_systemd_available() { return 0; }
pnm_systemd_load_state() { printf '%s\n' "${fixture_loaded[$1]}"; }
pnm_systemd_active_state() { printf '%s\n' "${fixture_active[$1]}"; }
pnm_systemd_enabled_state() { printf '%s\n' "${fixture_enabled[$1]}"; }
pnm_systemd_show_value() { printf '%s\n' "${fixture_invocations[$1]}"; }
pnm_systemd_daemon_reload() {
    local unit
    for unit in xray.service hysteria-server.service; do
        if [[ -f "$fixture_host/etc/systemd/system/$unit" ]]; then fixture_loaded[$unit]=loaded; else fixture_loaded[$unit]=not-found; fi
    done
}
pnm_systemctl() {
    local action="$1" unit="$2"
    if ((fixture_recovering == 1 && fixture_ignore_recovery == 1)) && [[ "$action" == restart ]]; then return 0; fi
    if ((fixture_recovering == 1 && fixture_ignore_recovery_stop == 1)) && [[ "$action" == stop ]]; then return 0; fi
    case "$action" in
        enable)
            mkdir -p "$fixture_host/etc/systemd/system/multi-user.target.wants"
            ln -sfn "../$unit" "$fixture_host/etc/systemd/system/multi-user.target.wants/$unit"
            fixture_enabled[$unit]=enabled
            ;;
        disable)
            rm -f "$fixture_host/etc/systemd/system/multi-user.target.wants/$unit"
            fixture_enabled[$unit]=disabled
            ;;
        stop) fixture_active[$unit]=inactive ;;
        restart)
            [[ "${fixture_loaded[$unit]}" == loaded ]] || return 69
            fixture_active[$unit]=active
            ((fixture_restarts[$unit] += 1))
            printf -v 'fixture_invocations[$unit]' '%032x' "${fixture_restarts[$unit]}"
            ;;
        *) return 70 ;;
    esac
}
pnm_systemd_unit_healthy() { [[ "${fixture_active[$1]}" == active && "${fixture_enabled[$1]}" == enabled ]]; }
pnm_check_deploy_core_health() {
    if ((fixture_health_failures > 0)); then ((fixture_health_failures -= 1)); return 1; fi
    return 0
}

# Only translate the two managed-destination boundaries into a private host
# tree. Parsing, dispatch, file transactions, compensation and hashes are real;
# candidate execution, named accounts and systemd observations are simulated.
pnm_core_restore_prepare_directory() { pnm_test_real_pnm_core_restore_prepare_directory "$fixture_host$1" "$2"; }
pnm_core_restore_write_file() {
    local owner="$5"
    if ((fixture_require_stopped == 1)); then
        [[ "${fixture_active[xray.service]}" == inactive && "${fixture_active[hysteria-server.service]}" == inactive ]] || return 70
    fi
    case "$owner" in
        root:root) owner="$EUID:$(id -g)" ;;
        root:xray|root:hysteria)
            if ((EUID == 0)); then owner="0:$(id -g nobody)"; else owner="$EUID:$(id -g)"; fi
            ;;
        hysteria:hysteria)
            if ((EUID == 0)); then owner="$(id -u nobody):$(id -g nobody)"; else owner="$EUID:$(id -g)"; fi
            ;;
    esac
    pnm_test_real_pnm_core_restore_write_file "$1" "$fixture_host$2" "$3" "$4" "$owner"
    local rc=$?
    [[ "$fixture_late_failure" != write || "$3" != restore_6 ]] || return 73
    return "$rc"
}
pnm_core_restore_rollback() { fixture_recovering=1; pnm_test_real_pnm_core_restore_rollback; }
pnm_core_record_applied_config() {
    if [[ "$fixture_late_failure" == applied && "$1" == hysteria2 && "$fixture_recovering" == 0 ]]; then return 73; fi
    pnm_test_real_pnm_core_record_applied_config "$@"
}
pnm_tx_commit() {
    [[ "$fixture_late_failure" != commit ]] || return 73
    pnm_test_real_pnm_tx_commit "$@"
}

assert_original_resources() {
    assert_eq 'original usr/local/etc/xray/config.json' "$(<"$PNM_XRAY_CONFIG")" || return 1
    assert_eq 'original etc/hysteria/config.yaml' "$(<"$PNM_HY2_CONFIG")" || return 1
    assert_eq 'original usr/local/bin/xray' "$(<"$PNM_XRAY_BIN")" || return 1
    assert_eq 'original usr/local/bin/hysteria' "$(<"$PNM_HY2_BIN")"
}

test_restore_success_publishes_both_confirmed_records() {
    local baseline
    prepare_flow_fixture || return 1
    pnm_core_restore "$fixture_root/archive.tar.gz" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status hysteria2 "$PNM_HY2_CONFIG")" || return 1
    for baseline in "$PNM_STATE_DIR"/transactions/*/restore.env; do
        assert_eq "600:$EUID" "$(stat -c '%a:%u' "$baseline")" || return 1
        assert_contains "$(<"$baseline")" 'XRAY_ENABLED=disabled' || return 1
    done
    assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_restore_stops_processes_before_resource_publication() {
    prepare_flow_fixture || return 1
    fixture_require_stopped=1
    pnm_core_restore "$fixture_root/archive.tar.gz"
}

test_restore_late_failures_recover_service_and_applied_baselines() {
    local failure rc
    for failure in health applied commit write; do
        prepare_flow_fixture || return 1
        if [[ "$failure" == health ]]; then fixture_health_failures=1; else fixture_late_failure="$failure"; fi
        if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
        [[ "$rc" != 0 ]] || return 1
        assert_original_resources || return 1
        assert_eq active "${fixture_active[xray.service]}" || return 1
        assert_eq disabled "${fixture_enabled[xray.service]}" || return 1
        assert_eq active "${fixture_active[hysteria-server.service]}" || return 1
        assert_eq enabled "${fixture_enabled[hysteria-server.service]}" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status hysteria2 "$PNM_HY2_CONFIG")" || return 1
        assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
        flock -n "$PNM_LOCK_FILE" true || return 1
    done
}

test_restore_lock_contention_precedes_candidate_validation() {
    local owner_fd rc
    prepare_flow_fixture || return 1
    mkdir -p "$(dirname "$PNM_LOCK_FILE")"
    exec {owner_fd}>"$PNM_LOCK_FILE"
    flock -x "$owner_fd" || return 1
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    assert_eq 73 "$rc" || return 1
    assert_eq 0 "$fixture_stage_checked" || return 1
    assert_original_resources || return 1
    exec {owner_fd}>&-
}

test_restore_rejects_unknown_baselines_before_resource_changes() {
    local rc
    prepare_flow_fixture || return 1
    fixture_enabled[xray.service]=masked
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    [[ "$rc" != 0 ]] || return 1
    assert_original_resources || return 1
    assert_eq 0 "${fixture_restarts[xray.service]}"
}

test_restore_detects_ineffective_service_recovery() {
    prepare_flow_fixture || return 1
    fixture_health_failures=1 fixture_ignore_recovery=1
    run_capture pnm_core_restore "$fixture_root/archive.tar.gz"
    [[ "$RUN_RC" != 0 ]] || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_contains "$RUN_ERROR" 'rollback failed' || return 1
    assert_not_contains "$RUN_OUTPUT" 'Both Cores restored and healthy'
}

test_restore_recovers_originally_absent_and_inactive_services() {
    local scenario original_applied rc
    for scenario in absent inactive; do
        prepare_flow_fixture || return 1
        fixture_active[hysteria-server.service]=inactive
        fixture_enabled[hysteria-server.service]=disabled
        if [[ "$scenario" == absent ]]; then
            rm "$fixture_host/etc/systemd/system/hysteria-server.service" "$PNM_STATE_DIR/cores/hysteria2/applied.env"
            fixture_loaded[hysteria-server.service]=not-found
        else
            original_applied="$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/hysteria2/applied.env")"
        fi
        fixture_late_failure=applied
        if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
        assert_eq 73 "$rc" || return 1
        assert_original_resources || return 1
        assert_eq inactive "${fixture_active[hysteria-server.service]}" || return 1
        assert_eq disabled "${fixture_enabled[hysteria-server.service]}" || return 1
        if [[ "$scenario" == absent ]]; then
            [[ ! -e "$fixture_host/etc/systemd/system/hysteria-server.service" ]] || return 1
            [[ ! -e "$PNM_STATE_DIR/cores/hysteria2/applied.env" ]] || return 1
            assert_eq not-found "${fixture_loaded[hysteria-server.service]}" || return 1
        else
            assert_eq "$original_applied" "$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/hysteria2/applied.env")" || return 1
        fi
        assert_eq 0 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    done
}

test_restore_does_not_promote_unconfirmed_original_evidence_on_failure() {
    local original_applied rc
    prepare_flow_fixture || return 1
    printf 'damaged fixture\n' >"$PNM_STATE_DIR/cores/xray/applied.env"
    original_applied="$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/xray/applied.env")"
    fixture_late_failure=commit
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    assert_eq 73 "$rc" || return 1
    assert_eq "$original_applied" "$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/xray/applied.env")" || return 1
    assert_eq damaged "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")"
}

test_restore_pending_deployment_precedes_validation() {
    local rc
    prepare_flow_fixture || return 1
    pnm_tx_assert_no_pending_deployment() { return 70; }
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 0 "$fixture_stage_checked" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_restore_preserves_callers_lock_and_locks_preparation() {
    prepare_flow_fixture || return 1
    pnm_core_restore_validate_staged() { ! flock -n "$PNM_LOCK_FILE" true; }
    pnm_lock_acquire exclusive || return 1
    pnm_core_restore "$fixture_root/archive.tar.gz" || return 1
    assert_eq 1 "$PNM_LOCK_DEPTH" || return 1
    if flock -n "$PNM_LOCK_FILE" true; then return 1; fi
    pnm_lock_release || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_restore_close_error_suppresses_success_and_releases_lock() {
    prepare_flow_fixture || return 1
    pnm_tx_close() { pnm_test_real_pnm_tx_close "$@" || return $?; return 70; }
    run_capture pnm_core_restore "$fixture_root/archive.tar.gz"
    assert_eq 70 "$RUN_RC" || return 1
    assert_not_contains "$RUN_OUTPUT" 'Both Cores restored and healthy' || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_restore_preserves_external_original_applied_edits() {
    local edited_hash
    prepare_flow_fixture || return 1
    pnm_check_deploy_core_health() {
        [[ "$1" != xray ]] || printf '# external edit\n' >>"$PNM_STATE_DIR/cores/xray/applied.env"
    }
    run_capture pnm_core_restore "$fixture_root/archive.tar.gz"
    assert_eq 70 "$RUN_RC" || return 1
    edited_hash="$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/xray/applied.env")"
    assert_contains "$(<"$PNM_STATE_DIR/cores/xray/applied.env")" '# external edit' || return 1
    [[ "$edited_hash" != "${PNM_CORE_RESTORE_APPLIED_HASH[xray]:-MISSING}" ]] || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_contains "$RUN_ERROR" 'rollback failed'
}

test_restore_refuses_missing_units_with_live_processes() {
    local rc
    prepare_flow_fixture || return 1
    fixture_loaded[xray.service]=not-found
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    [[ "$rc" != 0 ]] || return 1
    assert_original_resources
}

test_restore_compensates_enable_created_wants_directory() {
    local rc
    prepare_flow_fixture || return 1
    rm "$fixture_host/etc/systemd/system/multi-user.target.wants/hysteria-server.service"
    rmdir "$fixture_host/etc/systemd/system/multi-user.target.wants"
    fixture_enabled[hysteria-server.service]=disabled
    fixture_health_failures=1
    if pnm_core_restore "$fixture_root/archive.tar.gz"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 0 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    [[ ! -e "$fixture_host/etc/systemd/system/multi-user.target.wants" ]]
}

test_restore_refuses_file_compensation_until_processes_stop() {
    prepare_flow_fixture || return 1
    fixture_health_failures=1 fixture_ignore_recovery_stop=1
    run_capture pnm_core_restore "$fixture_root/archive.tar.gz"
    [[ "$RUN_RC" != 0 ]] || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq 'non-executable fixture' "$(<"$PNM_XRAY_CONFIG")" || return 1
    assert_contains "$RUN_ERROR" 'rollback failed'
}

run_test 'restore flow publishes both confirmed applied records' test_restore_success_publishes_both_confirmed_records
run_test 'restore stops both processes before publishing runtime resources' test_restore_stops_processes_before_resource_publication
run_test 'restore late failures recover service and applied baselines' test_restore_late_failures_recover_service_and_applied_baselines
run_test 'restore lock contention precedes candidate validation' test_restore_lock_contention_precedes_candidate_validation
run_test 'restore rejects unsupported service baselines before mutation' test_restore_rejects_unknown_baselines_before_resource_changes
run_test 'restore detects ineffective service recovery and reports it' test_restore_detects_ineffective_service_recovery
run_test 'restore recovers absent and inactive service baselines' test_restore_recovers_originally_absent_and_inactive_services
run_test 'failed restore preserves unconfirmed original applied evidence' test_restore_does_not_promote_unconfirmed_original_evidence_on_failure
run_test 'restore pending deployment refuses before candidate validation' test_restore_pending_deployment_precedes_validation
run_test 'restore preparation remains locked and preserves caller ownership' test_restore_preserves_callers_lock_and_locks_preparation
run_test 'restore close errors suppress success and release the write lock' test_restore_close_error_suppresses_success_and_releases_lock
run_test 'restore retains external edits to original applied evidence' test_restore_preserves_external_original_applied_edits
run_test 'restore refuses missing units with live processes before mutation' test_restore_refuses_missing_units_with_live_processes
run_test 'restore compensates directories created by enable' test_restore_compensates_enable_created_wants_directory
run_test 'restore compensation requires observed process stop before file writes' test_restore_refuses_file_compensation_until_processes_stop
finish_tests
