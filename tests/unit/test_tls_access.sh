#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/accounts.sh"
source "$PROJECT_ROOT/lib/check.sh"
source "$TEST_ROOT/testlib.sh"

if ((EUID != 0)) || ! command -v runuser >/dev/null || ! id nobody >/dev/null 2>&1; then
    printf '# SKIP: real TLS access tests require root, runuser and an existing nobody account\n'
    finish_tests
    exit 0
fi
suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT
chmod 0755 "$suite_root"
service_uid="$(id -u nobody)" service_gid="$(id -g nobody)"
assert_eq "$service_uid" "$(command runuser -u nobody -- id -u)" || exit 1

prepare_access_fixture() {
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    chmod 0755 "$fixture_root"
    PNM_CONFIG_DIR="$fixture_root/config"
    mkdir -p "$PNM_CONFIG_DIR/secrets" "$fixture_root/tls"
    chmod 0700 "$PNM_CONFIG_DIR" "$PNM_CONFIG_DIR/secrets"
    chmod 0755 "$fixture_root/tls"
    cert="$fixture_root/tls/server.crt" key="$fixture_root/tls/server.key"
    printf 'synthetic certificate fixture\n' >"$cert"
    printf 'synthetic private key fixture\n' >"$key"
    command chown "0:$service_gid" "$cert"
    command chown "$service_uid:$service_gid" "$key"
    chmod 0644 "$cert"
    chmod 0600 "$key"
    printf 'SCHEMA_VERSION=1\nHY2_AUTH_PASSWORD=abcdefghijklmnopqrstuvwx12345678\nHY2_TLS_CERT_PATH=%s\nHY2_TLS_KEY_PATH=%s\nHY2_TLS_PIN_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' \
        "$cert" "$key" >"$PNM_CONFIG_DIR/secrets/hysteria.env"
    chmod 0600 "$PNM_CONFIG_DIR/secrets/hysteria.env"
    fixture_uid="$service_uid" fixture_gid="$service_gid"
    fixture_probe_calls=0 fixture_stat_failure=0
    pnm_check_reset
    PNM_CHECK_CONFIGURED=1 PNM_NODE_CONFIG[HY2_TLS_MODE]=selfsigned-pin
}

# Map only account names/NSS policy to an existing unprivileged identity. The
# actual file UID/GID/mode, ancestor traversal and runuser readability probes
# use kernel permission checks. This does not load a real TLS certificate/key.
# No account or group is created, renamed, or changed on the host.
getent() {
    case "$1:${2-}" in
        passwd:hysteria) printf 'hysteria:x:%s:%s:Test identity:/nonexistent:/usr/sbin/nologin\n' "$fixture_uid" "$fixture_gid" ;;
        group:hysteria) printf 'hysteria:x:%s:\n' "$fixture_gid" ;;
        *) command getent "$@" ;;
    esac
}
stat() {
    local mode uid gid owner group stat_target="${!#}"
    if [[ "$1" == -c && "$2" == '%a|%U|%G' && ( "$stat_target" == "$cert" || "$stat_target" == "$key" ) ]]; then
        ((fixture_stat_failure == 0)) || return 1
        IFS='|' read -r mode uid gid < <(command stat -c '%a|%u|%g' -- "$stat_target")
        owner="$uid" group="$gid"
        [[ "$uid" != 0 ]] || owner=root
        [[ "$uid" != "$service_uid" ]] || owner=hysteria
        [[ "$gid" != "$service_gid" ]] || group=hysteria
        printf '%s|%s|%s\n' "$mode" "$owner" "$group"
    else
        command stat "$@"
    fi
}
runuser() {
    [[ "$#" == 6 && "$1" == -u && "$2" == hysteria && "$3" == -- && "$4" == test && "$5" == -r &&
        ( "$6" == "$cert" || "$6" == "$key" ) ]] || return 77
    ((fixture_probe_calls += 1))
    command runuser -u nobody -- test -r "$6"
}

fixture_evidence() {
    local path
    for path in "$cert" "$key"; do
        if [[ -L "$path" ]]; then readlink "$path"
        elif [[ -f "$path" ]]; then command stat -c '%a:%u:%g' "$path"; sha256sum "$path"
        else printf 'MISSING\n'; fi
    done
    command stat -c '%a:%u:%g' "$fixture_root" "$fixture_root/tls"
}

