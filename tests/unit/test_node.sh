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

test_validate_existing_node() {
    run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid" "$PROJECT_ROOT/bin/pnm" node validate
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'node.conf is valid' || return 1
    assert_contains "$RUN_OUTPUT" 'versions.conf is valid'
}

test_show_hides_secrets_and_exposes_node() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    declare -gA NODE=() REALITY=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || return 1
    pnm_render_xray_config NODE REALITY >"$PNM_XRAY_CONFIG" || return 1
    pnm_xray_config_runtime_values() { printf '443\texample.com:443\texample.com\ttcp\n'; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_show
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'PNM node' || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443' || return 1
    assert_contains "$RUN_OUTPUT" 'config=consistent' || return 1
    assert_contains "$RUN_OUTPUT" 'sni=example.com target=example.com:443' || return 1
    assert_not_contains "$RUN_OUTPUT" 'REDACTED_FIXTURE'
}

test_node_links_render_client_import_uris() {
    local temp_dir fake_xray runtime_config old_xray_bin old_xray_config old_config_dir
    temp_dir="$(mktemp -d)"
    mkdir -p -- "$temp_dir/config/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$temp_dir/config/versions.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$temp_dir/config/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$temp_dir/config/secrets/hysteria.env"
    sed -i 's/^XRAY_SERVER_NAME=.*/XRAY_SERVER_NAME=front.example.com/;s/^XRAY_TARGET=.*/XRAY_TARGET=edge.example.net:8443/' "$temp_dir/config/node.conf"
    fake_xray="$temp_dir/xray"
    runtime_config="$temp_dir/xray-config.json"
    old_xray_bin="$PNM_XRAY_BIN"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_config_dir="$PNM_CONFIG_DIR"
    printf '#!/usr/bin/env bash\nprintf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\nHash32: ignored\\n"\n' >"$fake_xray"
    chmod 0755 -- "$fake_xray"
    PNM_CONFIG_DIR="$temp_dir/config"
    PNM_XRAY_BIN="$fake_xray"
    PNM_XRAY_CONFIG="$runtime_config"
    declare -gA NODE=() REALITY=()
    pnm_load_node_config NODE && pnm_load_reality_secret REALITY || return 1
    pnm_render_xray_config NODE REALITY >"$runtime_config" || return 1
    PNM_OUTPUT_MODE=text
    pnm_require_root() { return 0; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_links --address 203.0.113.10
    PNM_XRAY_BIN="$old_xray_bin"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_CONFIG_DIR="$old_config_dir"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'vless://11111111-2222-4333-8444-555555555555@203.0.113.10:443' || return 1
    assert_contains "$RUN_OUTPUT" '&sni=front.example.com&fp=chrome' || return 1
    assert_contains "$RUN_OUTPUT" 'pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' || return 1
    assert_contains "$RUN_OUTPUT" 'hysteria2://abcdefghijklmnopqrstuvwxyz012345@203.0.113.10:8443/' || return 1
    assert_contains "$RUN_OUTPUT" '?sni=front.example.com&insecure=1' || return 1
    assert_contains "$RUN_OUTPUT" 'pinSHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D' || return 1
    assert_not_contains "$RUN_OUTPUT" '\\'
    assert_eq 'A%2FB%2BC%3D' "$(pnm_node_uri_encode 'A/B+C=')" || return 1
    assert_not_contains "$RUN_OUTPUT" 'fixture-private'
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
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443 -> proxy-frankfurt' || return 1
    assert_contains "$RUN_OUTPUT" 'do not use the VPS hostname'
}

test_node_show_reports_runtime_drift_without_secrets() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_XRAY_CONFIG="$temp_dir/runtime.json"
    printf '{"inbounds":[]}\n' >"$PNM_XRAY_CONFIG"
    pnm_xray_config_runtime_values() { printf '443\twww.cloudflare.com:443\twww.cloudflare.com\ttcp\n'; }
    pnm_systemd_active_state() { printf 'active\n'; }
    run_capture pnm_node_show
    rc=$RUN_RC
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443 -> example.com (example.com:443)' || return 1
    assert_contains "$RUN_OUTPUT" 'service=active config=drift port=443 sni=www.cloudflare.com target=www.cloudflare.com:443' || return 1
    assert_contains "$RUN_ERROR" 'differs from the runtime Xray configuration' || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" '11111111-2222-4333-8444-555555555555'
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
    assert_contains "$RUN_ERROR" 'Runtime Xray configuration differs from node.conf' || return 1
    assert_not_contains "$RUN_OUTPUT" 'vless://'
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
    rm -rf -- "$temp_dir"
    return "$rc"
}

run_test 'node validation accepts a complete configuration' test_validate_existing_node
run_test 'node show reports only non-secret desired state' test_show_hides_secrets_and_exposes_node
run_test 'node links render client import URIs without private keys' test_node_links_render_client_import_uris
run_test 'node validation rejects a single-label REALITY SNI' test_node_validation_rejects_single_label_reality_sni
run_test 'node links refuse a VPS hostname as REALITY SNI' test_node_links_refuse_single_label_reality_sni
run_test 'node show reports an invalid REALITY SNI for diagnosis' test_node_show_reports_invalid_reality_sni
run_test 'node show reports runtime drift without exposing credentials' test_node_show_reports_runtime_drift_without_secrets
run_test 'new defaults do not migrate an existing Microsoft node' test_node_init_does_not_migrate_existing_microsoft_config
run_test 'node links refuse to emit credentials when runtime Xray config has drifted' test_node_links_refuse_runtime_configuration_drift
run_test 'node validation rejects invalid values' test_invalid_node_is_rejected
run_test 'latest release metadata parsers return pinned values' test_release_metadata_parsers
run_test 'latest lookup returns concrete pinned versions and hashes' test_latest_version_lookup_persists_concrete_values
run_test 'node init writes both validated files in one transaction' test_init_writes_valid_files_transactionally
finish_tests
