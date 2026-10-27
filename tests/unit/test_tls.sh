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

tls_spki_pipeline_failure_refuses_pin() (
    local failed_stage="$1" temp_dir pipefail_mode
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    command openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
        -subj '/CN=fixture.invalid' -keyout "$temp_dir/key" -out "$temp_dir/cert" >/dev/null 2>&1 || return 1
    openssl() {
        command openssl "$@" || return $?
        if [[ "$failed_stage" == der && "$1" == pkey && "$2" == -pubin ]] ||
            [[ "$failed_stage" == digest && "$1" == dgst ]]; then return 23; fi
    }
    base64() {
        command base64 "$@" || return $?
        if [[ "$failed_stage" == base64 ]]; then return 23; fi
    }
    for pipefail_mode in on off; do
        if [[ "$pipefail_mode" == on ]]; then set -o pipefail; else set +o pipefail; fi
        run_capture pnm_tls_spki_pin "$temp_dir/cert"
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT$RUN_ERROR" || return 1
        assert_eq "$pipefail_mode" "$(set -o | awk '$1 == "pipefail" {print $2}')" || return 1
    done
)

test_spki_der_failure_refuses_pin() { tls_spki_pipeline_failure_refuses_pin der; }
test_spki_digest_failure_refuses_pin() { tls_spki_pipeline_failure_refuses_pin digest; }
test_spki_base64_failure_refuses_pin() { tls_spki_pipeline_failure_refuses_pin base64; }

test_key_publication_failure_refuses_pair_without_caller_pipefail() (
    local temp_dir pipefail_mode
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    command openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
        -subj '/CN=fixture.invalid' -keyout "$temp_dir/key" -out "$temp_dir/cert" >/dev/null 2>&1 || return 1
    openssl() {
        command openssl "$@" || return $?
        if [[ "$1" == pkey && "$*" == *-pubout* ]]; then return 23; fi
    }
    for pipefail_mode in on off; do
        if [[ "$pipefail_mode" == on ]]; then set -o pipefail; else set +o pipefail; fi
        run_capture pnm_tls_validate_pair "$temp_dir/cert" "$temp_dir/key"
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT$RUN_ERROR" || return 1
        assert_eq "$pipefail_mode" "$(set -o | awk '$1 == "pipefail" {print $2}')" || return 1
    done
)

tls_dangling_destination_is_preserved() (
    local operation="$1" leaf="$2" temp_dir target other
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    mkdir -m 0700 -- "$temp_dir/seed" "$temp_dir/target"
    pnm_tls_generate_selfsigned "$temp_dir/seed/cert" "$temp_dir/seed/key" example.com || return 1
    target="$temp_dir/target/$leaf"
    if [[ "$leaf" == server.crt ]]; then other=server.key; else other=server.crt; fi
    ln -s -- "$temp_dir/foreign-missing" "$target" || return 1
    if [[ "$operation" == generate ]]; then
        run_capture pnm_tls_generate_selfsigned "$temp_dir/target/server.crt" "$temp_dir/target/server.key" example.com
    else
        run_capture pnm_tls_stage_external_pair "$temp_dir/seed/cert" "$temp_dir/seed/key" "$temp_dir/target"
    fi
    assert_eq "$PNM_EXIT_CANTCREAT" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    [[ -L "$target" && "$(readlink -- "$target")" == "$temp_dir/foreign-missing" ]] || return 1
    [[ ! -e "$temp_dir/foreign-missing" && ! -L "$temp_dir/foreign-missing" ]] || return 1
    [[ ! -e "$temp_dir/target/$other" && ! -L "$temp_dir/target/$other" ]] || return 1
    [[ -z "$(find "$temp_dir/target" -maxdepth 1 -name '.pnm-*' -print -quit)" ]]
)

test_generated_certificate_keeps_foreign_dangling_link() { tls_dangling_destination_is_preserved generate server.crt; }
test_generated_key_keeps_foreign_dangling_link() { tls_dangling_destination_is_preserved generate server.key; }
test_external_certificate_keeps_foreign_dangling_link() { tls_dangling_destination_is_preserved external server.crt; }
test_external_key_keeps_foreign_dangling_link() { tls_dangling_destination_is_preserved external server.key; }

tls_mode_failure_refuses_publication() (
    local failed_mode="$1" temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf 'unrelated data' >"$temp_dir/sentinel"
    chmod() {
        if [[ "$1" == "$failed_mode" && "${!#}" == "$temp_dir"/.pnm-* ]]; then return 1; fi
        command chmod "$@"
    }
    run_capture pnm_tls_generate_selfsigned "$temp_dir/cert" "$temp_dir/key" example.com
    assert_eq "$PNM_EXIT_NOPERM" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    [[ ! -e "$temp_dir/cert" && ! -e "$temp_dir/key" ]] || return 1
    [[ -z "$(find "$temp_dir" -maxdepth 1 -name '.pnm-*' -print -quit)" ]] || return 1
    assert_eq 'unrelated data' "$(<"$temp_dir/sentinel")"
)

test_certificate_mode_failure_refuses_publication() { tls_mode_failure_refuses_publication 0644; }
test_key_mode_failure_refuses_publication() { tls_mode_failure_refuses_publication 0600; }

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

