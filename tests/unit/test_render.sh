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

PNM_TEST_INVOCATION_ID=0123456789abcdef0123456789abcdef
pnm_systemd_show_value() { printf '%s\n' "$PNM_TEST_INVOCATION_ID"; }

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
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
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

test_hysteria_candidate_validation_accepts_only_rendered_yaml() {
    local temp_dir candidate
    temp_dir="$(mktemp -d)"
    candidate="$temp_dir/hysteria.yaml"
    load_render_fixtures || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_hysteria_config NODE HYSTERIA >"$candidate" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_hysteria_config_validate_candidate "$candidate" NODE HYSTERIA || { rm -rf -- "$temp_dir"; return 1; }
    printf 'invalid: [\n' >"$candidate"
    if pnm_hysteria_config_validate_candidate "$candidate" NODE HYSTERIA; then
        rm -rf -- "$temp_dir"
        return 1
    fi
    rm -rf -- "$temp_dir"
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

test_applied_config_record_distinguishes_unknown_confirmed_and_changed() {
    local temp_dir config status
    local -A applied=()
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    config="$temp_dir/config.yaml"
    printf 'listen: :8443\n' >"$config"

    status="$(pnm_core_applied_config_status hysteria2 "$config")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq unknown "$status" || { rm -rf -- "$temp_dir"; return 1; }
    mkdir -p -- "$PNM_STATE_DIR/cores/hysteria2"
    printf 'SCHEMA_VERSION=1\nCORE=hysteria2\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=%s\n' \
        "$(sha256sum -- "$config" | awk '{print $1}')" "$PNM_TEST_INVOCATION_ID" >"$PNM_STATE_DIR/cores/hysteria2/applied.env"
    chmod 0600 -- "$PNM_STATE_DIR/cores/hysteria2/applied.env"
    status="$(pnm_core_applied_config_status hysteria2 "$config")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq confirmed "$status" || { rm -rf -- "$temp_dir"; return 1; }

    PNM_TEST_INVOCATION_ID=ffffffffffffffffffffffffffffffff
    status="$(pnm_core_applied_config_status hysteria2 "$config")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq changed "$status" || { rm -rf -- "$temp_dir"; return 1; }
    PNM_TEST_INVOCATION_ID=0123456789abcdef0123456789abcdef

    printf 'listen: :9443\n' >"$config"
    status="$(pnm_core_applied_config_status hysteria2 "$config")" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq changed "$status"
}

run_test 'Xray renderer produces valid JSON' test_xray_render_is_valid_json
run_test 'Xray renderer keeps REALITY target and SNI independent' test_xray_renderer_keeps_reality_target_and_sni_independent
run_test 'runtime Xray parser exposes public REALITY values only' test_runtime_xray_config_exposes_only_public_reality_values
run_test 'REALITY Short ID rejects odd hex length' test_reality_short_id_requires_even_hex_length
run_test 'Hysteria renderer keeps TLS verification enabled' test_hysteria_render_does_not_disable_tls_verification
run_test 'Hysteria candidate validation rejects non-rendered or damaged YAML' test_hysteria_candidate_validation_accepts_only_rendered_yaml
run_test 'rendered files are atomically written with mode 600' test_render_write_is_atomic_mode_600
run_test 'applied configuration evidence distinguishes unknown and changed state' test_applied_config_record_distinguishes_unknown_confirmed_and_changed
finish_tests