check_access_status() {
    local expected="$1" before after
    before="$(fixture_evidence)" || return 1
    pnm_check_hysteria_tls_permissions
    after="$(fixture_evidence)" || return 1
    assert_eq "$expected" "${PNM_CHECK_STATUSES[0]}" || return 1
    assert_eq "$before" "$after" 'diagnostics must not change fixture bytes or metadata' || return 1
    assert_not_contains "${PNM_CHECK_SUMMARIES[*]} ${PNM_CHECK_DETAILS[*]}" 'abcdefghijklmnopqrstuvwx12345678' || return 1
    assert_not_contains "${PNM_CHECK_SUMMARIES[*]} ${PNM_CHECK_DETAILS[*]}" 'synthetic private key fixture'
}

test_service_uid_passes_effective_readability_probes() {
    prepare_access_fixture || return 1
    check_access_status OK || return 1
    assert_eq 2 "$fixture_probe_calls"
}

test_ancestor_access_denial_fails_despite_matching_leaf_metadata() {
    prepare_access_fixture || return 1
    chmod 0700 "$fixture_root/tls"
    check_access_status FAIL || return 1
    assert_eq 1 "$fixture_probe_calls" || return 1
    assert_contains "${PNM_CHECK_DETAILS[0]}" 'effective read probe failed'
}

test_wrong_leaf_ownership_modes_and_unsafe_files_fail() {
    local scenario
    for scenario in key-mode key-owner key-group cert-mode cert-owner cert-group symlink missing; do
        prepare_access_fixture || return 1
        case "$scenario" in
            key-mode) chmod 0644 "$key" ;;
            key-owner) command chown "0:$service_gid" "$key" ;;
            key-group) command chown "$service_uid:0" "$key" ;;
            cert-mode) chmod 0600 "$cert" ;;
            cert-owner) command chown "$service_uid:$service_gid" "$cert" ;;
            cert-group) command chown 0:0 "$cert" ;;
            symlink) mv "$key" "$fixture_root/other.key"; ln -s "$fixture_root/other.key" "$key" ;;
            missing) rm "$key" ;;
        esac
        check_access_status FAIL || return 1
        assert_eq 0 "$fixture_probe_calls" || return 1
    done
}

test_privileged_service_identities_fail_before_probe() {
    local field
    for field in uid gid; do
        prepare_access_fixture || return 1
        if [[ "$field" == uid ]]; then fixture_uid=0; else fixture_gid=0; fi
        check_access_status FAIL || return 1
        assert_eq 0 "$fixture_probe_calls" || return 1
    done
}

test_missing_runuser_is_unknown_without_permission_changes() {
    prepare_access_fixture || return 1
    pnm_command_exists() { [[ "$1" != runuser ]]; }
    check_access_status UNKNOWN || return 1
    assert_eq 0 "$fixture_probe_calls"
}

test_unavailable_metadata_is_unknown_without_probe() {
    prepare_access_fixture || return 1
    fixture_stat_failure=1
    check_access_status UNKNOWN || return 1
    assert_eq 0 "$fixture_probe_calls"
}

test_unconfigured_and_nonstatic_tls_skip_without_probe() {
    local scenario
    for scenario in unconfigured nonstatic; do
        prepare_access_fixture || return 1
        if [[ "$scenario" == unconfigured ]]; then PNM_CHECK_CONFIGURED=0; else PNM_NODE_CONFIG[HY2_TLS_MODE]=acme; fi
        check_access_status SKIP || return 1
        assert_eq 0 "$fixture_probe_calls" || return 1
    done
}

test_invalid_secret_metadata_is_unknown_without_probe() {
    prepare_access_fixture || return 1
    printf 'SCHEMA_VERSION=1\n' >"$PNM_CONFIG_DIR/secrets/hysteria.env"
    check_access_status UNKNOWN || return 1
    assert_eq 0 "$fixture_probe_calls"
}

run_test 'TLS service identity passes both effective readability probes' test_service_uid_passes_effective_readability_probes
run_test 'TLS ancestor access denial fails despite matching file metadata' test_ancestor_access_denial_fails_despite_matching_leaf_metadata
run_test 'TLS wrong ownership modes and unsafe file types fail before read probes' test_wrong_leaf_ownership_modes_and_unsafe_files_fail
run_test 'TLS privileged service identities fail before actual read probes' test_privileged_service_identities_fail_before_probe
run_test 'TLS missing access tool reports unknown without mutation' test_missing_runuser_is_unknown_without_permission_changes
run_test 'TLS unavailable metadata reports unknown without mutation' test_unavailable_metadata_is_unknown_without_probe
run_test 'TLS unconfigured and nonstatic modes skip without mutation' test_unconfigured_and_nonstatic_tls_skip_without_probe
run_test 'TLS invalid Secret metadata reports unknown without probing' test_invalid_secret_metadata_is_unknown_without_probe
finish_tests
