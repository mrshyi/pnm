#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"
# shellcheck source=../../lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=../../lib/output.sh
source "$PROJECT_ROOT/lib/output.sh"
# shellcheck source=../../lib/config.sh
source "$PROJECT_ROOT/lib/config.sh"
# shellcheck source=../../lib/lock.sh
source "$PROJECT_ROOT/lib/lock.sh"
# shellcheck source=../../lib/transaction.sh
source "$PROJECT_ROOT/lib/transaction.sh"
# shellcheck source=../../lib/node.sh
source "$PROJECT_ROOT/lib/node.sh"
# shellcheck source=../../lib/render.sh
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/tls.sh"
source "$PROJECT_ROOT/adapters/network.sh"
PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
NODE_SUITE_STATE="$(mktemp -d)"
export PNM_LOCK_FILE="$NODE_SUITE_STATE/lock" PNM_STATE_DIR="$NODE_SUITE_STATE/state"
trap 'rm -rf -- "$NODE_SUITE_STATE"' EXIT

# Link tests isolate URI selection; certificate SAN validation is covered by
# test_hy2_sni.sh and sandbox install tests use real generated certificates.
pnm_hysteria_tls_server_name() {
    local node_name="${1:?node config array required}"
    local -n node_ref="$node_name"
    printf '%s\n' "${node_ref[HY2_TLS_SERVER_NAME]}"
}
pnm_tls_certificate_sha256() { printf '%064d\n' 0; }

assert_sensitive_output_contains() { [[ "${1-}" == *"${2-}"* ]]; }
assert_sensitive_output_not_contains() { [[ "${1-}" != *"${2-}"* ]]; }
pnm_listener_present() { return 0; }
pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
pnm_systemd_active_state() { printf 'active\n'; }

test_validate_existing_node() {
    run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid" "$PROJECT_ROOT/bin/pnm" node validate
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'node.conf is valid' || return 1
    assert_contains "$RUN_OUTPUT" 'versions.conf is valid'
}

test_show_hides_secrets_and_exposes_node() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    declare -gA NODE=() REALITY=() HYSTERIA=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    PNM_HY2_CONFIG="$temp_dir/hysteria.yaml"
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || return 1
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || return 1
    pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$PNM_HY2_CONFIG" || return 1
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG" || return 1
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG" || return 1
    pnm_xray_config_runtime_values() { printf '443\texample.com:443\texample.com\ttcp\n'; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_show
    rm -rf -- "$temp_dir"
    if ((EUID != 0)); then
        assert_eq 77 "$RUN_RC" && assert_eq '' "$RUN_OUTPUT"
        return $?
    fi
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'PNM node' || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443' || return 1
    assert_contains "$RUN_OUTPUT" 'config=consistent' || return 1
    assert_contains "$RUN_OUTPUT" 'sni=example.com target=example.com:443' || return 1
    assert_not_contains "$RUN_OUTPUT" 'REDACTED_FIXTURE'
}

