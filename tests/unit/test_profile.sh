#!/usr/bin/env bash
# shellcheck disable=SC1090
set -Eeuo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
for module in common output config render lock transaction lifecycle core-ops profile check menu; do
    source "$PROJECT_ROOT/lib/$module.sh"
done
source "$TEST_ROOT/testlib.sh"
source <(declare -f pnm_tx_prepare_directory | sed '1s/pnm_tx_prepare_directory/profile_real_prepare_directory/')
source <(declare -f pnm_profile_validate_core | sed '1s/pnm_profile_validate_core/profile_real_validate_core/')
source <(declare -f pnm_tx_write_file | sed '1s/pnm_tx_write_file/profile_real_write_file/')

profile_fixture() {
    fixture=$(mktemp -d)
    trap 'rm -rf -- "$fixture"' EXIT
    PNM_CONFIG_DIR="$fixture/config" PNM_STATE_DIR="$fixture/state" PNM_LOCK_FILE="$fixture/lock/pnm.lock"
    PNM_XRAY_CONFIG="$fixture/xray.json" PNM_HY2_CONFIG="$fixture/hysteria.yaml"
    mkdir -m 0700 "$PNM_CONFIG_DIR"
    sed 's/^PNM_CONFIGURED=.*/PNM_CONFIGURED=yes/' "$TEST_ROOT/fixtures/config-valid/node.conf" >"$PNM_CONFIG_DIR/node.conf"
    chmod 0600 "$PNM_CONFIG_DIR/node.conf"
    printf '{}\n' >"$PNM_XRAY_CONFIG"
    printf 'listen: :8443\n' >"$PNM_HY2_CONFIG"
    printf 'credential sentinel\n' >"$fixture/secret"
    declare -gA fixture_active=([xray.service]=active [hysteria-server.service]=active)
    declare -gA fixture_enabled=([xray.service]=enabled [hysteria-server.service]=enabled)
    declare -gA fixture_invocation=([xray.service]=00000000000000000000000000000001 [hysteria-server.service]=00000000000000000000000000000002)
    serial=2 calls='' fail_start='' fail_restore=0 invalid_core=''
    pnm_require_root() { :; }
    pnm_platform_supported() { :; }
    pnm_systemd_available() { :; }
    pnm_profile_validate_core() { pnm_core_resolve "$1"; [[ "$1" != "$invalid_core" ]]; }
    pnm_systemd_active_state() { printf '%s\n' "${fixture_active[$1]}"; }
    pnm_systemd_enabled_state() { printf '%s\n' "${fixture_enabled[$1]}"; }
    pnm_systemd_show_value() { [[ "$2" == InvocationID ]] && printf '%s\n' "${fixture_invocation[$1]}"; }
    pnm_systemd_daemon_reload() { :; }
    pnm_core_runtime_listener_ready() { :; }
    pnm_check_deploy_core_health() { local unit; unit=$(pnm_core_lifecycle_unit "$1"); [[ "${fixture_active[$unit]}:${fixture_enabled[$unit]}" == active:enabled ]]; }
    pnm_systemctl() {
        local action=$1 unit=$2
        calls+="$action:$unit "
        case "$action" in
            enable) ((fail_restore == 0)) || return 1; fixture_enabled[$unit]=enabled ;;
            disable) fixture_enabled[$unit]=disabled ;;
            stop | reset-failed) fixture_active[$unit]=inactive ;;
            start)
                if [[ "$fail_start" == "$unit" ]]; then fail_start=''; fixture_active[$unit]=failed; return 1; fi
                if [[ "${fixture_active[$unit]}" != active ]]; then ((serial+=1)); printf -v 'fixture_invocation[$unit]' '%032x' "$serial"; fi
                fixture_active[$unit]=active ;;
            *) return 1 ;;
        esac
    }
    pnm_systemd_start() { pnm_systemctl start "$1"; }
    pnm_systemd_stop() { pnm_systemctl stop "$1"; }
    pnm_systemd_enable() { pnm_systemctl enable "$1"; }
    pnm_systemd_disable() { pnm_systemctl disable "$1"; }
    pnm_systemd_stop_verified() {
        pnm_systemctl stop "$1" && [[ "$(pnm_systemd_active_state "$1")" == inactive ]]
    }
    pnm_tx_prepare_directory() {
        if [[ "$1" == /etc/systemd/system/multi-user.target.wants ]]; then
            profile_real_prepare_directory "$fixture/wants" "$2"
        else
            profile_real_prepare_directory "$@"
        fi
    }
    pnm_tx_begin fixture-bindings
    pnm_core_record_applied_config xray "$PNM_XRAY_CONFIG" "$PNM_TX_PATH"
    pnm_core_record_applied_config hysteria2 "$PNM_HY2_CONFIG" "$PNM_TX_PATH"
    pnm_tx_commit
    pnm_tx_close
}

test_profile_compatibility() (
    local -A node=()
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid"
    pnm_load_node_config node && pnm_validate_node_config node || return 1
    assert_eq dual "${node[PNM_PROFILE]-dual}" || return 1
    node[PNM_PROFILE]=invalid
    ! pnm_validate_node_config node || return 1
    node[PNM_PROFILE]=reality
    pnm_validate_node_config node && pnm_profile_includes reality xray &&
        ! pnm_profile_includes reality hysteria2 && pnm_profile_includes hy2 hysteria2 &&
        ! pnm_profile_includes hy2 xray
)

