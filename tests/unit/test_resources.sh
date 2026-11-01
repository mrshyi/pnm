#!/usr/bin/env bash
# Trusted function extraction preserves the real resource reader for private fixtures.
# shellcheck disable=SC1090
set -Eeuo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
for module in common output config check status; do source "$PROJECT_ROOT/lib/$module.sh"; done
source "$PROJECT_ROOT/adapters/resources.sh"
source "$TEST_ROOT/testlib.sh"
source <(declare -f pnm_resource_observations | sed '1s/pnm_resource_observations/resource_real_observations/')

resource_fixture() {
    resource_root=$(mktemp -d)
    trap 'rm -rf -- "$resource_root"' EXIT
    printf 'MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 100 kB\nSwapFree: 90 kB\n' >"$resource_root/meminfo"
    printf '0.1 0.2 0.3 1/100 123\n' >"$resource_root/loadavg"
    printf 'cpu 0 0 0 0\ncpu0 0 0 0 0\ncpu1 0 0 0 0\n' >"$resource_root/stat"
    printf 'oom_kill 0\n' >"$resource_root/vmstat"
    pnm_resource_observations() { resource_real_observations "$resource_root"; }
}

test_resources_healthy_snapshot() (
    resource_fixture
    pnm_check_reset
    pnm_check_resources
    assert_eq 4 "${#PNM_CHECK_IDS[@]}" || return 1
    assert_eq 'OK OK OK OK' "${PNM_CHECK_STATUSES[*]}" || return 1
    assert_eq 0 "$PNM_CHECK_WARN_COUNT" || return 1
    assert_contains "${PNM_CHECK_DETAILS[3]}" 'not attributed to PNM'
)

test_resources_pressure_warns() (
    resource_fixture
    printf 'MemTotal: 1000 kB\nMemAvailable: 50 kB\nSwapTotal: 100 kB\nSwapFree: 5 kB\n' >"$resource_root/meminfo"
    printf '3 3 3 1/100 123\n' >"$resource_root/loadavg"
    printf 'oom_kill 2\n' >"$resource_root/vmstat"
    pnm_check_reset
    pnm_check_resources
    assert_eq 'WARN WARN WARN WARN' "${PNM_CHECK_STATUSES[*]}" || return 1
    run_capture pnm_check_exit_code
    assert_eq 1 "$RUN_RC" || return 1
    pnm_check_add core FAIL 'Existing failure' ''
    run_capture pnm_check_exit_code
    assert_eq 2 "$RUN_RC"
)

test_resources_no_swap_skips() (
    resource_fixture
    printf 'MemTotal: 1000 kB\nMemAvailable: 100 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$resource_root/meminfo"
    pnm_check_reset
    pnm_check_resources
    assert_eq SKIP "${PNM_CHECK_STATUSES[1]}" || return 1
    assert_eq 0 "$PNM_CHECK_WARN_COUNT"
)

test_resources_unavailable_is_unknown() (
    resource_fixture
    rm "$resource_root/meminfo" "$resource_root/loadavg" "$resource_root/vmstat"
    pnm_check_reset
    pnm_check_resources
    assert_eq 'UNKNOWN UNKNOWN UNKNOWN UNKNOWN' "${PNM_CHECK_STATUSES[*]}" || return 1
    assert_eq 4 "$PNM_CHECK_UNKNOWN_COUNT"
)

test_resources_invalid_counters_are_unknown() (
    resource_fixture
    printf 'MemTotal: 10 kB\nMemAvailable: 20 kB\nSwapTotal: -1 kB\nSwapFree: 0 kB\n' >"$resource_root/meminfo"
    printf 'nan 1 2\n' >"$resource_root/loadavg"
    printf 'oom_kill -1\n' >"$resource_root/vmstat"
    pnm_check_reset
    pnm_check_resources
    assert_eq 'UNKNOWN UNKNOWN UNKNOWN UNKNOWN' "${PNM_CHECK_STATUSES[*]}"
)

test_resources_reader_failure_is_unknown() (
    pnm_resource_observations() { return 69; }
    pnm_check_reset
    pnm_check_resources
    assert_eq 1 "${#PNM_CHECK_IDS[@]}" || return 1
    assert_eq UNKNOWN "${PNM_CHECK_STATUSES[0]}"
)

status_fixture() {
    resource_fixture
    PNM_CONFIG_DIR="$resource_root/config"
    mkdir "$PNM_CONFIG_DIR"
    sed 's/^XRAY_PORT=.*/XRAY_PORT=1443/;s/^HY2_PORT=.*/HY2_PORT=18443/' \
        "$TEST_ROOT/fixtures/config-valid/node.conf" >"$PNM_CONFIG_DIR/node.conf"
    printf 'PNM_PROFILE=reality\n' >>"$PNM_CONFIG_DIR/node.conf"
    pnm_service_state_line() { printf 'loaded|active|enabled|running\n'; }
    pnm_binary_version() { printf 'fixture\n'; }
    pnm_listener_present() { printf '%s:%s\n' "$1" "$2" >>"$resource_root/queries"; return 0; }
    pnm_platform_summary() { printf 'fixture\n'; }
}

test_status_reports_profile_and_configured_ports() (
    status_fixture
    pnm_status_collect
    assert_eq $'tcp:1443\nudp:18443' "$(<"$resource_root/queries")" || return 1
    run_capture pnm_status_render_json
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="pnm.status.v1" and d["desired_profile"]=="reality"; x,h=d["cores"]; assert x["port"]==1443 and x["desired_enabled"] is True; assert h["port"]==18443 and h["desired_enabled"] is False; assert d["services"][1]["active"]=="active"' <<<"$RUN_OUTPUT"
)

test_status_missing_node_does_not_probe_defaults() (
    status_fixture
    rm "$PNM_CONFIG_DIR/node.conf"
    pnm_status_collect
    [[ ! -e "$resource_root/queries" ]] || return 1
    run_capture pnm_status_render_json
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["desired_profile"]=="unknown"; assert all(c["port"] is None and c["desired_enabled"] is None and c["listener"]=="unknown" for c in d["cores"])' <<<"$RUN_OUTPUT"
)

run_test 'resource snapshot reports memory swap load and system OOM without Core attribution' test_resources_healthy_snapshot
run_test 'resource warnings retain WARN exit and existing failures retain FAIL precedence' test_resources_pressure_warns
run_test 'no swap is a deliberate skip rather than a configuration demand' test_resources_no_swap_skips
run_test 'missing resource counters remain unknown' test_resources_unavailable_is_unknown
run_test 'invalid resource counters cannot imply health' test_resources_invalid_counters_are_unknown
run_test 'unavailable resource reader produces an unknown result' test_resources_reader_failure_is_unknown
run_test 'status separates desired profile from actual services and probes configured ports' test_status_reports_profile_and_configured_ports
run_test 'status without readable desired state does not probe default ports' test_status_missing_node_does_not_probe_defaults
finish_tests
