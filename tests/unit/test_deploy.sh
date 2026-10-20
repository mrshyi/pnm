#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
source "$PNM_LIB_DIR/common.sh"
source "$PNM_LIB_DIR/output.sh"
source "$PNM_LIB_DIR/config.sh"
source "$PNM_LIB_DIR/lock.sh"
source "$PNM_LIB_DIR/transaction.sh"
source "$PNM_ADAPTER_DIR/systemd.sh"
source "$PNM_LIB_DIR/lifecycle.sh"
source "$PNM_LIB_DIR/sandbox-install.sh"
source "$PNM_LIB_DIR/check.sh"
source "$PNM_LIB_DIR/deploy.sh"
source "$TEST_ROOT/testlib.sh"

DEPLOY_ORDER=''
DEPLOY_FAIL_PHASE=''
DEPLOY_MARK_CONFIGURED_CALLS=0
DEPLOY_RESTORE_CALLS=0

deploy_test_sandbox() { DEPLOY_ORDER+="sandbox,"; [[ "$DEPLOY_FAIL_PHASE" != sandbox ]]; }
deploy_test_xray() { DEPLOY_ORDER+="xray,"; [[ "$DEPLOY_FAIL_PHASE" != xray ]]; }
deploy_test_hysteria() { DEPLOY_ORDER+="hysteria,"; [[ "$DEPLOY_FAIL_PHASE" != hysteria ]]; }
deploy_test_health() { DEPLOY_ORDER+="health,"; [[ "$DEPLOY_FAIL_PHASE" != health ]]; }
pnm_deploy_mark_configured() { DEPLOY_MARK_CONFIGURED_CALLS=$((DEPLOY_MARK_CONFIGURED_CALLS + 1)); }

prepare_deploy() {
    local temp_dir="$1"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_DRY_RUN=0
    PNM_DEPLOY_ID_OVERRIDE='deploy-test'
    PNM_DEPLOY_STEP_SANDBOX=deploy_test_sandbox
    PNM_DEPLOY_STEP_XRAY=deploy_test_xray
    PNM_DEPLOY_STEP_HYSTERIA=deploy_test_hysteria
    PNM_DEPLOY_STEP_HEALTH=deploy_test_health
    DEPLOY_ORDER=''
    DEPLOY_FAIL_PHASE=''
    DEPLOY_MARK_CONFIGURED_CALLS=0
    DEPLOY_RESTORE_CALLS=0
    pnm_require_root() { return 0; }
    pnm_systemd_load_state() { printf 'not-found\n'; }
    pnm_systemd_active_state() { printf 'inactive\n'; }
    pnm_systemd_enabled_state() { printf 'disabled\n'; }
    pnm_systemctl() { return 0; }
    stat() {
        case "$*" in
            *"$PNM_STATE_DIR"*) printf '700|%s\n' "$EUID" ;;
            *) command stat "$@" ;;
        esac
    }
    pnm_deploy_restore_service_state() { ((DEPLOY_RESTORE_CALLS += 1)); }
}

test_core_deploy_runs_four_stages() {
    local temp_dir journal
    temp_dir="$(mktemp -d)"
    prepare_deploy "$temp_dir"
    pnm_deploy_execute || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 'sandbox,xray,hysteria,health,' "$DEPLOY_ORDER" || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_STATE_DIR/deployments/deploy-test/journal.tsv"
    assert_contains "$(<"$journal")" $'COMMIT\t'
    assert_not_contains "$(<"$journal")" 'ssh-access'
    assert_not_contains "$(<"$journal")" 'ufw-access'
    rm -rf -- "$temp_dir"
}

