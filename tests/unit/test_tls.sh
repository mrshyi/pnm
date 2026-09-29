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
# shellcheck source=../../lib/tls.sh
source "$PNM_LIB_DIR/tls.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_selfsigned_pair_is_valid_and_pinned() {
    local temp_dir certificate private_key pin mode
    temp_dir="$(mktemp -d)"
    certificate="$temp_dir/tls/server.crt"
    private_key="$temp_dir/tls/server.key"
    mkdir -m 0700 -- "$temp_dir/tls"
    pnm_tls_generate_selfsigned "$certificate" "$private_key" example.com || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tls_validate_pair "$certificate" "$private_key" || { rm -rf -- "$temp_dir"; return 1; }
    pin="$(pnm_tls_spki_pin "$certificate")"
    mode="$(stat -c '%a' "$private_key")"
    rm -rf -- "$temp_dir"
    pnm_validate_pin_sha256 "$pin" && assert_eq 600 "$mode"
}

test_mismatched_pair_is_rejected() {
    local temp_dir cert1 key1 cert2 key2 rc
    temp_dir="$(mktemp -d)"
    mkdir -m 0700 -- "$temp_dir/one" "$temp_dir/two"
    cert1="$temp_dir/one/server.crt"; key1="$temp_dir/one/server.key"
    cert2="$temp_dir/two/server.crt"; key2="$temp_dir/two/server.key"
    pnm_tls_generate_selfsigned "$cert1" "$key1" example.com || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tls_generate_selfsigned "$cert2" "$key2" example.net || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tls_validate_pair "$cert1" "$key2"; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    [[ "$rc" != 0 ]]
}

run_test 'self-signed certificate pair is valid and produces Base64 pin' test_selfsigned_pair_is_valid_and_pinned
run_test 'certificate/private-key mismatch is rejected' test_mismatched_pair_is_rejected
finish_tests
