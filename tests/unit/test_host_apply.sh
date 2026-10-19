#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/lock.sh
source "$PNM_LIB_DIR/lock.sh"
# shellcheck source=../../lib/transaction.sh
source "$PNM_LIB_DIR/transaction.sh"
# shellcheck source=../../lib/accounts.sh
source "$PNM_LIB_DIR/accounts.sh"
# shellcheck source=../../adapters/assets.sh
source "$PNM_ADAPTER_DIR/assets.sh"
# shellcheck source=../../lib/sandbox-install.sh
source "$PNM_LIB_DIR/sandbox-install.sh"
# shellcheck source=../../lib/host-apply.sh
source "$PNM_LIB_DIR/host-apply.sh"
# shellcheck source=../../lib/deploy.sh
source "$PNM_LIB_DIR/deploy.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_host_root_requires_apply_gate() {
    local rc
    PNM_SANDBOX_ROOT=/
    PNM_APPLY_GATE_ACTIVE=0
    PNM_HOST_APPLY_CONFIRMED=no
    if pnm_sandbox_path /etc/pnm; then rc=0; else rc=$?; fi
    assert_eq 77 "$rc"
}

test_host_resources_require_explicit_confirmation_before_accounts() {
    local rc calls=0
    PNM_APPLY_GATE_ACTIVE=0
    PNM_HOST_APPLY_CONFIRMED=no
    pnm_ensure_service_account() { calls=$((calls + 1)); return 0; }
    if pnm_host_apply_resources_step; then rc=0; else rc=$?; fi
    assert_eq 77 "$rc" || return 1
    assert_eq 0 "$calls"
}

test_host_resources_require_fixed_verified_assets() (
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_CONFIG_DIR="$PROJECT_ROOT/tests/fixtures/config-valid"
    PNM_HOST_XRAY_ARCHIVE="$temp_dir/missing-xray.zip"
    PNM_HOST_HY2_BINARY="$temp_dir/missing-hysteria"
    PNM_APPLY_GATE_ACTIVE=1
    PNM_HOST_APPLY_CONFIRMED=yes
    PNM_ASSUME_YES=1
    PNM_DRY_RUN=0
    pnm_require_root() { return 0; }
    if pnm_host_apply_resources_step; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
)

test_deploy_root_resource_path_is_not_directly_reachable() {
    local rc
    PNM_DEPLOY_SANDBOX_ROOT=/
    PNM_APPLY_GATE_ACTIVE=0
    PNM_HOST_APPLY_CONFIRMED=no
    if pnm_deploy_sandbox_step; then rc=0; else rc=$?; fi
    assert_eq 77 "$rc"
}

test_host_resources_download_fixed_assets_to_private_cache() {
    local temp_dir payload digest calls=0
    temp_dir="$(mktemp -d)"
    payload='verified asset payload'
    digest="$(printf '%s' "$payload" | sha256sum | awk '{print $1}')"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_HOST_ASSET_DIR="$PNM_STATE_DIR/assets"
    PNM_HOST_XRAY_ARCHIVE=''
    PNM_HOST_HY2_BINARY=''
    pnm_load_versions_config() {
        local -n target_versions="$1"
        target_versions=([XRAY_VERSION]=v1.2.3 [XRAY_SHA256]="$digest" [HY2_VERSION]=v2.3.4 [HY2_SHA256]="$digest" [APPROVED]=yes [SCHEMA_VERSION]=1)
    }
    pnm_validate_versions_config() { return 0; }
    pnm_asset_download_verified() {
        ((calls += 1))
        printf '%s' "$payload" >"$4"
    }
    pnm_host_apply_asset_precheck || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 2 "$calls" || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$PNM_HOST_XRAY_ARCHIVE" == "$PNM_HOST_ASSET_DIR/xray-v1.2.3-$digest.zip" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$PNM_HOST_HY2_BINARY" == "$PNM_HOST_ASSET_DIR/hysteria2-v2.3.4-$digest.bin" ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq '700' "$(stat -c '%a' "$PNM_HOST_ASSET_DIR")" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}
test_directory_helper_never_chmods_root() (
    local path rc chmod_calls=0
    mkdir() { return 0; }
    chmod() { ((chmod_calls += 1)); }
    for path in / // /./ /tmp/..; do
        if pnm_mkdir_mode 0700 "$path"; then rc=0; else rc=$?; fi
        assert_eq 78 "$rc" "root alias must be rejected: $path" || return 1
    done
    assert_eq 0 "$chmod_calls"
)

test_host_install_keeps_root_on_config_failure() (
    local rc mutations=0
    PNM_APPLY_GATE_ACTIVE=1
    PNM_HOST_APPLY_CONFIRMED=yes
    pnm_require_root() { return 0; }
    pnm_mkdir_mode() { ((mutations += 1)); }
    pnm_load_node_config() { return 78; }
    if pnm_sandbox_install /; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 0 "$mutations" 'invalid configuration must not change directory modes' || return 1
    assert_eq / "$PNM_SANDBOX_ROOT"
)

test_root_alias_cannot_bypass_host_gate() (
    local path rc mutations=0
    PNM_APPLY_GATE_ACTIVE=0
    PNM_HOST_APPLY_CONFIRMED=no
    pnm_mkdir_mode() { ((mutations += 1)); }
    pnm_load_node_config() { return 78; }
    for path in // /./ /tmp/..; do
        if pnm_sandbox_install "$path"; then rc=0; else rc=$?; fi
        [[ "$rc" == 77 || "$rc" == 78 ]] || return 1
    done
    assert_eq 0 "$mutations" 'root aliases must be rejected before filesystem changes'
)

