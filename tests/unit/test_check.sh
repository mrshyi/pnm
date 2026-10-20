#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
FAKE_COMMAND="$TEST_ROOT/fakebin/fake-command"
FAKE_DIR="$(mktemp -d)"
CHECK_CONFIG_DIR="$(mktemp -d)"
CHECK_RUNTIME_DIR="$(mktemp -d)"
CHECK_STATE_DIR="$(mktemp -d)"
mkdir -p -- "$CHECK_CONFIG_DIR/secrets" "$CHECK_STATE_DIR/cores/xray" "$CHECK_STATE_DIR/cores/hysteria2"
cp -- "$TEST_ROOT/fixtures/config-valid/node.conf" "$CHECK_CONFIG_DIR/node.conf"
cp -- "$TEST_ROOT/fixtures/config-valid/versions.conf" "$CHECK_CONFIG_DIR/versions.conf"
cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$CHECK_CONFIG_DIR/secrets/reality.env"
touch -- "$CHECK_CONFIG_DIR/server.crt" "$CHECK_CONFIG_DIR/server.key"
cat >"$CHECK_CONFIG_DIR/secrets/hysteria.env" <<EOF
SCHEMA_VERSION=1
HY2_AUTH_PASSWORD=abcdefghijklmnopqrstuvwxyz012345
HY2_TLS_CERT_PATH=$CHECK_CONFIG_DIR/server.crt
HY2_TLS_KEY_PATH=$CHECK_CONFIG_DIR/server.key
HY2_TLS_PIN_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
EOF
chmod 0600 -- "$CHECK_CONFIG_DIR/secrets/hysteria.env" "$CHECK_CONFIG_DIR/secrets/reality.env"
trap 'rm -rf -- "$FAKE_DIR" "$CHECK_CONFIG_DIR" "$CHECK_RUNTIME_DIR" "$CHECK_STATE_DIR"' EXIT

for command_name in uname systemctl timedatectl ss xray hysteria openssl apt-get stat getent runuser; do
    ln -s "$FAKE_COMMAND" "$FAKE_DIR/$command_name"
done

# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"
# shellcheck source=../../lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/tls.sh"
# shellcheck source=../../adapters/network.sh
source "$PROJECT_ROOT/adapters/network.sh"
# Keep the sourced library defaults from shadowing this script's fixture paths.
unset PNM_CONFIG_DIR PNM_OS_RELEASE_FILE PNM_XRAY_CONFIG PNM_HY2_CONFIG PNM_XRAY_BIN PNM_HY2_BIN

PNM_CONFIG_DIR="$CHECK_CONFIG_DIR"
if command -v python3 >/dev/null 2>&1; then
    declare -A CHECK_NODE=() CHECK_REALITY=() CHECK_HYSTERIA=()
    pnm_load_node_config CHECK_NODE && pnm_load_reality_secret CHECK_REALITY && pnm_load_hysteria_secret CHECK_HYSTERIA
    pnm_render_xray_config CHECK_NODE CHECK_REALITY >"$CHECK_RUNTIME_DIR/xray-config.json"
    pnm_render_hysteria_config CHECK_NODE CHECK_HYSTERIA >"$CHECK_RUNTIME_DIR/hysteria-config.yaml"
    for core in xray hysteria2; do
        case "$core" in
            xray) runtime_config="$CHECK_RUNTIME_DIR/xray-config.json" ;;
            hysteria2) runtime_config="$CHECK_RUNTIME_DIR/hysteria-config.yaml" ;;
        esac
        printf 'SCHEMA_VERSION=1\nCORE=%s\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=0123456789abcdef0123456789abcdef\n' \
            "$core" "$(sha256sum -- "$runtime_config" | awk '{print $1}')" >"$CHECK_STATE_DIR/cores/$core/applied.env"
    done
else
    cp -- "$TEST_ROOT/fixtures/xray-config.json" "$CHECK_RUNTIME_DIR/xray-config.json"
    cp -- "$TEST_ROOT/fixtures/hysteria-config.yaml" "$CHECK_RUNTIME_DIR/hysteria-config.yaml"
fi