test_core_deploy_stops_after_failed_stage() {
    local temp_dir rc journal
    temp_dir="$(mktemp -d)"
    prepare_deploy "$temp_dir"
    DEPLOY_FAIL_PHASE=xray
    if pnm_deploy_execute; then rc=0; else rc=$?; fi
    [[ "$rc" != 0 ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 'sandbox,xray,' "$DEPLOY_ORDER" || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_STATE_DIR/deployments/deploy-test/journal.tsv"
    assert_contains "$(<"$journal")" $'STOPPED\tafter=xray-lifecycle'
    rm -rf -- "$temp_dir"
}

test_post_health_failure_is_not_reported_as_committed() {
    local temp_dir rc journal contents
    temp_dir="$(mktemp -d)"
    prepare_deploy "$temp_dir"
    DEPLOY_FAIL_PHASE=health
    if pnm_deploy_execute; then rc=0; else rc=$?; fi
    journal="$PNM_STATE_DIR/deployments/deploy-test/journal.tsv"
    contents="$(<"$journal")"
    assert_eq 1 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 'sandbox,xray,hysteria,health,' "$DEPLOY_ORDER" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$DEPLOY_MARK_CONFIGURED_CALLS" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "$DEPLOY_RESTORE_CALLS" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$contents" $'STOPPED\tafter=post-health rc=1' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$contents" $'ABANDONED\tdeployment closed without commit' || { rm -rf -- "$temp_dir"; return 1; }
    assert_not_contains "$contents" $'COMMIT\t'
    rm -rf -- "$temp_dir"
}

test_post_health_failure_can_be_retried_as_a_new_deployment() {
    local temp_dir rc journal
    temp_dir="$(mktemp -d)"
    prepare_deploy "$temp_dir"
    DEPLOY_FAIL_PHASE=health
    if pnm_deploy_execute; then rc=0; else rc=$?; fi
    assert_eq 1 "$rc" || { rm -rf -- "$temp_dir"; return 1; }

    DEPLOY_FAIL_PHASE=''
    PNM_DEPLOY_ID_OVERRIDE='deploy-retry'
    if ! pnm_deploy_execute; then rm -rf -- "$temp_dir"; return 1; fi
    journal="$PNM_STATE_DIR/deployments/deploy-retry/journal.tsv"
    assert_contains "$(<"$journal")" $'COMMIT\t' || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "$DEPLOY_MARK_CONFIGURED_CALLS" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 'sandbox,xray,hysteria,health,sandbox,xray,hysteria,health,' "$DEPLOY_ORDER" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_apply_rejects_preflight_before_gate() {
    local temp_dir rc calls=0
    temp_dir="$(mktemp -d)"
    prepare_deploy "$temp_dir"
    pnm_preflight_collect() { :; }
    pnm_preflight_exit_code() { return "$PNM_EXIT_FAIL"; }
    pnm_apply_gate_execute() { ((calls += 1)); return 0; }
    if pnm_deploy_apply >/dev/null 2>&1; then rc=0; else rc=$?; fi
    assert_eq "$PNM_EXIT_FAIL" "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$calls" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_deploy_health_checks_both_cores() {
    local calls=''
    pnm_check_deploy_core_health() { calls+="$1,"; }
    pnm_deploy_health_step || return 1
    assert_eq 'xray,hysteria2,' "$calls"
}

test_failed_deploy_restores_prior_active_and_enabled_state() {
    local temp_dir calls
    temp_dir="$(mktemp -d)"
    PNM_TEST_SYSTEMCTL_LOG="$temp_dir/systemctl.log"
    PNM_DEPLOY_XRAY_ACTIVE=active PNM_DEPLOY_XRAY_ENABLED=enabled
    PNM_DEPLOY_HY2_ACTIVE=inactive PNM_DEPLOY_HY2_ENABLED=disabled
    pnm_systemctl() { printf '%s;' "$*" >>"$PNM_TEST_SYSTEMCTL_LOG"; }
    pnm_deploy_restore_service_state || { rm -rf -- "$temp_dir"; return 1; }
    calls="$(<"$PNM_TEST_SYSTEMCTL_LOG")"
    rm -rf -- "$temp_dir"
    assert_eq 'enable xray.service;restart xray.service;disable hysteria-server.service;stop hysteria-server.service;' "$calls"
}

test_post_health_journal_failure_still_restores_prior_services() {
    local rc
    PNM_DEPLOY_ACTIVE=0
    PNM_DEPLOY_JOURNAL_ERROR=0
    DEPLOY_RESTORE_CALLS=0
    pnm_deploy_begin() { PNM_DEPLOY_ACTIVE=1; return 0; }
    pnm_deploy_run_phase() {
        if [[ "$1" == post-health ]]; then
            PNM_DEPLOY_JOURNAL_ERROR=1
            return "$PNM_EXIT_CANTCREAT"
        fi
        return 0
    }
    pnm_deploy_close() { PNM_DEPLOY_ACTIVE=0; return 0; }
    if pnm_deploy_execute >/dev/null 2>&1; then rc=0; else rc=$?; fi
    assert_eq "$PNM_EXIT_CANTCREAT" "$rc" || return 1
    assert_eq 1 "$DEPLOY_RESTORE_CALLS"
}

run_test 'one-click deploy runs Core stages without SSH or UFW' test_core_deploy_runs_four_stages
run_test 'one-click deploy stops after a failed Core stage' test_core_deploy_stops_after_failed_stage
run_test 'post-health failure is not reported as a committed deployment' test_post_health_failure_is_not_reported_as_committed
run_test 'post-health failure can be retried and committed by a new deployment' test_post_health_failure_can_be_retried_as_a_new_deployment
run_test 'one-click deploy rejects preflight failures before apply' test_apply_rejects_preflight_before_gate
run_test 'post-install health checks both systemd Core services' test_deploy_health_checks_both_cores
run_test 'failed deployment restores prior Core active and enabled states' test_failed_deploy_restores_prior_active_and_enabled_state
run_test 'post-health journal failure still restores prior services' test_post_health_journal_failure_still_restores_prior_services
finish_tests