# Exercise the host branch without writing any host resource or requiring root.
run_host_install_safety_case() (
    local failure="$1" temp_dir rc accounts=0 restored=0
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_APPLY_GATE_ACTIVE=1
    PNM_HOST_APPLY_CONFIRMED=yes
    PNM_DRY_RUN=0
    pnm_require_root() { return 0; }
    pnm_mkdir_mode() { return 99; }
    pnm_load_node_config() {
        PNM_SANDBOX_NODE=(
            [SCHEMA_VERSION]=1 [PNM_CONFIGURED]=no [NODE_REGION]=vps [NODE_ADDRESS]=203.0.113.10
            [TIMEZONE]=UTC [XRAY_PORT]=443 [XRAY_SERVER_NAME]=example.com [XRAY_TARGET]=example.com:443
            [HY2_PORT]=8443 [HY2_TLS_MODE]=selfsigned-pin
        )
    }
    pnm_sandbox_prepare_secrets() { PNM_SANDBOX_GENERATE_REALITY_SECRET=0; PNM_SANDBOX_GENERATE_HYSTERIA_SECRET=0; }
    pnm_sandbox_generate_missing_secrets() { return 0; }
    pnm_tx_begin() {
        PNM_TX_ACTIVE=1
        PNM_TX_COMMITTED=0
        PNM_TX_ROLLED_BACK=0
        PNM_TX_RECOVERY_REQUIRED=0
        PNM_TX_ROLLBACKS=()
        PNM_TX_PATH="$temp_dir/transaction"
        mkdir -m 0700 -- "$PNM_TX_PATH"
    }
    pnm_service_accounts_step() { ((accounts += 1)); }
    pnm_service_accounts_rollback() { return 0; }
    pnm_tx_restore_written_files() {
        ((restored += 1))
        [[ "$failure" != rollback ]] || return 70
    }
    pnm_sandbox_prepare_dirs() {
        assert_eq /etc/pnm "$(pnm_sandbox_path /etc/pnm)"
    }
    pnm_sandbox_step_assets() {
        [[ "$PNM_SANDBOX_STAGING" == "$PNM_TX_PATH/staging" && -d "$PNM_SANDBOX_STAGING" ]]
    }
    pnm_sandbox_step_tls() { return 0; }
    pnm_sandbox_step_secrets() { return 0; }
    pnm_sandbox_step_configs() { assert_eq / "$PNM_SANDBOX_ROOT"; }
    pnm_sandbox_step_units() { return 0; }
    pnm_sandbox_step_validate() { [[ "$failure" != validate && "$failure" != rollback ]] || return 78; }
    if [[ "$failure" == commit ]]; then
        pnm_tx_commit() { return 73; }
    fi
    if pnm_sandbox_install /; then rc=0; else rc=$?; fi
    case "$failure" in
        none) assert_eq 0 "$rc" && assert_eq 0 "$restored" || return 1 ;;
        validate) assert_eq 78 "$rc" && assert_eq 1 "$restored" || return 1 ;;
        commit) assert_eq 73 "$rc" && assert_eq 1 "$restored" || return 1 ;;
        rollback) assert_eq 70 "$rc" && assert_eq 1 "$restored" || return 1 ;;
    esac
    assert_eq 1 "$accounts" 'host branch must create service identities' || return 1
    if [[ "$failure" == rollback ]]; then
        [[ -d "$PNM_SANDBOX_STAGING" ]] || return 1
    else
        [[ ! -e "$PNM_SANDBOX_STAGING" ]] || return 1
    fi
    assert_eq 0 "$PNM_TX_ACTIVE"
)

test_host_install_safety() { run_host_install_safety_case none; }
test_host_install_validation_rollback() { run_host_install_safety_case validate; }
test_host_install_commit_rollback() { run_host_install_safety_case commit; }
test_host_install_failed_rollback() { run_host_install_safety_case rollback; }

test_staging_cleanup_rejects_other_directories() (
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    mkdir -- "$temp_dir/outside"
    PNM_TX_PATH="$temp_dir/transaction"
    PNM_SANDBOX_STAGING="$temp_dir/outside"
    if pnm_sandbox_cleanup_staging; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    [[ -d "$temp_dir/outside" ]] || return 1
    PNM_TX_PATH=/
    PNM_SANDBOX_STAGING=/staging
    if pnm_sandbox_cleanup_staging; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc"
)

run_test 'directory helper refuses root and its aliases' test_directory_helper_never_chmods_root
run_test 'host config failure leaves root permissions untouched' test_host_install_keeps_root_on_config_failure
run_test 'root aliases cannot bypass the apply gate' test_root_alias_cannot_bypass_host_gate
run_test 'host install keeps root identity and uses private transaction staging' test_host_install_safety
run_test 'host validation failure rolls back and cleans staging' test_host_install_validation_rollback
run_test 'host commit failure rolls back and cleans staging' test_host_install_commit_rollback
run_test 'failed rollback retains staging without retrying compensation' test_host_install_failed_rollback
run_test 'staging cleanup refuses directories outside the transaction' test_staging_cleanup_rejects_other_directories
run_test 'host sandbox root requires apply gate' test_host_root_requires_apply_gate
run_test 'host resources require explicit confirmation before accounts' test_host_resources_require_explicit_confirmation_before_accounts
run_test 'host resources require fixed verified assets' test_host_resources_require_fixed_verified_assets
run_test 'host resources download fixed verified assets to a private cache' test_host_resources_download_fixed_assets_to_private_cache
run_test 'deployment root resource path is not directly reachable' test_deploy_root_resource_path_is_not_directly_reachable
finish_tests
