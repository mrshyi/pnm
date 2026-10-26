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
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/tls.sh"
source "$PROJECT_ROOT/lib/check.sh"
# shellcheck source=../../adapters/network.sh
source "$PROJECT_ROOT/adapters/network.sh"
EXPECTED_CHECK_RC=0 EXPECTED_CHECK_OVERALL=OK
if ((EUID != 0)); then EXPECTED_CHECK_RC=1 EXPECTED_CHECK_OVERALL=WARN; fi
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
        PNM_LOCK_FILE="$CHECK_STATE_DIR/pnm.lock" \
        PNM_XRAY_BIN="$FAKE_DIR/xray" \
        PNM_HY2_BIN="${PNM_HY2_BIN:-$FAKE_DIR/hysteria}" \
        PNM_OS_RELEASE_FILE="${PNM_OS_RELEASE_FILE:-$TEST_ROOT/fixtures/os-release-debian-13}" \
        PNM_XRAY_CONFIG="$CHECK_RUNTIME_DIR/xray-config.json" \
        PNM_HY2_CONFIG="$CHECK_RUNTIME_DIR/hysteria-config.yaml" \
        "$PROJECT_ROOT/bin/pnm" "$@"
}

check_xray_binary_resolution() (
    local competing="${1:?competing executable flag required}" temp_dir original_path expected_status
    temp_dir="$(mktemp -d -- "$CHECK_RUNTIME_DIR/health.XXXXXXXX")"
    mkdir -- "$temp_dir/path"
    ln -s -- "$(command -v head)" "$temp_dir/path/head"
    export PNM_XRAY_BIN="$temp_dir/managed-xray"
    export PNM_XRAY_CONFIG="$CHECK_RUNTIME_DIR/xray-config.json"
    export PNM_TEST_HEALTH_LOG="$temp_dir/managed.log"
    export PNM_TEST_DECOY_LOG="$temp_dir/decoy.log"
    cat >"$PNM_XRAY_BIN" <<'EOF'
#!/bin/bash
if [[ "$#" == 1 && "$1" == version ]]; then
    printf 'version\n' >>"$PNM_TEST_HEALTH_LOG"
    printf 'Xray 26.10.21\n'
elif [[ "$#" == 4 && "$1" == run && "$2" == -test && "$3" == -config && "$4" == "$PNM_XRAY_CONFIG" ]]; then
    printf 'config-test\n' >>"$PNM_TEST_HEALTH_LOG"
else
    exit 64
fi
EOF
    chmod 0700 -- "$PNM_XRAY_BIN"
    if [[ "$competing" == yes ]]; then
        cat >"$temp_dir/path/xray" <<'EOF'
#!/bin/bash
printf 'unexpected invocation\n' >"$PNM_TEST_DECOY_LOG"
exit 1
EOF
        chmod 0700 -- "$temp_dir/path/xray"
    fi
    # Isolate service/listener observations while preserving actual executable
    # discovery, config-test invocation, capture and health result handling.
    pnm_service_state_line() { printf 'loaded|active|enabled|running\n'; }
    pnm_listener_present() { [[ "$1" == tcp && "$2" == 443 ]]; }
    pnm_check_reset
    PNM_CHECK_CONFIGURED=1
    PNM_NODE_CONFIG[XRAY_PORT]=443
    original_path="$PATH"
    # Deliberately exclude installed binaries to test managed-path resolution.
    # shellcheck disable=SC2123
    PATH="$temp_dir/path"
    pnm_check_xray
    PATH="$original_path"
    expected_status=OK
    ((EUID == 0)) || expected_status=UNKNOWN
    assert_eq "$expected_status" "${PNM_CHECK_STATUSES[0]}" || return 1
    assert_eq $'version\nconfig-test' "$(<"$PNM_TEST_HEALTH_LOG")" || return 1
    [[ ! -e "$PNM_TEST_DECOY_LOG" ]]
)

test_xray_health_without_path_binary() { check_xray_binary_resolution no; }
test_xray_health_ignores_competing_path_binary() { check_xray_binary_resolution yes; }

test_configured_custom_ports_are_valid() (
    local temp_dir expected_status=OK
    temp_dir="$(mktemp -d -- "$CHECK_RUNTIME_DIR/ports.XXXXXXXX")"
    mkdir -- "$temp_dir/config"
    sed -e 's/^XRAY_PORT=.*/XRAY_PORT=10443/' -e 's/^HY2_PORT=.*/HY2_PORT=18443/' \
        "$CHECK_CONFIG_DIR/node.conf" >"$temp_dir/config/node.conf"
    PNM_CONFIG_DIR="$temp_dir/config"
    pnm_check_reset
    pnm_check_configuration
    ((EUID == 0)) || expected_status=UNKNOWN
    assert_eq "$expected_status" "${PNM_CHECK_STATUSES[0]}" || return 1
    assert_eq 1 "$PNM_CHECK_CONFIGURED"
)