test_profile_switch_roundtrip() (
    profile_fixture
    local xray_before=${fixture_invocation[xray.service]} hy2_before files_before files_after
    files_before=$(sha256sum "$PNM_XRAY_CONFIG" "$PNM_HY2_CONFIG" "$fixture/secret")
    pnm_profile_command set reality --yes || return 1
    assert_eq "$xray_before" "${fixture_invocation[xray.service]}" || return 1
    assert_eq inactive "${fixture_active[hysteria-server.service]}" || return 1
    assert_eq disabled "${fixture_enabled[hysteria-server.service]}" || return 1
    pnm_profile_command set hy2 --yes || return 1
    assert_eq inactive "${fixture_active[xray.service]}" || return 1
    hy2_before=${fixture_invocation[hysteria-server.service]}
    pnm_profile_command set dual --yes || return 1
    assert_eq "$hy2_before" "${fixture_invocation[hysteria-server.service]}" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status hysteria2 "$PNM_HY2_CONFIG")" || return 1
    files_after=$(sha256sum "$PNM_XRAY_CONFIG" "$PNM_HY2_CONFIG" "$fixture/secret")
    assert_eq "$files_before" "$files_after" || return 1
    calls=''
    pnm_profile_command set dual --yes || return 1
    assert_eq '' "$calls"
)

test_profile_start_failure_recovers() (
    profile_fixture
    pnm_profile_command set reality --yes || return 1
    local node_before
    node_before=$(sha256sum "$PNM_CONFIG_DIR/node.conf")
    fail_start=hysteria-server.service
    run_capture pnm_profile_command set hy2 --yes
    assert_eq 70 "$RUN_RC" || return 1
    assert_eq "$node_before" "$(sha256sum "$PNM_CONFIG_DIR/node.conf")" || return 1
    assert_eq active "${fixture_active[xray.service]}" || return 1
    assert_eq inactive "${fixture_active[hysteria-server.service]}" || return 1
    assert_eq disabled "${fixture_enabled[hysteria-server.service]}" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_assert_no_pending_deployment || return 1
    pnm_profile_command set hy2 --yes
)

test_profile_precheck_refuses_changes() (
    profile_fixture
    invalid_core=hysteria2
    run_capture pnm_profile_command set reality --yes
    [[ "$RUN_RC" != 0 && -z "$calls" ]] || return 1
    PNM_ASSUME_YES=0
    run_capture pnm_profile_command set reality
    assert_eq 64 "$RUN_RC" || return 1
    run_capture pnm_profile_command set other --yes
    assert_eq 64 "$RUN_RC"
)

test_profile_show_reports_actual_drift() (
    profile_fixture
    pnm_profile_command set reality --yes || return 1
    fixture_active[hysteria-server.service]=active
    PNM_OUTPUT_MODE=json
    run_capture pnm_profile_command show
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["desired"]=="reality"; c=d["cores"][1]; assert c["desired_enabled"] is False and c["active"]=="active"' <<<"$RUN_OUTPUT" || return 1
    pnm_check_reset
    pnm_check_profile_inactive hysteria2
    assert_eq FAIL "${PNM_CHECK_STATUSES[0]}"
)

test_profile_disabled_core_refuses_restart() (
    profile_fixture
    pnm_profile_command set reality --yes || return 1
    calls=''
    run_capture pnm_core_command restart hy2
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq '' "$calls" || return 1
    local -A node=() secret=()
    pnm_load_node_config node
    run_capture pnm_node_core_link_status hysteria2 node secret
    assert_contains "$RUN_OUTPUT" 'excluded by the desired profile'
)

test_profile_ownership_check_refuses_unknown_units() (
    profile_fixture
    local PNM_PROFILE_TARGET=dual
    local -A PNM_PROFILE_NODE=()
    run_capture profile_real_validate_core xray
    [[ "$RUN_RC" != 0 && -z "$calls" ]]
)

test_profile_publication_failure_recovers() (
    profile_fixture
    local node_before
    node_before=$(sha256sum "$PNM_CONFIG_DIR/node.conf")
    pnm_tx_write_file() {
        profile_real_write_file "$@" || return $?
        [[ "$2" != "$PNM_CONFIG_DIR/node.conf" ]] || return 73
    }
    run_capture pnm_profile_command set hy2 --yes
    assert_eq 73 "$RUN_RC" || return 1
    assert_eq "$node_before" "$(sha256sum "$PNM_CONFIG_DIR/node.conf")" || return 1
    assert_eq active "${fixture_active[xray.service]}" || return 1
    assert_eq active "${fixture_active[hysteria-server.service]}" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_assert_no_pending_deployment
)

test_profile_menu_confirmation() (
    profile_fixture
    run_capture pnm_menu_profile <<< $'reality\nno'
    assert_eq '' "$calls" || return 1
    run_capture pnm_menu_profile <<< $'reality\nyes'
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq inactive "${fixture_active[hysteria-server.service]}"
)

run_test 'legacy nodes default to dual and invalid profiles refuse' test_profile_compatibility
run_test 'profile roundtrip preserves files and unchanged Core invocations' test_profile_switch_roundtrip
run_test 'failed activation restores the prior profile and applied binding, then permits retry' test_profile_start_failure_recovers
run_test 'profile precheck and confirmation refuse before service changes' test_profile_precheck_refuses_changes
run_test 'profile show exposes actual drift and diagnostics fail it' test_profile_show_reports_actual_drift
run_test 'disabled Core restart and client link are refused' test_profile_disabled_core_refuses_restart
run_test 'profile ownership validation refuses unknown host units' test_profile_ownership_check_refuses_unknown_units
run_test 'profile publication failure restores node bytes, services and applied state' test_profile_publication_failure_recovers
run_test 'profile menu requires confirmation before switching' test_profile_menu_confirmation
finish_tests
