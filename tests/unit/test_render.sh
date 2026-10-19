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
    python3 -c 'import json,sys; d=json.load(sys.stdin); inbound=d["inbounds"][0]; stream=inbound["streamSettings"]; assert inbound["port"] == 443; assert inbound["settings"]["clients"][0]["flow"] == "xtls-rprx-vision"; assert stream["network"] == "tcp"; assert stream["security"] == "reality"; assert stream["realitySettings"]["serverNames"] == ["example.com"]' <<<"$output"
}

test_xray_renderer_keeps_reality_target_and_sni_independent() {
    local output
    load_render_fixtures || return 1
    NODE[XRAY_SERVER_NAME]='front.example.com'
    NODE[XRAY_TARGET]='edge.example.net:8443'
    output="$(pnm_render_xray_config NODE REALITY)" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); reality=d["inbounds"][0]["streamSettings"]["realitySettings"]; assert reality["serverNames"] == ["front.example.com"]; assert reality["dest"] == "edge.example.net:8443"' <<<"$output"
}

test_runtime_xray_config_exposes_only_public_reality_values() {
    local temp_dir runtime_values
    temp_dir="$(mktemp -d)"
    load_render_fixtures || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_xray_config NODE REALITY >"$temp_dir/runtime.json" || { rm -rf -- "$temp_dir"; return 1; }
    runtime_values="$(pnm_xray_config_runtime_values "$temp_dir/runtime.json")" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq $'443\texample.com:443\texample.com\ttcp' "$runtime_values" || return 1
    assert_not_contains "$runtime_values" "${REALITY[XRAY_REALITY_PRIVATE_KEY]}"
}

test_reality_short_id_requires_even_hex_length() {
    local -A reality=()
    pnm_load_reality_secret reality || return 1
    reality[XRAY_REALITY_SHORT_ID]=123
    ! pnm_validate_reality_secret_config reality
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
run_test 'Xray renderer keeps REALITY target and SNI independent' test_xray_renderer_keeps_reality_target_and_sni_independent
run_test 'runtime Xray parser exposes public REALITY values only' test_runtime_xray_config_exposes_only_public_reality_values
run_test 'REALITY Short ID rejects odd hex length' test_reality_short_id_requires_even_hex_length
run_test 'Hysteria renderer keeps TLS verification enabled' test_hysteria_render_does_not_disable_tls_verification
run_test 'rendered files are atomically written with mode 600' test_render_write_is_atomic_mode_600
finish_tests