test_dns_match_checks_positive_result_and_preserves_san_policy() (
    local temp_dir name
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
        -subj '/CN=wrong.example' -addext 'subjectAltName=DNS:*.fixture.example' \
        -keyout "$temp_dir/key" -out "$temp_dir/cert" >/dev/null 2>&1 || return 1
    for name in one.fixture.example ONE.fixture.example; do
        pnm_tls_certificate_matches_dns_name "$temp_dir/cert" "$name" || return 1
    done
    for name in wrong.example fixture.example two.one.fixture.example; do
        run_capture pnm_tls_certificate_matches_dns_name "$temp_dir/cert" "$name"
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT$RUN_ERROR" || return 1
    done
    openssl() {
        if [[ "$*" == *-checkhost* ]]; then
            printf '%s\n' "$fixture_result"
            return "$fixture_rc"
        fi
        command openssl "$@"
    }
    local fixture_result fixture_rc=0
    for fixture_result in '' 'unexpected output' 'Hostname one.fixture.example does NOT match certificate'; do
        run_capture pnm_tls_certificate_matches_dns_name "$temp_dir/cert" one.fixture.example
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT$RUN_ERROR" || return 1
    done
    fixture_result='Hostname one.fixture.example does match certificate' fixture_rc=1
    run_capture pnm_tls_certificate_matches_dns_name "$temp_dir/cert" one.fixture.example
    assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC"
)

test_client_fingerprint_hashes_certificate_der_not_spki() (
    local temp_dir expected first second spki_first spki_second
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
        -subj '/CN=fixture.invalid' -set_serial 1 -keyout "$temp_dir/key" -out "$temp_dir/one.crt" >/dev/null 2>&1 || return 1
    openssl req -x509 -key "$temp_dir/key" -days 1 -subj '/CN=fixture.invalid' -set_serial 2 \
        -out "$temp_dir/two.crt" >/dev/null 2>&1 || return 1
    openssl x509 -in "$temp_dir/one.crt" -outform DER -out "$temp_dir/cert.der" || return 1
    expected="$(sha256sum "$temp_dir/cert.der")"; expected="${expected%% *}"
    first="$(pnm_tls_certificate_sha256 "$temp_dir/one.crt")" || return 1
    second="$(pnm_tls_certificate_sha256 "$temp_dir/two.crt")" || return 1
    spki_first="$(pnm_tls_spki_pin "$temp_dir/one.crt")" || return 1
    spki_second="$(pnm_tls_spki_pin "$temp_dir/two.crt")" || return 1
    [[ "$first" =~ ^[0-9a-f]{64}$ && "$first" == "$expected" && "$first" != "$second" ]] || return 1
    [[ "$spki_first" == "$spki_second" ]]
)

test_client_fingerprint_rejects_invalid_inputs_and_tool_output() (
    local temp_dir candidate
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf 'not a certificate\n' >"$temp_dir/bad.crt"
    ln -s -- "$temp_dir/bad.crt" "$temp_dir/link.crt"
    for candidate in "$temp_dir/missing.crt" "$temp_dir/bad.crt" "$temp_dir/link.crt"; do
        run_capture pnm_tls_certificate_sha256 "$candidate"
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT" || return 1
    done
    openssl() { return 77; }
    run_capture pnm_tls_certificate_sha256 "$temp_dir/bad.crt"
    assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    openssl() { printf 'sha256 Fingerprint=malformed\n'; }
    run_capture pnm_tls_certificate_sha256 "$temp_dir/bad.crt"
    assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT"
)

run_test 'DNS matching rejects mismatches and unknown tool results while preserving wildcard SAN rules' test_dns_match_checks_positive_result_and_preserves_san_policy
run_test 'client fingerprint hashes full certificate DER and changes on same-key renewal' test_client_fingerprint_hashes_certificate_der_not_spki
run_test 'client fingerprint rejects invalid input and tool failure or malformed output' test_client_fingerprint_rejects_invalid_inputs_and_tool_output
run_test 'self-signed certificate pair is valid and produces Base64 pin' test_selfsigned_pair_is_valid_and_pinned
run_test 'self-signed staging preserves an existing dangling certificate link' test_generated_certificate_keeps_foreign_dangling_link
run_test 'self-signed staging preserves an existing dangling key link' test_generated_key_keeps_foreign_dangling_link
run_test 'external TLS staging preserves an existing dangling certificate link' test_external_certificate_keeps_foreign_dangling_link
run_test 'external TLS staging preserves an existing dangling key link' test_external_key_keeps_foreign_dangling_link
run_test 'certificate mode failure refuses self-signed publication' test_certificate_mode_failure_refuses_publication
run_test 'key mode failure refuses self-signed publication' test_key_mode_failure_refuses_publication
run_test 'SPKI DER conversion failure refuses a pin without leaking pipeline output' test_spki_der_failure_refuses_pin
run_test 'SPKI digest failure refuses a pin without leaking pipeline output' test_spki_digest_failure_refuses_pin
run_test 'SPKI encoding failure refuses a pin without leaking pipeline output' test_spki_base64_failure_refuses_pin
run_test 'key public-output failure refuses the pair independently of caller pipefail' test_key_publication_failure_refuses_pair_without_caller_pipefail
run_test 'certificate/private-key mismatch is rejected' test_mismatched_pair_is_rejected
run_test 'TLS certificate check reports valid, expired, unreadable, and skipped modes' test_certificate_check_reports_valid_expired_unreadable_and_skipped_modes
finish_tests
