#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
source "$PNM_LIB_DIR/common.sh"
source "$PNM_LIB_DIR/output.sh"
source "$PNM_LIB_DIR/config.sh"
source "$PNM_LIB_DIR/lock.sh"
source "$PNM_LIB_DIR/transaction.sh"
source "$PNM_LIB_DIR/tls.sh"
source "$PNM_LIB_DIR/render.sh"
source "$PNM_LIB_DIR/node.sh"
source "$TEST_ROOT/testlib.sh"
HY2_SUITE_STATE="$(mktemp -d)"
export PNM_LOCK_FILE="$HY2_SUITE_STATE/lock" PNM_STATE_DIR="$HY2_SUITE_STATE/state"
trap 'rm -rf -- "$HY2_SUITE_STATE"' EXIT

make_test_certificate() {
    local directory="${1:?directory required}"
    local san="${2:?SAN required}"
    local common_name="${san#DNS:}" key_path="$directory/server.key" cert_path="$directory/server.crt"
    common_name="${common_name%%,*}"
    if command -v cygpath >/dev/null 2>&1; then
        key_path="$(cygpath -w "$key_path")"
        cert_path="$(cygpath -w "$cert_path")"
        MSYS_NO_PATHCONV=1 openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
            -days 2 -subj "/CN=$common_name" -addext "subjectAltName=$san" \
            -keyout "$key_path" -out "$cert_path" >/dev/null 2>&1
    else
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
            -days 2 -subj "/CN=$common_name" -addext "subjectAltName=$san" \
            -keyout "$key_path" -out "$cert_path" >/dev/null 2>&1
    fi
}

test_hy2_tls_sni_is_independent_and_matches_certificate_san() {
    local temp_dir server_name
    local -A node_cfg=() hysteria_cfg=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:proxy-frankfurt' || { rm -rf -- "$temp_dir"; return 1; }
    node_cfg=(
        [HY2_TLS_MODE]=selfsigned-pin [HY2_TLS_SERVER_NAME]=proxy-frankfurt
        [NODE_ADDRESS]=203.0.113.10 [XRAY_SERVER_NAME]=www.cloudflare.com
    )
    hysteria_cfg=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt")
    server_name="$(pnm_hysteria_tls_server_name node_cfg hysteria_cfg)" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq proxy-frankfurt "$server_name" || return 1
    assert_eq www.cloudflare.com "${node_cfg[XRAY_SERVER_NAME]}"
}

