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
source "$PNM_LIB_DIR/deploy.sh"
source "$TEST_ROOT/testlib.sh"

DEPLOY_ORDER=''
DEPLOY_FAIL_PHASE=''

deploy_test_sandbox() { DEPLOY_ORDER+="sandbox,"; [[ "$DEPLOY_FAIL_PHASE" != sandbox ]]; }
deploy_test_xray() { DEPLOY_ORDER+="xray,"; [[ "$DEPLOY_FAIL_PHASE" != xray ]]; }
deploy_test_hysteria() { DEPLOY_ORDER+="hysteria,"; [[ "$DEPLOY_FAIL_PHASE" != hysteria ]]; }
deploy_test_health() { DEPLOY_ORDER+="health,"; [[ "$DEPLOY_FAIL_PHASE" != health ]]; }

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
    pnm_require_root() { return 0; }
    pnm_deploy_mark_configured() { return 0; }
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

run_test 'one-click deploy runs Core stages without SSH or UFW' test_core_deploy_runs_four_stages
run_test 'one-click deploy stops after a failed Core stage' test_core_deploy_stops_after_failed_stage
run_test 'one-click deploy rejects preflight failures before apply' test_apply_rejects_preflight_before_gate
finish_tests