check_core_listener_ports() (
    local unknown="${1:?unknown port flag required}" expected_status=OK probes=''
    PNM_XRAY_BIN="$FAKE_DIR/xray" PNM_HY2_BIN="$FAKE_DIR/hysteria"
    PNM_XRAY_CONFIG="$CHECK_RUNTIME_DIR/xray-config.json"
    PNM_HY2_CONFIG="$CHECK_RUNTIME_DIR/hysteria-config.yaml"
    pnm_service_state_line() { printf 'loaded|active|enabled|running\n'; }
    pnm_listener_present() {
        probes+="$1:$2 "
        [[ "$1:$2" == tcp:10443 || "$1:$2" == udp:18443 ]]
    }
    pnm_check_reset
    PNM_CHECK_CONFIGURED=1
    if [[ "$unknown" == no ]]; then
        PNM_NODE_CONFIG[XRAY_PORT]=10443 PNM_NODE_CONFIG[HY2_PORT]=18443
    else
        PNM_NODE_CONFIG[XRAY_PORT]=invalid PNM_NODE_CONFIG[HY2_PORT]=''
    fi
    pnm_check_xray
    pnm_check_hysteria
    if [[ "$unknown" == yes ]]; then
        expected_status=UNKNOWN
        assert_eq '' "$probes" || return 1
    else
        ((EUID == 0)) || expected_status=UNKNOWN
        assert_eq 'tcp:10443 udp:18443 ' "$probes" || return 1
    fi
    assert_eq "$expected_status" "${PNM_CHECK_STATUSES[0]}" || return 1
    assert_eq "$expected_status" "${PNM_CHECK_STATUSES[1]}"
)

test_core_health_probes_configured_ports() { check_core_listener_ports no; }
test_unknown_core_ports_do_not_probe_defaults() { check_core_listener_ports yes; }

test_passing_check_json() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_eq "$EXPECTED_CHECK_RC" "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" "\"overall\":\"$EXPECTED_CHECK_OVERALL\"" && assert_contains "$RUN_OUTPUT" '"fail":0'
}

test_failure_exit_precedence() {
    PNM_FAKE_PROFILE=fail run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"overall":"FAIL"' && assert_contains "$RUN_OUTPUT" '"status":"FAIL"'
}

test_quiet_has_no_stdout() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --quiet check
    assert_eq "$EXPECTED_CHECK_RC" "$RUN_RC" && assert_eq '' "$RUN_OUTPUT"
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
    if ((EUID == 0)); then
        assert_eq 2 "$RUN_RC" || return 1
        assert_contains "$RUN_OUTPUT" 'Hysteria2 service account cannot read its TLS files' || return 1
    else
        assert_eq 1 "$RUN_RC" || return 1
        # Non-root checks cannot impersonate the service account. They can
        # only report the verified ownership/mode policy; Debian root checks
        # exercise the effective runuser probe above.
        assert_contains "$RUN_OUTPUT" 'HY2 TLS files are readable under the service account policy' || return 1
    fi
    assert_not_contains "$RUN_OUTPUT" 'abcdefghijklmnopqrstuvwxyz012345'
}

test_hysteria_v213_binary_is_detected_and_version_reported() {
    local profile
    run_capture pnm_binary_version "$FAKE_DIR/hysteria" hysteria
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq 'v2.13.0' "$RUN_OUTPUT" || return 1
    run_capture pnm_binary_version_number "$FAKE_DIR/hysteria" hysteria
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '2.13.0' "$RUN_OUTPUT" || return 1

    for profile in pass hysteria-stderr; do
        PNM_FAKE_PROFILE="$profile" run_capture run_fake_pnm --json check
        assert_eq "$EXPECTED_CHECK_RC" "$RUN_RC" || return 1
        if ((EUID == 0)); then
            assert_contains "$RUN_OUTPUT" 'Hysteria2 local checks passed' || return 1
            assert_contains "$RUN_OUTPUT" 'v2.13.0' || return 1
        else
            assert_contains "$RUN_OUTPUT" '"id":"hysteria2","status":"UNKNOWN"' || return 1
        fi
    done

    PNM_FAKE_PROFILE=hysteria-stderr run_capture pnm_binary_version "$FAKE_DIR/hysteria" hysteria
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
        assert_eq "$EXPECTED_CHECK_RC" "$RUN_RC" "supported platform fixture should respect diagnostic permissions: $fixture" || return 1
    done
}

test_platform_policy_checks_architecture_for_each_supported_release() {
    local fixture architecture
    source "$PROJECT_ROOT/adapters/platform-linux.sh"
    pnm_platform_arch() { printf '%s\n' "$architecture"; }
    for fixture in os-release-debian-12 os-release-debian-13 os-release-ubuntu-22.04 os-release-ubuntu-24.04; do
        PNM_OS_RELEASE_FILE="$TEST_ROOT/fixtures/$fixture"
        architecture=x86_64
        pnm_platform_supported || return 1
        for architecture in aarch64 armv7l i686; do
            if pnm_platform_supported; then return 1; fi
        done
    done
}

