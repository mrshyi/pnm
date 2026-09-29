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

test_host_resources_require_fixed_verified_assets() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_CONFIG_DIR="$PROJECT_ROOT/tests/fixtures/config-valid"
    PNM_HOST_XRAY_ARCHIVE="$temp_dir/missing-xray.zip"
    PNM_HOST_HY2_BINARY="$temp_dir/missing-hysteria"
    PNM_APPLY_GATE_ACTIVE=1
    PNM_HOST_APPLY_CONFIRMED=yes
    PNM_ASSUME_YES=1
    PNM_DRY_RUN=0
    if pnm_host_apply_resources_step; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc"
    rm -rf -- "$temp_dir"
}

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
run_test 'host sandbox root requires apply gate' test_host_root_requires_apply_gate
run_test 'host resources require explicit confirmation before accounts' test_host_resources_require_explicit_confirmation_before_accounts
run_test 'host resources require fixed verified assets' test_host_resources_require_fixed_verified_assets
run_test 'host resources download fixed verified assets to a private cache' test_host_resources_download_fixed_assets_to_private_cache
run_test 'deployment root resource path is not directly reachable' test_deploy_root_resource_path_is_not_directly_reachable
finish_tests
