#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../adapters/assets.sh
source "$PNM_ADAPTER_DIR/assets.sh"
# shellcheck source=../../lib/assets.sh
source "$PNM_LIB_DIR/assets.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_asset_urls_are_pinned_by_core_and_version() {
    assert_eq 'https://github.com/XTLS/Xray-core/releases/download/v1.2.3/Xray-linux-64.zip' "$(pnm_asset_url xray v1.2.3)" || return 1
    assert_eq 'https://github.com/apernet/hysteria/releases/download/app%2Fv2.3.4/hysteria-linux-amd64' "$(pnm_asset_url hysteria2 v2.3.4)"
}

test_asset_hash_verification() {
    local temp_dir asset digest rc
    temp_dir="$(mktemp -d)"
    asset="$temp_dir/asset"
    printf 'verified payload' >"$asset"
    digest="$(sha256sum "$asset" | awk '{print $1}')"
    pnm_asset_verify_file "$asset" "$digest" || return 1
    if pnm_asset_verify_file "$asset" "${digest/a/b}"; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 1 "$rc"
}

test_assets_json_has_no_secrets() {
    local old_config="$PNM_CONFIG_DIR"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    pnm_assets_load || return 1
    PNM_OUTPUT_MODE=json
    run_capture pnm_assets
    PNM_OUTPUT_MODE=text
    PNM_CONFIG_DIR="$old_config"
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"] == "pnm.assets.v1"; assert len(d["assets"]) == 2' <<<"$RUN_OUTPUT"
    assert_not_contains "$RUN_OUTPUT" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_verified_download_atomically_installs_payload() {
    local temp_dir fakebin destination digest rc
    temp_dir="$(mktemp -d)"
    fakebin="$temp_dir/bin"
    destination="$temp_dir/payload"
    mkdir -m 0700 -- "$fakebin"
    printf '%s\n' '#!/usr/bin/env bash' 'target=' 'while (($# > 0)); do' '  if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi' 'done' 'printf "verified payload" >"$target"' >"$fakebin/curl"
    chmod 0700 -- "$fakebin/curl"
    digest="$(printf 'verified payload' | sha256sum | awk '{print $1}')"
    if PATH="$fakebin:$PATH" pnm_asset_download_verified xray v1.2.3 "$digest" "$destination"; then rc=0; else rc=$?; fi
    [[ "$rc" == 0 && -f "$destination" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(<"$destination")" == 'verified payload' ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

run_test 'asset URLs are fixed by Core and version' test_asset_urls_are_pinned_by_core_and_version
run_test 'asset SHA-256 verification fails closed' test_asset_hash_verification
run_test 'assets output is JSON and excludes Secret values' test_assets_json_has_no_secrets
run_test 'verified download atomically installs the payload' test_verified_download_atomically_installs_payload
finish_tests
