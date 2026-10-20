#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
FAKE_COMMAND="$TEST_ROOT/fakebin/fake-command"
FAKE_DIR="$(mktemp -d)"
CHECK_CONFIG_DIR="$(mktemp -d)"
mkdir -p -- "$CHECK_CONFIG_DIR/secrets"
cp -- "$TEST_ROOT/fixtures/config-valid/node.conf" "$CHECK_CONFIG_DIR/node.conf"
cp -- "$TEST_ROOT/fixtures/config-valid/versions.conf" "$CHECK_CONFIG_DIR/versions.conf"
touch -- "$CHECK_CONFIG_DIR/server.crt"
cat >"$CHECK_CONFIG_DIR/secrets/hysteria.env" <<EOF
SCHEMA_VERSION=1
HY2_AUTH_PASSWORD=abcdefghijklmnopqrstuvwxyz012345
HY2_TLS_CERT_PATH=$CHECK_CONFIG_DIR/server.crt
HY2_TLS_KEY_PATH=$CHECK_CONFIG_DIR/server.key
HY2_TLS_PIN_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
EOF
chmod 0600 -- "$CHECK_CONFIG_DIR/secrets/hysteria.env"
trap 'rm -rf -- "$FAKE_DIR" "$CHECK_CONFIG_DIR"' EXIT

for command_name in uname systemctl timedatectl ss xray hysteria openssl apt-get stat; do
    ln -s "$FAKE_COMMAND" "$FAKE_DIR/$command_name"
done

# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

run_fake_pnm() {
    env \
        PATH="$FAKE_DIR:$PATH" \
        PNM_TEST_SYSTEMD=1 \
        PNM_FAKE_PROFILE="${PNM_FAKE_PROFILE:-pass}" \
        PNM_CONFIG_DIR="$CHECK_CONFIG_DIR" \
        PNM_XRAY_BIN="$FAKE_DIR/xray" \
        PNM_HY2_BIN="${PNM_HY2_BIN:-$FAKE_DIR/hysteria}" \
        PNM_OS_RELEASE_FILE="${PNM_OS_RELEASE_FILE:-$TEST_ROOT/fixtures/os-release-debian-13}" \
        PNM_XRAY_CONFIG="$TEST_ROOT/fixtures/xray-config.json" \
        PNM_HY2_CONFIG="$TEST_ROOT/fixtures/hysteria-config.yaml" \
        "$PROJECT_ROOT/bin/pnm" "$@"
}

test_passing_check_json() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"overall":"OK"' && assert_contains "$RUN_OUTPUT" '"fail":0'
}

test_failure_exit_precedence() {
    PNM_FAKE_PROFILE=fail run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"overall":"FAIL"' && assert_contains "$RUN_OUTPUT" '"status":"FAIL"'
}

test_quiet_has_no_stdout() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --quiet check
    assert_eq 0 "$RUN_RC" && assert_eq '' "$RUN_OUTPUT"
}

test_json_contains_no_fixture_password() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_not_contains "$RUN_OUTPUT" 'REDACTED_FIXTURE'
}

test_expired_hysteria_certificate_fails_health_check() {
    PNM_FAKE_PROFILE=expired-cert run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"id":"hysteria_tls","status":"FAIL"'
}

test_hysteria_v213_binary_is_detected_and_version_reported() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'Hysteria2 local checks passed' || return 1
    assert_contains "$RUN_OUTPUT" 'v2.13.0' || return 1

    PNM_FAKE_PROFILE=hysteria-stderr run_capture run_fake_pnm --json check
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'v2.13.0'
}

test_hysteria_missing_binary_is_distinct_from_version_failure() {
    PNM_HY2_BIN="$FAKE_DIR/missing-hysteria" PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'Hysteria2 is not installed' || return 1

    PNM_HY2_BIN="$FAKE_DIR/hysteria" PNM_FAKE_PROFILE=hysteria-exec-fails run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'Hysteria2 version could not be determined' || return 1
    assert_not_contains "$RUN_OUTPUT" 'Hysteria2 is not installed'
}

test_status_reports_hysteria_version() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json status
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'v2.13.0'
}

test_supported_platform_matrix() {
    local fixture

    for fixture in os-release-debian-12 os-release-debian-13 os-release-ubuntu-22.04 os-release-ubuntu-24.04; do
        PNM_OS_RELEASE_FILE="$TEST_ROOT/fixtures/$fixture" PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --quiet check
        assert_eq 0 "$RUN_RC" "supported platform fixture should pass: $fixture" || return 1
    done
}

run_test 'fully healthy fixture returns PASS JSON' test_passing_check_json
run_test 'FAIL takes exit-code precedence' test_failure_exit_precedence
run_test 'quiet mode emits no stdout' test_quiet_has_no_stdout
run_test 'check output does not expose config secret fixture' test_json_contains_no_fixture_password
run_test 'expired Hysteria2 certificate fails the health check' test_expired_hysteria_certificate_fails_health_check
run_test 'official Hysteria2 v2.13.0 banner is detected and reported' test_hysteria_v213_binary_is_detected_and_version_reported
run_test 'missing Hysteria binary differs from version-command failure' test_hysteria_missing_binary_is_distinct_from_version_failure
run_test 'status reports the detected Hysteria2 version' test_status_reports_hysteria_version
run_test 'supported Debian and Ubuntu platform matrix passes' test_supported_platform_matrix
finish_tests