test_platform_policy_rejects_other_ubuntu_versions_and_derivatives() (
    local temp_dir entry distribution version
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    source "$PROJECT_ROOT/adapters/platform-linux.sh"
    pnm_platform_arch() { printf 'x86_64\n'; }
    PNM_OS_RELEASE_FILE="$temp_dir/os-release"
    for entry in ubuntu:20.04 ubuntu:22.10 ubuntu:24.10 ubuntu:26.04 linuxmint:22.04; do
        IFS=: read -r distribution version <<<"$entry"
        printf 'ID=%s\nID_LIKE=ubuntu\nVERSION_ID="%s"\n' "$distribution" "$version" >"$PNM_OS_RELEASE_FILE" || return 1
        if pnm_platform_supported; then return 1; fi
    done
    printf 'ID=ubuntu\n' >"$PNM_OS_RELEASE_FILE" || return 1
    if pnm_platform_supported; then return 1; fi
)

check_listener_startup_budget() (
    local policy="$1" counter delays=0 rc attempts=26 expected_rc=1 expected_probes=26 expected_delays=25
    counter="$(mktemp -- "$CHECK_RUNTIME_DIR/listener.XXXXXXXX")"
    printf '0\n' >"$counter"
    ss() {
        local count
        count="$(<"$counter")"
        printf '%s\n' "$((count + 1))" >"$counter"
        if [[ "$policy" == delayed && $count -ge 2 ]]; then
            printf 'LISTEN 0 128 0.0.0.0:10443 0.0.0.0:*\n'
        fi
        if [[ "$policy" == tool-error || "$policy" == tool-error-immediate ]]; then
            printf 'LISTEN 0 128 0.0.0.0:10443 0.0.0.0:*\n'
            return 2
        fi
    }
    sleep() { [[ "$1" == 0.2 ]] || return 1; ((delays += 1)); }
    case "$policy" in
        delayed) expected_rc=0 expected_probes=3 expected_delays=2 ;;
        immediate) attempts=1 expected_probes=1 expected_delays=0 ;;
        unavailable)
            pnm_command_exists() { return 1; }
            expected_rc=2 expected_probes=0 expected_delays=0 ;;
        invalid) attempts=27 expected_rc=2 expected_probes=0 expected_delays=0 ;;
        tool-error) expected_rc=2 expected_probes=1 expected_delays=0 ;;
        tool-error-immediate) attempts=1 expected_rc=2 expected_probes=1 expected_delays=0 ;;
    esac
    if [[ "$policy" == immediate ]]; then
        if pnm_listener_present tcp 10443; then rc=0; else rc=$?; fi
    else
        if pnm_listener_present tcp 10443 "$attempts"; then rc=0; else rc=$?; fi
    fi
    assert_eq "$expected_rc" "$rc" || return 1
    assert_eq "$expected_probes" "$(<"$counter")" || return 1
    assert_eq "$expected_delays" "$delays"
)
test_listener_delayed_startup() { check_listener_startup_budget delayed; }
test_listener_startup_exhaustion() { check_listener_startup_budget absent; }
test_listener_diagnostic_is_immediate() { check_listener_startup_budget immediate; }
test_listener_unavailable_does_not_wait() { check_listener_startup_budget unavailable; }
test_listener_rejects_invalid_budget() { check_listener_startup_budget invalid; }
test_listener_startup_tool_failure_is_unknown() { check_listener_startup_budget tool-error; }
test_listener_immediate_tool_failure_is_unknown() { check_listener_startup_budget tool-error-immediate; }

run_test 'startup listener probe permits delayed readiness' test_listener_delayed_startup
run_test 'startup listener probe stops at its fixed maximum budget' test_listener_startup_exhaustion
run_test 'ordinary listener diagnostics retain a single immediate probe' test_listener_diagnostic_is_immediate
run_test 'unavailable listener tools do not consume the startup budget' test_listener_unavailable_does_not_wait
run_test 'invalid listener retry budgets are refused before probing' test_listener_rejects_invalid_budget
run_test 'startup listener tool failures stay unknown without retries' test_listener_startup_tool_failure_is_unknown
run_test 'ordinary listener tool failures cannot become a free port' test_listener_immediate_tool_failure_is_unknown
run_test 'Xray health tests the managed binary when PATH has no xray' test_xray_health_without_path_binary
run_test 'Xray health ignores a competing PATH executable' test_xray_health_ignores_competing_path_binary
run_test 'persisted custom ports are valid desired state' test_configured_custom_ports_are_valid
run_test 'both Core health checks probe configured listener ports' test_core_health_probes_configured_ports
run_test 'unknown Core ports cannot fall back to unrelated default listeners' test_unknown_core_ports_do_not_probe_defaults
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
run_test 'each supported release requires the deployment architecture' test_platform_policy_checks_architecture_for_each_supported_release
run_test 'Ubuntu platform policy rejects unapproved releases derivatives and missing version' test_platform_policy_rejects_other_ubuntu_versions_and_derivatives
finish_tests