test_node_links_render_client_import_uris() {
    local temp_dir fake_xray runtime_config runtime_hy2_config old_xray_bin old_xray_config old_hy2_config old_config_dir
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$temp_dir/config/versions.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=front.example.com/;s/^XRAY_TARGET=.*/XRAY_TARGET=edge.example.net:8443/' "$temp_dir/config/node.conf"
    fake_xray="$temp_dir/xray"
    runtime_config="$temp_dir/xray-config.json"
    runtime_hy2_config="$temp_dir/hysteria-config.yaml"
    old_xray_bin="$PNM_XRAY_BIN"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"
    old_config_dir="$PNM_CONFIG_DIR"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\nHash32: ignored\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_BIN="$fake_xray"
    PNM_XRAY_CONFIG="$runtime_config"
    PNM_HY2_CONFIG="$runtime_hy2_config"
    declare -gA NODE=() REALITY=()
    declare -gA HYSTERIA=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || return 1
    pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_xray_config NODE REALITY >"$runtime_config" || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$runtime_hy2_config" || return 1
    pnm_test_record_applied_config xray "$runtime_config" || return 1
    pnm_test_record_applied_config hysteria2 "$runtime_hy2_config" || return 1
    PNM_OUTPUT_MODE=text
    pnm_require_root() { return 0; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_links --address 203.0.113.10
    PNM_XRAY_BIN="$old_xray_bin"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"
    PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://11111111-2222-4333-8444-555555555555@203.0.113.10:443' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '&sni=front.example.com&fp=chrome' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'hysteria2://abcdefghijklmnopqrstuvwxyz012345@203.0.113.10:8443/' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '?sni=proxy-frankfurt&insecure=1' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" "pinSHA256=$(printf '%064d' 0)" || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" '\\' || return 1
    assert_eq 'A%2FB%2BC%3D' "$(pnm_node_uri_encode 'A/B+C=')" || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'fixture-private'
}

test_node_links_omit_hy2_when_runtime_port_drifts() {
    local temp_dir runtime_config hy2_config fake_xray old_xray_bin old_xray_config old_hy2_config old_config_dir
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    runtime_config="$temp_dir/xray-config.json"; hy2_config="$temp_dir/hysteria-config.yaml"
    fake_xray="$temp_dir/xray"
    old_xray_bin="$PNM_XRAY_BIN"; old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"; old_config_dir="$PNM_CONFIG_DIR"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    PNM_CONFIG_DIR="$temp_dir/config"; PNM_XRAY_BIN="$fake_xray"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$runtime_config"; PNM_HY2_CONFIG="$hy2_config"
    declare -gA NODE=() REALITY=() HYSTERIA=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY && pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_xray_config NODE REALITY >"$runtime_config" || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$hy2_config" || return 1
    pnm_test_record_applied_config xray "$runtime_config" || return 1
    pnm_test_record_applied_config hysteria2 "$hy2_config" || return 1
    sed -i 's/^listen: :8443$/listen: :9443/' "$hy2_config"
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    PNM_XRAY_BIN="$old_xray_bin"; PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"; PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://11111111-2222-4333-8444-555555555555@203.0.113.10:443' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'hysteria2://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT$RUN_ERROR" 'Hysteria2 link omitted' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT$RUN_ERROR" 'listen'
}

test_node_links_omit_hy2_when_runtime_auth_drifts_without_leaking_password() {
    local temp_dir runtime_config hy2_config fake_xray old_xray_bin old_xray_config old_hy2_config old_config_dir rc
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    runtime_config="$temp_dir/xray-config.json"; hy2_config="$temp_dir/hysteria-config.yaml"
    fake_xray="$temp_dir/xray"
    old_xray_bin="$PNM_XRAY_BIN"; old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"; old_config_dir="$PNM_CONFIG_DIR"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    PNM_CONFIG_DIR="$temp_dir/config"; PNM_XRAY_BIN="$fake_xray"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$runtime_config"; PNM_HY2_CONFIG="$hy2_config"
    declare -gA NODE=() REALITY=() HYSTERIA=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY && pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_xray_config NODE REALITY >"$runtime_config" || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$hy2_config" || return 1
    pnm_test_record_applied_config xray "$runtime_config" || return 1
    pnm_test_record_applied_config hysteria2 "$hy2_config" || return 1
    sed -i 's/abcdefghijklmnopqrstuvwxyz012345/zyxwvutsrqponmlkjihgfedcba654321/' "$temp_dir/config/secrets/hysteria.env"
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    rc=$RUN_RC
    PNM_XRAY_BIN="$old_xray_bin"; PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"; PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$rc" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'hysteria2://' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" 'zyxwvutsrqponmlkjihgfedcba654321' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT$RUN_ERROR" 'Hysteria2 link omitted'
}

test_node_links_omit_hy2_for_damaged_runtime_config() {
    local temp_dir runtime_config hy2_config fake_xray old_xray_bin old_xray_config old_hy2_config old_config_dir
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    runtime_config="$temp_dir/xray-config.json"; hy2_config="$temp_dir/hysteria-config.yaml"
    fake_xray="$temp_dir/xray"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    old_xray_bin="$PNM_XRAY_BIN"; old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"; old_config_dir="$PNM_CONFIG_DIR"
    PNM_CONFIG_DIR="$temp_dir/config"; PNM_XRAY_BIN="$fake_xray"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$runtime_config"; PNM_HY2_CONFIG="$hy2_config"
    declare -gA NODE=() REALITY=() HYSTERIA=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY && pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_xray_config NODE REALITY >"$runtime_config" || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$hy2_config" || return 1
    pnm_test_record_applied_config xray "$runtime_config" || return 1
    pnm_test_record_applied_config hysteria2 "$hy2_config" || return 1
    printf 'not: valid: [\n' >"$hy2_config"
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    PNM_XRAY_BIN="$old_xray_bin"; PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"; PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'hysteria2://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT$RUN_ERROR" 'Hysteria2 link omitted'
}

pnm_test_prepare_hy2_runtime_config() {
    local temp_dir="${1:?temporary test directory required}"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_HY2_CONFIG="$temp_dir/runtime.yaml"
    declare -gA HY2_TEST_NODE=() HY2_TEST_SECRET=()
    pnm_load_node_config HY2_TEST_NODE && pnm_load_hysteria_secret HY2_TEST_SECRET || return 1
    pnm_render_hysteria_config HY2_TEST_NODE HY2_TEST_SECRET >"$PNM_HY2_CONFIG"
}

test_hy2_runtime_config_matches_rendered_config() {
    local temp_dir old_config_dir old_hy2_config
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT$RUN_ERROR"
}

test_hy2_runtime_config_ignores_line_ending_and_trailing_space_differences() {
    local temp_dir old_config_dir old_hy2_config
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    sed 's/'"'"'/"/g' "$PNM_HY2_CONFIG" | awk '{ sub(/[[:space:]]+$/, ""); printf "%s  \r\n", $0 }' >"$temp_dir/formatted.yaml"
    mv -- "$temp_dir/formatted.yaml" "$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT$RUN_ERROR"
}

test_hy2_runtime_config_reports_drift_without_values() {
    local temp_dir old_config_dir old_hy2_config rc
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    sed -i 's/^listen: :8443$/listen: :9443/' "$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    rc="$RUN_RC"
    if ((rc != 1)) || [[ "$PNM_HY2_CONFIG_DIAGNOSTIC" != *'listen'* || "$PNM_HY2_CONFIG_DIAGNOSTIC" == *'9443'* ]]; then
        PNM_CONFIG_DIR="$old_config_dir"
        PNM_HY2_CONFIG="$old_hy2_config"
        rm -rf -- "$temp_dir"
        return 1
    fi
    pnm_render_hysteria_config HY2_TEST_NODE HY2_TEST_SECRET >"$PNM_HY2_CONFIG" || return 1
    sed -i "s@^  password: .*@  password: 'RUNTIME-SECRET-MUST-NOT-LEAK'@" "$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 1 "$RUN_RC" || return 1
    assert_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'auth.password' || return 1
    assert_not_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'RUNTIME-SECRET-MUST-NOT-LEAK' || return 1
    assert_not_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_hy2_runtime_config_reports_missing_field() {
    local temp_dir old_config_dir old_hy2_config
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    sed -i '/^  password:/d' "$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 1 "$RUN_RC" || return 1
    assert_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'auth.password'
}

test_node_links_keep_partial_success_and_report_hy2_drift() {
    local temp_dir fake_xray old_config_dir old_hy2_config old_xray_config old_xray_bin old_output_mode
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_xray_bin="$PNM_XRAY_BIN"
    old_output_mode="$PNM_OUTPUT_MODE"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$PNM_CONFIG_DIR/secrets/reality.env"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    PNM_XRAY_BIN="$temp_dir/xray"
    fake_xray="$PNM_XRAY_BIN"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    declare -gA REALITY=()
    pnm_load_reality_secret REALITY || return 1
    pnm_render_xray_config HY2_TEST_NODE REALITY >"$PNM_XRAY_CONFIG" || return 1
    PNM_STATE_DIR="$temp_dir/state"
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG" || return 1
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG" || return 1
    sed -i "s@^  password: .*@  password: 'RUNTIME-SECRET-MUST-NOT-LEAK'@" "$PNM_HY2_CONFIG"
    pnm_xray_config_matches_node() { return 0; }
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'hysteria2://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'auth.password' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" 'RUNTIME-SECRET-MUST-NOT-LEAK' || return 1

    PNM_OUTPUT_MODE=json
    run_capture pnm_node_links --address 203.0.113.10
    source "$PROJECT_ROOT/lib/render.sh"
    PNM_OUTPUT_MODE="$old_output_mode"
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_XRAY_BIN="$old_xray_bin"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '"hysteria2":null' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '"hysteria2_status":"drift"' || return 1
    assert_sensitive_output_contains "$RUN_ERROR" 'auth.password' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" 'RUNTIME-SECRET-MUST-NOT-LEAK' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_hy2_runtime_config_classifies_malformed_and_missing_files() {
    local temp_dir old_config_dir old_hy2_config rc
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    printf 'auth: [broken\n' >"$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    rc="$RUN_RC"
    if ((rc != 78)) || [[ "$PNM_HY2_CONFIG_DIAGNOSTIC" != *'damaged'* ]]; then
        PNM_CONFIG_DIR="$old_config_dir"
        PNM_HY2_CONFIG="$old_hy2_config"
        rm -rf -- "$temp_dir"
        return 1
    fi
    printf '\n# no YAML mapping\n' >"$PNM_HY2_CONFIG"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    if ((RUN_RC != 78)) || [[ "$PNM_HY2_CONFIG_DIAGNOSTIC" != *'damaged'* ]]; then
        PNM_CONFIG_DIR="$old_config_dir"
        PNM_HY2_CONFIG="$old_hy2_config"
        rm -rf -- "$temp_dir"
        return 1
    fi
    PNM_HY2_CONFIG="$temp_dir/missing.yaml"
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 69 "$RUN_RC" || return 1
    assert_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'missing'
}

test_hy2_runtime_config_reports_permission_errors() {
    local temp_dir old_config_dir old_hy2_config
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    old_hy2_config="$PNM_HY2_CONFIG"
    pnm_test_prepare_hy2_runtime_config "$temp_dir" || return 1
    pnm_hysteria_config_parse_candidate() {
        local candidate="${1:?candidate config required}"
        local target_name="${2:?parsed field map required}"
        local -n parsed_fields_ref="$target_name"
        if [[ "$candidate" == "$PNM_HY2_CONFIG" ]]; then
            return "$PNM_EXIT_NOPERM"
        fi
        parsed_fields_ref=(
            [listen]=":${HY2_TEST_NODE[HY2_PORT]}"
            [tls.cert]="${HY2_TEST_SECRET[HY2_TLS_CERT_PATH]}"
            [tls.key]="${HY2_TEST_SECRET[HY2_TLS_KEY_PATH]}"
            [auth.type]=password
            [auth.password]="${HY2_TEST_SECRET[HY2_AUTH_PASSWORD]}"
            [masquerade.type]=proxy
            [masquerade.proxy.url]="https://${HY2_TEST_NODE[XRAY_SERVER_NAME]}"
        )
    }
    run_capture pnm_hysteria_config_matches_node HY2_TEST_NODE HY2_TEST_SECRET
    source "$PROJECT_ROOT/lib/render.sh"
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 77 "$RUN_RC" || return 1
    assert_contains "$PNM_HY2_CONFIG_DIAGNOSTIC" 'permissions'
}

test_node_validation_rejects_single_label_reality_sni() {
    local -A node_config=()
    pnm_load_node_config node_config || return 1
    node_config[XRAY_SERVER_NAME]=proxy-frankfurt
    ! pnm_validate_node_config node_config
}

test_node_links_refuse_single_label_reality_sni() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/node.conf"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=proxy-frankfurt/' "$temp_dir/node.conf"
    PNM_CONFIG_DIR="$temp_dir"
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    rm -rf -- "$temp_dir"
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_ERROR" 'do not use the VPS hostname'
}

test_node_show_reports_invalid_reality_sni() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$temp_dir/versions.conf"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=proxy-frankfurt/' "$temp_dir/node.conf"
    run_capture env PNM_CONFIG_DIR="$temp_dir" "$PROJECT_ROOT/bin/pnm" node show
    rm -rf -- "$temp_dir"
    if ((EUID != 0)); then
        assert_eq 77 "$RUN_RC" && assert_eq '' "$RUN_OUTPUT"
        return $?
    fi
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443 -> proxy-frankfurt' || return 1
    assert_contains "$RUN_OUTPUT" 'do not use the VPS hostname'
}

