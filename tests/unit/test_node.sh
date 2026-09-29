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

test_validate_existing_node() {
    run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid" "$PROJECT_ROOT/bin/pnm" node validate
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'node.conf is valid' || return 1
    assert_contains "$RUN_OUTPUT" 'versions.conf is valid'
}

test_show_hides_secrets_and_exposes_node() {
    run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets" "$PROJECT_ROOT/bin/pnm" node show
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'PNM node' || return 1
    assert_contains "$RUN_OUTPUT" 'xray: 443' || return 1
    assert_not_contains "$RUN_OUTPUT" 'REDACTED_FIXTURE'
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
    [[ "${node_config[TIMEZONE]}" == UTC ]] || return 1
    [[ "${node_config[XRAY_SERVER_NAME]}" == www.microsoft.com ]] || return 1
    [[ "${node_config[XRAY_TARGET]}" == www.microsoft.com:443 ]] || return 1
    [[ "${node_config[XRAY_PORT]}" == 443 && "${node_config[HY2_PORT]}" == 8443 ]] || return 1
    [[ "${node_config[HY2_TLS_MODE]}" == selfsigned-pin ]] || return 1
    rm -rf -- "$temp_dir"
    return "$rc"
}

run_test 'node validation accepts a complete configuration' test_validate_existing_node
run_test 'node show reports only non-secret desired state' test_show_hides_secrets_and_exposes_node
run_test 'node validation rejects invalid values' test_invalid_node_is_rejected
run_test 'latest release metadata parsers return pinned values' test_release_metadata_parsers
run_test 'latest lookup returns concrete pinned versions and hashes' test_latest_version_lookup_persists_concrete_values
run_test 'node init writes both validated files in one transaction' test_init_writes_valid_files_transactionally
finish_tests
