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

test_certificate_check_reports_valid_expired_unreadable_and_skipped_modes() (
    local temp_dir certificate private_key status test_now_epoch not_after
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    certificate="$temp_dir/valid.crt"; private_key="$temp_dir/valid.key"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=valid.example' \
        -keyout "$private_key" -out "$certificate" >/dev/null 2>&1 || { rm -rf -- "$temp_dir"; return 1; }
    status="$(pnm_tls_certificate_check selfsigned-pin "$certificate")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$status" 'OK|' || { rm -rf -- "$temp_dir"; return 1; }
    not_after="$(openssl x509 -in "$certificate" -noout -enddate)" || return 1
    test_now_epoch="$(date -u -d "${not_after#notAfter=}" +%s)" || return 1
    # Test expiry against a real certificate without relying on unsupported
    # `openssl req -days 0` or waiting for wall-clock time to advance.
    date() {
        if [[ "$*" == '-u +%s' ]]; then
            printf '%s\n' "$test_now_epoch"
        else
            command date "$@"
        fi
    }
    status="$(pnm_tls_certificate_check external-ca "$certificate")" || return 1
    assert_contains "$status" 'FAIL|' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$status" 'expired' || { rm -rf -- "$temp_dir"; return 1; }
    status="$(pnm_tls_certificate_check selfsigned-pin "$temp_dir/missing.crt")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$status" 'WARN|' || { rm -rf -- "$temp_dir"; return 1; }
    status="$(pnm_tls_certificate_check acme-runtime "$temp_dir/missing.crt")" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_contains "$status" 'SKIP|'
)

run_test 'self-signed certificate pair is valid and produces Base64 pin' test_selfsigned_pair_is_valid_and_pinned
run_test 'certificate/private-key mismatch is rejected' test_mismatched_pair_is_rejected
run_test 'TLS certificate check reports valid, expired, unreadable, and skipped modes' test_certificate_check_reports_valid_expired_unreadable_and_skipped_modes
finish_tests