test_node_links_use_certificate_san_without_changing_reality_sni_or_pin() {
    local temp_dir cert server_key pin fake_xray expected_pin secret_before secret_after
    local old_config_dir old_xray_config old_hy2_config old_xray_bin
    local -A node_cfg=() reality_cfg=() hysteria_cfg=()
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=www.cloudflare.com/;s/^XRAY_TARGET=.*/XRAY_TARGET=www.cloudflare.com:443/' "$temp_dir/config/node.conf"
    cert="$temp_dir/server.crt"
    server_key="$temp_dir/server.key"
    make_test_certificate "$temp_dir" 'DNS:proxy-frankfurt' || { rm -rf -- "$temp_dir"; return 1; }
    pin="$(pnm_tls_spki_pin "$cert")" || { rm -rf -- "$temp_dir"; return 1; }
    sed -i "s#^HY2_TLS_CERT_PATH=.*#HY2_TLS_CERT_PATH=$cert#;s#^HY2_TLS_KEY_PATH=.*#HY2_TLS_KEY_PATH=$server_key#;s#^HY2_TLS_PIN_SHA256=.*#HY2_TLS_PIN_SHA256=$pin#" \
        "$temp_dir/config/secrets/hysteria.env"
    fake_xray="$temp_dir/xray"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Password (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    old_config_dir="$PNM_CONFIG_DIR"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"
    old_xray_bin="$PNM_XRAY_BIN"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_XRAY_CONFIG="$temp_dir/xray.json"
    PNM_HY2_CONFIG="$temp_dir/hysteria.yaml"
    PNM_XRAY_BIN="$fake_xray"
    if ! pnm_load_node_config node_cfg || ! pnm_load_reality_secret reality_cfg || ! pnm_load_hysteria_secret hysteria_cfg; then
        printf 'test fixture configuration could not be loaded\n' >&2
        rm -rf -- "$temp_dir"
        return 1
    fi
    if ! pnm_render_hysteria_config node_cfg hysteria_cfg >"$PNM_HY2_CONFIG"; then
        printf 'test HY2 configuration could not be rendered\n' >&2
        rm -rf -- "$temp_dir"
        return 1
    fi
    pnm_render_xray_config node_cfg reality_cfg >"$PNM_XRAY_CONFIG" || return 1
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG" || return 1
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG" || return 1
    pnm_systemd_active_state() { printf 'active\n'; }
    pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
    pnm_listener_present() { return 0; }
    pnm_require_root() { return 0; }
    PNM_OUTPUT_MODE=text
    secret_before="$(sha256sum "$PNM_CONFIG_DIR/secrets/hysteria.env")" || return 1
    run_capture pnm_node_links --address 203.0.113.10
    secret_after="$(sha256sum "$PNM_CONFIG_DIR/secrets/hysteria.env")" || return 1
    openssl x509 -in "$cert" -outform DER -out "$temp_dir/cert.der" || return 1
    expected_pin="$(sha256sum "$temp_dir/cert.der")" || return 1
    expected_pin="${expected_pin%% *}"
    PNM_CONFIG_DIR="$old_config_dir"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"
    PNM_XRAY_BIN="$old_xray_bin"
    rm -rf -- "$temp_dir"
    [[ "$secret_before" == "$secret_after" && "${hysteria_cfg[HY2_TLS_PIN_SHA256]}" == "$pin" ]] || return 1
    if [[ "$RUN_RC" != 0 ]]; then
        printf 'link command returned %s: %s\n' "$RUN_RC" "$RUN_ERROR" >&2
        return 1
    fi
    if [[ "$RUN_OUTPUT" != *'&sni=www.cloudflare.com&fp=chrome'* ]]; then
        printf 'REALITY SNI field was missing or changed\n' >&2
        return 1
    fi
    if [[ "$RUN_OUTPUT" != *'?sni=proxy-frankfurt&insecure=1'* ]]; then
        printf 'HY2 certificate SNI field was missing or changed\n' >&2
        return 1
    fi
    if [[ "$RUN_OUTPUT" != *"pinSHA256=$expected_pin"* ]]; then
        printf 'HY2 pin field was missing or changed\n' >&2
        return 1
    fi
}

test_legacy_node_infers_a_unique_certificate_san_without_migration() {
    local temp_dir server_name
    local -A node=() hysteria=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:proxy-frankfurt' || { rm -rf -- "$temp_dir"; return 1; }
    node=([HY2_TLS_MODE]=selfsigned-pin [NODE_ADDRESS]=203.0.113.10 [XRAY_SERVER_NAME]=www.cloudflare.com)
    hysteria=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt")
    server_name="$(pnm_hysteria_tls_server_name node hysteria)" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq proxy-frankfurt "$server_name" || return 1
    [[ ! -v 'node[HY2_TLS_SERVER_NAME]' ]]
}

test_legacy_node_conf_without_new_key_remains_valid_and_unmodified() {
    local temp_dir old_config_dir
    local -A legacy_node=()
    temp_dir="$(mktemp -d)"
    cp -- "$TEST_ROOT/fixtures/config-valid/node.conf" "$temp_dir/node.conf"
    sed -i '/^HY2_TLS_SERVER_NAME=/d' "$temp_dir/node.conf"
    old_config_dir="$PNM_CONFIG_DIR"
    PNM_CONFIG_DIR="$temp_dir"
    pnm_load_node_config legacy_node && pnm_validate_node_config legacy_node || { PNM_CONFIG_DIR="$old_config_dir"; rm -rf -- "$temp_dir"; return 1; }
    PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    [[ ! -v 'legacy_node[HY2_TLS_SERVER_NAME]' ]]
}

test_external_ca_node_init_requires_explicit_tls_server_name() {
    local temp_dir old_config_dir rc
    temp_dir="$(mktemp -d)"
    old_config_dir="$PNM_CONFIG_DIR"
    PNM_CONFIG_DIR="$temp_dir/config"
    pnm_require_root() { return 0; }
    run_capture pnm_node_init 0 \
        --region frankfurt --address 203.0.113.10 --tls-mode external-ca \
        --xray-version v1.2.3 --xray-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        --hy2-version v2.3.4 --hy2-sha256 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    rc="$RUN_RC"
    PNM_CONFIG_DIR="$old_config_dir"
    [[ ! -e "$temp_dir/config/node.conf" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq 64 "$rc" || return 1
    assert_contains "$RUN_ERROR" 'Missing required node value: --hy2-server-name'
}

test_external_ca_selects_the_certificate_domain_matching_node_address() {
    local temp_dir server_name
    local -A node=() hysteria=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:edge.example.net,DNS:other.example.net' || { rm -rf -- "$temp_dir"; return 1; }
    node=([HY2_TLS_MODE]=external-ca [NODE_ADDRESS]=edge.example.net [XRAY_SERVER_NAME]=www.cloudflare.com)
    hysteria=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt")
    server_name="$(pnm_hysteria_tls_server_name node hysteria)" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq edge.example.net "$server_name"
}

test_external_ca_uses_an_explicit_domain_for_an_ip_address() {
    local temp_dir server_name
    local -A node=() hysteria=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:hy2.example.net,DNS:other.example.net' || { rm -rf -- "$temp_dir"; return 1; }
    node=(
        [HY2_TLS_MODE]=external-ca [HY2_TLS_SERVER_NAME]=hy2.example.net
        [NODE_ADDRESS]=203.0.113.10 [XRAY_SERVER_NAME]=www.cloudflare.com
    )
    hysteria=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt")
    server_name="$(pnm_hysteria_tls_server_name node hysteria)" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq hy2.example.net "$server_name"
}

test_ambiguous_legacy_certificate_requires_explicit_migration() {
    local temp_dir rc
    local -A node=() hysteria=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:one.example.net,DNS:two.example.net' || { rm -rf -- "$temp_dir"; return 1; }
    node=([HY2_TLS_MODE]=external-ca [NODE_ADDRESS]=203.0.113.10 [XRAY_SERVER_NAME]=www.cloudflare.com)
    hysteria=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt")
    run_capture pnm_hysteria_tls_server_name node hysteria
    rc="$RUN_RC"
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc" || return 1
    assert_contains "$RUN_ERROR" 'set HY2_TLS_SERVER_NAME explicitly' || return 1
    [[ ! -v 'node[HY2_TLS_SERVER_NAME]' ]]
}

test_hy2_tls_sni_mismatch_is_rejected_without_printing_credentials() {
    local temp_dir rc
    local -A node=() hysteria=()
    temp_dir="$(mktemp -d)"
    make_test_certificate "$temp_dir" 'DNS:proxy-frankfurt' || { rm -rf -- "$temp_dir"; return 1; }
    node=([HY2_TLS_MODE]=selfsigned-pin [HY2_TLS_SERVER_NAME]=wrong.example [XRAY_SERVER_NAME]=www.cloudflare.com)
    hysteria=([HY2_TLS_CERT_PATH]="$temp_dir/server.crt" [HY2_AUTH_PASSWORD]=TEST-PASSWORD-MUST-NOT-LEAK)
    run_capture pnm_hysteria_tls_server_name node hysteria
    rc="$RUN_RC"
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc" || return 1
    assert_not_contains "$RUN_ERROR$RUN_OUTPUT" 'TEST-PASSWORD-MUST-NOT-LEAK' || return 1
    assert_not_contains "$RUN_ERROR$RUN_OUTPUT" 'wrong.example'
}

run_test 'HY2 TLS SNI is independent and must match certificate SAN' test_hy2_tls_sni_is_independent_and_matches_certificate_san
run_test 'client links use HY2 SAN and DER fingerprint while preserving REALITY SNI and stored SPKI' test_node_links_use_certificate_san_without_changing_reality_sni_or_pin
run_test 'legacy configuration infers a unique certificate SAN without rewriting it' test_legacy_node_infers_a_unique_certificate_san_without_migration
run_test 'legacy node.conf remains valid without silently adding the new key' test_legacy_node_conf_without_new_key_remains_valid_and_unmodified
run_test 'external CA node initialization requires an explicit TLS server name' test_external_ca_node_init_requires_explicit_tls_server_name
run_test 'external CA chooses the certificate domain matching node address' test_external_ca_selects_the_certificate_domain_matching_node_address
run_test 'external CA supports an explicit certificate domain for IP addresses' test_external_ca_uses_an_explicit_domain_for_an_ip_address
run_test 'ambiguous legacy certificate requires an explicit SNI migration' test_ambiguous_legacy_certificate_requires_explicit_migration
run_test 'HY2 certificate SNI mismatch is rejected without credential leakage' test_hy2_tls_sni_mismatch_is_rejected_without_printing_credentials
finish_tests