run_fake_pnm() {
    env \
        PATH="$FAKE_DIR:$PATH" \
        PNM_TEST_SYSTEMD=1 \
        PNM_FAKE_PROFILE="${PNM_FAKE_PROFILE:-pass}" \
        PNM_CONFIG_DIR="$CHECK_CONFIG_DIR" \
        PNM_STATE_DIR="$CHECK_STATE_DIR" \
        PNM_XRAY_BIN="$FAKE_DIR/xray" \
        PNM_HY2_BIN="${PNM_HY2_BIN:-$FAKE_DIR/hysteria}" \
        PNM_OS_RELEASE_FILE="${PNM_OS_RELEASE_FILE:-$TEST_ROOT/fixtures/os-release-debian-13}" \
        PNM_XRAY_CONFIG="$CHECK_RUNTIME_DIR/xray-config.json" \
        PNM_HY2_CONFIG="$CHECK_RUNTIME_DIR/hysteria-config.yaml" \
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

test_hysteria_sni_certificate_mismatch_fails_health_check() {
    PNM_FAKE_PROFILE=hy2-sni-mismatch run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'HY2 TLS server name does not match its certificate' || return 1
    assert_not_contains "$RUN_OUTPUT" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_hysteria_tls_private_key_permissions_are_checked_without_mutation() {
    PNM_FAKE_PROFILE=bad-tls-mode run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"id":"hysteria_tls_permissions","status":"FAIL"' || return 1
    assert_contains "$RUN_OUTPUT" 'private_key=644|root|root' || return 1
    assert_not_contains "$RUN_OUTPUT" 'PRIVATE KEY'
}

test_hysteria_tls_runtime_user_readability_is_checked() {
    PNM_FAKE_PROFILE=bad-tls-read run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    if ((EUID == 0)); then
        assert_contains "$RUN_OUTPUT" 'Hysteria2 service account cannot read its TLS files' || return 1
    else
        # Non-root checks cannot impersonate the service account. They can
        # only report the verified ownership/mode policy; Debian root checks
        # exercise the effective runuser probe above.
        assert_contains "$RUN_OUTPUT" 'HY2 TLS files are readable under the service account policy' || return 1
    fi
    assert_not_contains "$RUN_OUTPUT" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_hysteria_v213_binary_is_detected_and_version_reported() {
    run_capture pnm_binary_version "$FAKE_DIR/hysteria" hysteria
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq 'v2.13.0' "$RUN_OUTPUT" || return 1
    run_capture pnm_binary_version_number "$FAKE_DIR/hysteria" hysteria
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '2.13.0' "$RUN_OUTPUT" || return 1

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

test_hysteria_version_failures_are_distinguished() {
    local non_executable="$FAKE_DIR/hysteria-not-executable"
    cp -- "$FAKE_COMMAND" "$non_executable"
    chmod 0644 -- "$non_executable"
    if [[ ! -x "$non_executable" ]]; then
        PNM_HY2_BIN="$non_executable" run_capture run_fake_pnm --json check
        assert_eq 2 "$RUN_RC" || return 1
        assert_contains "$RUN_OUTPUT" 'not executable' || return 1
    fi

    PNM_HY2_BIN="$FAKE_DIR/hysteria" PNM_FAKE_PROFILE=hysteria-no-version run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'version output could not be parsed' || return 1

    PNM_HY2_BIN="$FAKE_DIR/hysteria" PNM_FAKE_PROFILE=hysteria-exec-fails run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'version command failed' || return 1

    PNM_HY2_BIN="$FAKE_DIR/hysteria" PNM_FAKE_PROFILE=hysteria-no-version run_capture run_fake_pnm --json status
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'version-parse-failed' || return 1
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
run_test 'Hysteria2 TLS SNI mismatch fails health check without secrets' test_hysteria_sni_certificate_mismatch_fails_health_check
run_test 'HY2 TLS private key permissions are checked without mutation' test_hysteria_tls_private_key_permissions_are_checked_without_mutation
run_test 'HY2 TLS files are probed as the Hysteria2 runtime account' test_hysteria_tls_runtime_user_readability_is_checked
run_test 'official Hysteria2 v2.13.0 banner is detected and reported' test_hysteria_v213_binary_is_detected_and_version_reported
run_test 'missing Hysteria binary differs from version-command failure' test_hysteria_missing_binary_is_distinct_from_version_failure
run_test 'Hysteria binary, invocation, and parse failures are distinguished' test_hysteria_version_failures_are_distinguished
run_test 'status reports the detected Hysteria2 version' test_status_reports_hysteria_version
run_test 'supported Debian and Ubuntu platform matrix passes' test_supported_platform_matrix
finish_tests
