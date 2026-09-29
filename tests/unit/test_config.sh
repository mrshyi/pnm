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
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_valid_config() {
    declare -A config=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid"
    pnm_load_node_config config
    assert_eq 443 "${config[XRAY_PORT]}" && assert_eq selfsigned-pin "${config[HY2_TLS_MODE]}"
}

test_unsafe_config_rejected() {
    declare -A config=()
    local rc
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-unsafe"
    rm -f -- /tmp/pnm-configuration-was-executed
    if pnm_load_node_config config >/dev/null 2>&1; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" && [[ ! -e /tmp/pnm-configuration-was-executed ]]
}

test_duplicate_config_rejected() {
    declare -A config=()
    local rc
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-duplicate"
    if pnm_load_node_config config >/dev/null 2>&1; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc"
}

test_invalid_typed_values_rejected() {
    declare -A config=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-invalid"
    if pnm_load_node_config config >/dev/null 2>&1; then
        if pnm_validate_node_config config; then
            return 1
        fi
        return 0
    fi
    # Values containing spaces are rejected even before typed validation.
    return 0
}

test_versions_manifest_validation() {
    declare -A versions=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid"
    pnm_load_versions_config versions
    pnm_validate_versions_config versions
}

test_symlink_config_rejected() {
    declare -A config=()
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    ln -s "$TEST_ROOT/fixtures/config-valid/node.conf" "$temp_dir/node.conf"
    PNM_CONFIG_DIR="$temp_dir"
    if pnm_load_node_config config >/dev/null 2>&1; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc"
}

run_test 'valid node configuration parses as data' test_valid_config
run_test 'command substitution is rejected and not executed' test_unsafe_config_rejected
run_test 'duplicate configuration keys are rejected' test_duplicate_config_rejected
run_test 'invalid typed configuration values are rejected' test_invalid_typed_values_rejected
run_test 'approved versions manifest validates' test_versions_manifest_validation
run_test 'symlink configuration is rejected' test_symlink_config_rejected
finish_tests
