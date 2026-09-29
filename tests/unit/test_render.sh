#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/render.sh
source "$PNM_LIB_DIR/render.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

load_render_fixtures() {
    declare -gA NODE=() REALITY=() HYSTERIA=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    pnm_load_node_config NODE
    pnm_load_reality_secret REALITY
    pnm_load_hysteria_secret HYSTERIA
    pnm_render_validate_inputs NODE REALITY HYSTERIA
}

test_xray_render_is_valid_json() {
    local output
    load_render_fixtures || return 1
    output="$(pnm_render_xray_config NODE REALITY)" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["inbounds"][0]["port"] == 443; assert d["inbounds"][0]["streamSettings"]["security"] == "reality"' <<<"$output"
}

test_hysteria_render_does_not_disable_tls_verification() {
    local output
    load_render_fixtures || return 1
    output="$(pnm_render_hysteria_config NODE HYSTERIA)" || return 1
    assert_contains "$output" 'listen: :8443' && assert_contains "$output" 'type: password' && assert_not_contains "$output" 'insecure:'
}

test_render_write_is_atomic_mode_600() {
    local temp_dir destination mode
    temp_dir="$(mktemp -d)"
    destination="$temp_dir/config.json"
    load_render_fixtures || return 1
    pnm_render_write_file pnm_render_xray_config "$destination" NODE REALITY || return 1
    mode="$(stat -c '%a' "$destination")"
    rm -rf -- "$temp_dir"
    assert_eq 600 "$mode"
}

run_test 'Xray renderer produces valid JSON' test_xray_render_is_valid_json
run_test 'Hysteria renderer keeps TLS verification enabled' test_hysteria_render_does_not_disable_tls_verification
run_test 'rendered files are atomically written with mode 600' test_render_write_is_atomic_mode_600
finish_tests