test_node_show_reports_runtime_drift_without_secrets() {
    local temp_dir rc old_output_mode
    temp_dir="$(mktemp -d)"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    printf '{"inbounds":[]}\n' >"$PNM_XRAY_CONFIG"
    pnm_xray_config_runtime_values() { printf '443\twww.cloudflare.com:443\twww.cloudflare.com\ttcp\n'; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_show
    rc=$RUN_RC
    if ((EUID != 0)); then
        rm -rf -- "$temp_dir"
        assert_eq 77 "$rc" && assert_eq '' "$RUN_OUTPUT"
        return $?
    fi
    assert_eq 78 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443 -> example.com (example.com:443)' || return 1
    assert_contains "$RUN_OUTPUT" 'service=active config=drift applied=unknown link=drift' || return 1
    assert_contains "$RUN_OUTPUT" 'port=443 sni=www.cloudflare.com target=www.cloudflare.com:443' || return 1
    assert_contains "$RUN_ERROR" 'differs from the runtime Xray configuration' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" '11111111-2222-4333-8444-555555555555'

    old_output_mode="$PNM_OUTPUT_MODE"
    PNM_OUTPUT_MODE=json
    run_capture pnm_node_show
    PNM_OUTPUT_MODE="$old_output_mode"
    rm -rf -- "$temp_dir"
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '{"schema":"pnm.node.v1"' || return 1
    assert_contains "$RUN_OUTPUT" '"configuration_consistency":"drift"' || return 1
    assert_contains "$RUN_ERROR" 'drift fields:' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" '11111111-2222-4333-8444-555555555555'
}

test_node_init_does_not_migrate_existing_microsoft_config() {
    local temp_dir original rc
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$temp_dir/config/versions.conf"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=www.microsoft.com/;s/^XRAY_TARGET=.*/XRAY_TARGET=www.microsoft.com:443/' "$temp_dir/config/node.conf"
    original="$(<"$temp_dir/config/node.conf")"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    pnm_require_root() { return 0; }
    if pnm_node_init 0 --force; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$original" "$(<"$temp_dir/config/node.conf")" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_node_links_refuse_runtime_configuration_drift() {
    local temp_dir runtime_config rc old_xray_config
    temp_dir="$(mktemp -d)"
    runtime_config="$temp_dir/runtime.json"
    printf '{"inbounds":[]}\n' >"$runtime_config"
    old_xray_config="$PNM_XRAY_CONFIG"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$runtime_config"
    pnm_require_root() { return 0; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_links --address 203.0.113.10
    rc=$RUN_RC
    PNM_XRAY_CONFIG="$old_xray_config"
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT$RUN_ERROR" 'Xray link omitted: runtime configuration differs from node.conf' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT" 'vless://'
}

test_core_link_statuses_are_independent_and_require_applied_evidence() {
    local temp_dir status old_state old_xray_config old_hy2_config old_config_dir
    temp_dir="$(mktemp -d)"
    old_state="$PNM_STATE_DIR"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"
    old_config_dir="$PNM_CONFIG_DIR"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$temp_dir/xray.json"
    PNM_HY2_CONFIG="$temp_dir/hysteria.yaml"
    declare -gA NODE=() REALITY=() HYSTERIA=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY && pnm_load_hysteria_secret HYSTERIA || return 1
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || return 1
    pnm_render_hysteria_config NODE HYSTERIA >"$PNM_HY2_CONFIG" || return 1
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG" || return 1
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG" || return 1
    pnm_systemd_active_state() { printf '%s\n' "${PNM_TEST_ACTIVE_STATE[${1-}]-unknown}"; }
    declare -gA PNM_TEST_ACTIVE_STATE=([xray.service]=active [hysteria-server.service]=active)

    status="$(pnm_node_core_link_status xray NODE REALITY)" || return 1
    assert_contains "$status" 'ready|active|consistent|confirmed|' || return 1
    status="$(pnm_node_core_link_status hysteria2 NODE HYSTERIA)" || return 1
    assert_contains "$status" 'ready|active|consistent|confirmed|' || return 1

    PNM_TEST_ACTIVE_STATE[xray.service]=inactive
    status="$(pnm_node_core_link_status xray NODE REALITY)" || return 1
    assert_contains "$status" 'inactive|inactive|' || return 1
    status="$(pnm_node_core_link_status hysteria2 NODE HYSTERIA)" || return 1
    assert_contains "$status" 'ready|' || return 1

    PNM_TEST_ACTIVE_STATE[xray.service]=active
    PNM_TEST_ACTIVE_STATE[hysteria-server.service]=inactive
    status="$(pnm_node_core_link_status hysteria2 NODE HYSTERIA)" || return 1
    assert_contains "$status" 'inactive|inactive|' || return 1
    status="$(pnm_node_core_link_status xray NODE REALITY)" || return 1
    assert_contains "$status" 'ready|' || return 1

    PNM_TEST_ACTIVE_STATE[hysteria-server.service]=active
    sed -i 's/^listen: :8443$/listen: :9443/' "$PNM_HY2_CONFIG"
    status="$(pnm_node_core_link_status hysteria2 NODE HYSTERIA)" || return 1
    assert_contains "$status" 'drift|active|drift|' || return 1
    assert_not_contains "$status" "${HYSTERIA[HY2_AUTH_PASSWORD]}" || return 1

    pnm_listener_present() { return 1; }
    status="$(pnm_node_core_link_status xray NODE REALITY)" || return 1
    assert_contains "$status" 'unavailable|active|consistent|confirmed|expected local TCP/' || return 1
    pnm_listener_present() { return 0; }

    rm -f -- "$PNM_STATE_DIR/cores/xray/applied.env"
    status="$(pnm_node_core_link_status xray NODE REALITY)" || return 1
    assert_contains "$status" 'unknown|active|consistent|unknown|' || return 1
    PNM_STATE_DIR="$old_state"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"
    PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
}

test_xray_config_semantic_match_ignores_json_formatting() {
    local temp_dir old_config
    temp_dir="$(mktemp -d)"
    old_config="$PNM_XRAY_CONFIG"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || { rm -rf -- "$temp_dir"; return 1; }
    python3 - "$PNM_XRAY_CONFIG" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
with open(path, "w", encoding="utf-8") as destination:
    json.dump(config, destination, sort_keys=True, indent=4)
PY
    run_capture pnm_xray_config_matches_node NODE REALITY
    PNM_XRAY_CONFIG="$old_config"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT"
}

test_historical_release_runtime_config_matches_current_template() {
    local old_config
    old_config="$PNM_XRAY_CONFIG"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$TEST_ROOT/fixtures/xray-runtime-v0.16.0-rc.1.json"
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || return 1
    run_capture pnm_xray_config_matches_node NODE REALITY
    PNM_XRAY_CONFIG="$old_config"
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT$RUN_ERROR"
}

test_xray_log_subfields_and_reality_show_are_strict_and_report_json_paths() {
    local temp_dir old_config rc old_output_mode
    temp_dir="$(mktemp -d)"
    old_config="$PNM_XRAY_CONFIG"
    old_output_mode="$PNM_OUTPUT_MODE"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    PNM_OUTPUT_MODE=text
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || { rm -rf -- "$temp_dir"; return 1; }
    cp -- "$TEST_ROOT/fixtures/xray-runtime-v0.16.0-rc.1.json" "$PNM_XRAY_CONFIG"
    python3 - "$PNM_XRAY_CONFIG" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
config["log"]["loglevel"] = "debug"
with open(path, "w", encoding="utf-8") as destination:
    json.dump(config, destination)
PY
    run_capture pnm_xray_config_matches_node NODE REALITY
    rc="$RUN_RC"
    if ((rc != 1)) || [[ -n "$RUN_OUTPUT" || "$RUN_ERROR" != *'$.log.loglevel'* || "$RUN_ERROR" == *debug* ]]; then
        PNM_XRAY_CONFIG="$old_config"
        PNM_OUTPUT_MODE="$old_output_mode"
        rm -rf -- "$temp_dir"
        return 1
    fi

    cp -- "$TEST_ROOT/fixtures/xray-runtime-v0.16.0-rc.1.json" "$PNM_XRAY_CONFIG"
    python3 - "$PNM_XRAY_CONFIG" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
config["inbounds"][0]["streamSettings"]["realitySettings"]["show"] = True
with open(path, "w", encoding="utf-8") as destination:
    json.dump(config, destination)
PY
    run_capture pnm_xray_config_matches_node NODE REALITY
    rc="$RUN_RC"
    PNM_XRAY_CONFIG="$old_config"
    PNM_OUTPUT_MODE="$old_output_mode"
    rm -rf -- "$temp_dir"
    assert_eq 1 "$rc" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    assert_contains "$RUN_ERROR" '$.inbounds[0].streamSettings.realitySettings.show' || return 1
    assert_not_contains "$RUN_ERROR" 'true'
}

test_xray_drift_diagnostic_lists_field_names_without_values() {
    local temp_dir old_config rc
    temp_dir="$(mktemp -d)"
    old_config="$PNM_XRAY_CONFIG"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || { rm -rf -- "$temp_dir"; return 1; }
    python3 - "$PNM_XRAY_CONFIG" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
config["inbounds"][0]["streamSettings"]["realitySettings"]["dest"] = "different.example:443"
config["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"] = "DO-NOT-PRINT-PRIVATE-KEY"
config["inbounds"][0]["settings"]["clients"][0]["id"] = "DO-NOT-PRINT-UUID"
with open(path, "w", encoding="utf-8") as destination:
    json.dump(config, destination)
PY
    run_capture pnm_xray_config_matches_node NODE REALITY
    rc="$RUN_RC"
    PNM_XRAY_CONFIG="$old_config"
    rm -rf -- "$temp_dir"
    assert_eq 1 "$rc" || return 1
    assert_contains "$RUN_OUTPUT$RUN_ERROR" 'drift fields:' || return 1
    assert_contains "$RUN_OUTPUT$RUN_ERROR" 'realitySettings.dest' || return 1
    assert_contains "$RUN_OUTPUT$RUN_ERROR" 'realitySettings.privateKey' || return 1
    assert_contains "$RUN_OUTPUT$RUN_ERROR" 'clients[0].id' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'different.example' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'DO-NOT-PRINT-PRIVATE-KEY' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'DO-NOT-PRINT-UUID' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" '11111111-2222-4333-8444-555555555555' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'fixture-private'
}

test_xray_drift_diagnostic_redacts_unknown_field_names() {
    local temp_dir old_config rc
    temp_dir="$(mktemp -d)"
    old_config="$PNM_XRAY_CONFIG"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || { rm -rf -- "$temp_dir"; return 1; }
    python3 - "$PNM_XRAY_CONFIG" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
config["inbounds"][0]["settings"]["fixture-secret-as-key-DO-NOT-PRINT"] = True
with open(path, "w", encoding="utf-8") as destination:
    json.dump(config, destination)
PY
    run_capture pnm_xray_config_matches_node NODE REALITY
    rc="$RUN_RC"
    PNM_XRAY_CONFIG="$old_config"
    rm -rf -- "$temp_dir"
    assert_eq 1 "$rc" || return 1
    assert_contains "$RUN_OUTPUT$RUN_ERROR" 'settings.<field>' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'fixture-secret-as-key-DO-NOT-PRINT'
}

test_invalid_node_is_rejected() {
    run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-invalid" "$PROJECT_ROOT/bin/pnm" node validate
    assert_eq 78 "$RUN_RC"
}

test_release_metadata_parsers() {
    local temp_dir release_file xray_digest hysteria_digest
    temp_dir="$(mktemp -d)"
    release_file="$temp_dir/release.json"
    xray_digest="$temp_dir/xray.dgst"
    hysteria_digest="$temp_dir/hashes.txt"

    printf '{"tag_name":"v1.2.3","prerelease":false}\n' >"$release_file"
    printf 'SHA-256= AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' >"$xray_digest"
    printf 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB  build/hysteria-linux-amd64\n' >"$hysteria_digest"

    assert_eq 'v1.2.3' "$(pnm_node_parse_release_tag "$release_file")" || return 1
    assert_eq 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        "$(pnm_node_parse_xray_sha256 "$xray_digest")" || return 1
    assert_eq 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
        "$(pnm_node_parse_hysteria_sha256 "$hysteria_digest")" || return 1
    rm -rf -- "$temp_dir"
}

test_latest_version_lookup_persists_concrete_values() {
    local lookup_rc

    pnm_node_fetch_url() {
        local url="${1:?URL required}"
        local destination="${2:?destination required}"

        case "$url" in
            *api.github.com/repos/XTLS/Xray-core/releases/*)
                printf '{"tag_name":"v9.8.7"}\n' >"$destination"
                ;;
            *Xray-linux-64.zip.dgst)
                printf 'SHA2-256= cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\n' >"$destination"
                ;;
            *api.github.com/repos/apernet/hysteria/releases/*)
                printf '{"tag_name":"app/v8.7.6"}\n' >"$destination"
                ;;
            *hashes.txt)
                printf 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd  build/hysteria-linux-amd64\n' >"$destination"
                ;;
            *)
                return 1
                ;;
        esac
    }

    if pnm_node_fetch_latest_versions; then
        lookup_rc=0
    else
        lookup_rc=$?
    fi
    pnm_cleanup
    [[ "$lookup_rc" == 0 ]] || return 1
    assert_eq v9.8.7 "${PNM_NODE_LATEST_VERSIONS[XRAY_VERSION]}" || return 1
    assert_eq cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
        "${PNM_NODE_LATEST_VERSIONS[XRAY_SHA256]}" || return 1
    assert_eq v8.7.6 "${PNM_NODE_LATEST_VERSIONS[HY2_VERSION]}" || return 1
    assert_eq dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
        "${PNM_NODE_LATEST_VERSIONS[HY2_SHA256]}" || return 1
}

test_init_writes_valid_files_transactionally() {
    local temp_dir rc
    local -A node_config=() versions_config=()
    temp_dir="$(mktemp -d)"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='tx-node-test'
    PNM_DRY_RUN=0
    pnm_require_root() { return 0; }
    pnm_lock_acquire() { PNM_LOCK_DEPTH=1; PNM_LOCK_MODE=exclusive; }
    pnm_lock_release() { PNM_LOCK_DEPTH=0; PNM_LOCK_MODE=''; }
    if [[ "$(uname -s)" != Linux ]]; then
        rm -rf -- "$temp_dir"
        return 0
    fi
    if pnm_node_init 0 \
        --address 203.0.113.10 \
        --xray-version v1.8.24 --xray-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        --hy2-version v2.6.3 --hy2-sha256 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
        rc=0
    else
        rc=$?
    fi
    if [[ "$rc" != 0 ]]; then
        return 1
    fi
    [[ "$(stat -c '%a' "$PNM_CONFIG_DIR/node.conf")" == 600 ]] || return 1
    [[ "$(stat -c '%a' "$PNM_CONFIG_DIR/versions.conf")" == 600 ]] || return 1
    pnm_load_node_config node_config && pnm_validate_node_config node_config || return 1
    pnm_load_versions_config versions_config && pnm_validate_versions_config versions_config
    rc=$?
    [[ "${node_config[NODE_REGION]}" == vps ]] || return 1
    [[ "${node_config[NODE_ADDRESS]}" == 203.0.113.10 ]] || return 1
    [[ "${node_config[TIMEZONE]}" == UTC ]] || return 1
    [[ "${node_config[XRAY_SERVER_NAME]}" == www.cloudflare.com ]] || return 1
    [[ "${node_config[XRAY_TARGET]}" == www.cloudflare.com:443 ]] || return 1
    [[ "${node_config[XRAY_PORT]}" == 443 && "${node_config[HY2_PORT]}" == 8443 ]] || return 1
    [[ "${node_config[HY2_TLS_MODE]}" == selfsigned-pin ]] || return 1
    [[ "${node_config[HY2_TLS_SERVER_NAME]}" == proxy-vps ]] || return 1
    rm -rf -- "$temp_dir"
    return "$rc"
}

test_node_links_preserve_xray_when_hy2_fingerprint_fails() (
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_OUTPUT_MODE=json
    pnm_require_root() { return 0; }
    pnm_node_core_link_status() { printf 'ready|active|consistent|applied|fixture\n'; }
    pnm_node_xray_reality_public_key() { printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'; }
    pnm_tls_certificate_sha256() { return "$PNM_EXIT_CONFIG"; }
    run_capture pnm_node_links_unlocked --address 203.0.113.10
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '"hysteria2":null' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '"hysteria2_status":"unknown"' || return 1
    assert_contains "$RUN_ERROR" 'fingerprint' || return 1
    assert_sensitive_output_not_contains "$RUN_OUTPUT$RUN_ERROR" 'abcdefghijklmnopqrstuvwxyz012345'
)

run_test 'node links preserve ready Xray when HY2 certificate fingerprint fails' test_node_links_preserve_xray_when_hy2_fingerprint_fails
run_test 'node validation accepts a complete configuration' test_validate_existing_node
run_test 'node show reports only non-secret desired state' test_show_hides_secrets_and_exposes_node
run_test 'node links render client import URIs without private keys' test_node_links_render_client_import_uris
run_test 'node links omit HY2 URI but retain REALITY URI on HY2 port drift' test_node_links_omit_hy2_when_runtime_port_drifts
run_test 'node links omit HY2 URI without exposing credentials on auth drift' test_node_links_omit_hy2_when_runtime_auth_drifts_without_leaking_password
run_test 'node links omit HY2 URI for malformed runtime config while retaining REALITY' test_node_links_omit_hy2_for_damaged_runtime_config
run_test 'HY2 runtime config matches the PNM rendered config' test_hy2_runtime_config_matches_rendered_config
run_test 'HY2 runtime config ignores CRLF and trailing whitespace' test_hy2_runtime_config_ignores_line_ending_and_trailing_space_differences
run_test 'HY2 runtime config reports only drift field names' test_hy2_runtime_config_reports_drift_without_values
run_test 'HY2 runtime config reports missing fields' test_hy2_runtime_config_reports_missing_field
run_test 'HY2 runtime config distinguishes damaged from missing files' test_hy2_runtime_config_classifies_malformed_and_missing_files
run_test 'HY2 runtime config reports permission errors separately' test_hy2_runtime_config_reports_permission_errors
run_test 'node links keep exit-zero partial success and diagnose HY2 drift' test_node_links_keep_partial_success_and_report_hy2_drift
run_test 'node validation rejects a single-label REALITY SNI' test_node_validation_rejects_single_label_reality_sni
run_test 'node links refuse a VPS hostname as REALITY SNI' test_node_links_refuse_single_label_reality_sni
run_test 'node show reports an invalid REALITY SNI for diagnosis' test_node_show_reports_invalid_reality_sni
run_test 'node show reports runtime drift without exposing credentials' test_node_show_reports_runtime_drift_without_secrets
run_test 'new defaults do not migrate an existing Microsoft node' test_node_init_does_not_migrate_existing_microsoft_config
run_test 'node links refuse to emit credentials when runtime Xray config has drifted' test_node_links_refuse_runtime_configuration_drift
run_test 'Core link status checks are independent and require applied evidence' test_core_link_statuses_are_independent_and_require_applied_evidence
run_test 'Xray runtime comparison ignores JSON formatting differences' test_xray_config_semantic_match_ignores_json_formatting
run_test 'historical v0.16.0-rc.1 runtime config matches the current render template' test_historical_release_runtime_config_matches_current_template
run_test 'Xray log subfields and REALITY show drift are strict and use stderr JSON paths' test_xray_log_subfields_and_reality_show_are_strict_and_report_json_paths
run_test 'Xray drift diagnostic lists field paths without values or secrets' test_xray_drift_diagnostic_lists_field_names_without_values
run_test 'Xray drift diagnostics redact unrecognized JSON field names' test_xray_drift_diagnostic_redacts_unknown_field_names
run_test 'node validation rejects invalid values' test_invalid_node_is_rejected
run_test 'latest release metadata parsers return pinned values' test_release_metadata_parsers
run_test 'latest lookup returns concrete pinned versions and hashes' test_latest_version_lookup_persists_concrete_values
run_test 'node init writes both validated files in one transaction' test_init_writes_valid_files_transactionally
finish_tests
