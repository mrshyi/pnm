#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/lib/deploy.sh"
source "$PROJECT_ROOT/lib/apply-gate.sh"
source "$PROJECT_ROOT/lib/node.sh"
source "$TEST_ROOT/testlib.sh"

prepare_deployment_fixture() {
    local root="$1"
    PNM_STATE_DIR="$root/state" PNM_LOCK_FILE="$root/lock"
    PNM_CONFIG_DIR="$root/config"
    PNM_DRY_RUN=0 PNM_ASSUME_YES=1
    PNM_DEPLOY_ID_OVERRIDE=deploy-fixture PNM_TX_ID_OVERRIDE=tx-fixture
    PNM_APPLY_GATE_ID_OVERRIDE=apply-fixture
    PNM_DEPLOY_STEP_SANDBOX=fixture_resources
    PNM_DEPLOY_STEP_XRAY=fixture_xray
    PNM_DEPLOY_STEP_HYSTERIA=fixture_hysteria
    PNM_DEPLOY_STEP_HEALTH=fixture_health
    PNM_APPLY_GATE_STEP_HEALTH=fixture_outer_health
    FIXTURE_ROOT="$root" FIXTURE_FAILURE=''
    declare -gA FIXTURE_ACTIVE=([xray.service]=active [hysteria-server.service]=inactive)
    declare -gA FIXTURE_ENABLED=([xray.service]=enabled [hysteria-server.service]=disabled)
    mkdir -p "$root/units" "$PNM_CONFIG_DIR"
    printf 'old unit\n' >"$root/units/xray.service"
    printf 'old binary\n' >"$root/binary"
    chmod 0750 "$root/binary"
    printf 'PNM_CONFIGURED=no\n' >"$PNM_CONFIG_DIR/node.conf"
    chmod 0600 "$PNM_CONFIG_DIR/node.conf"
}

pnm_require_root() { return 0; }
pnm_preflight_collect() { return 0; }
pnm_preflight_exit_code() { return 0; }
pnm_core_applied_config_status() { printf 'unknown\n'; }
pnm_deploy_validate_ownership() { return 0; }
pnm_systemd_load_state() {
    if [[ -f "$FIXTURE_ROOT/units/$1" ]]; then printf 'loaded\n'; else printf 'not-found\n'; fi
}
pnm_systemd_active_state() { printf '%s\n' "${FIXTURE_ACTIVE[$1]}"; }
pnm_systemd_enabled_state() { printf '%s\n' "${FIXTURE_ENABLED[$1]}"; }
pnm_systemd_daemon_reload() { return 0; }
pnm_systemd_unit_healthy() { [[ "${FIXTURE_ACTIVE[$1]}" == active && "${FIXTURE_ENABLED[$1]}" == enabled ]]; }
pnm_listener_present() { return 0; }
pnm_systemctl() {
    local action="$1" unit="${2-}"
    case "$action" in
        stop) FIXTURE_ACTIVE[$unit]=inactive ;;
        restart|start) FIXTURE_ACTIVE[$unit]=active ;;
        enable) FIXTURE_ENABLED[$unit]=enabled ;;
        disable) FIXTURE_ENABLED[$unit]=disabled ;;
        *) return 70 ;;
    esac
}
pnm_service_accounts_rollback() { return 0; }

fixture_resources() {
    local owns_transaction=0
    if ((PNM_TX_ACTIVE == 0)); then
        PNM_TX_ID_OVERRIDE=tx-resources
        pnm_tx_begin sandbox-install || return $?
        owns_transaction=1
    fi
    printf 'new binary\n' >"$FIXTURE_ROOT/staged"
    pnm_tx_write_file "$FIXTURE_ROOT/staged" "$FIXTURE_ROOT/binary" binary 0755 || return $?
    pnm_tx_prepare_directory "$FIXTURE_ROOT/new" 0700 || return $?
    pnm_tx_write_file "$FIXTURE_ROOT/staged" "$FIXTURE_ROOT/new/secret" secret 0600 || return $?
    pnm_tx_write_file "$FIXTURE_ROOT/staged" "$FIXTURE_ROOT/units/hysteria-server.service" hy2_unit 0644 || return $?
    [[ "$FIXTURE_FAILURE" != resources ]] || return 78
    if ((owns_transaction == 1)); then pnm_tx_commit && pnm_tx_close; fi
    return 0
}
fixture_xray() { pnm_systemctl start xray.service; [[ "$FIXTURE_FAILURE" != xray ]] || return 78; }
fixture_hysteria() { pnm_systemctl enable hysteria-server.service; pnm_systemctl start hysteria-server.service; [[ "$FIXTURE_FAILURE" != hysteria ]] || return 78; }
fixture_health() { [[ "$FIXTURE_FAILURE" != inner-health ]] || return 78; }
fixture_outer_health() { [[ "$FIXTURE_FAILURE" != outer-health ]] || return 78; }
pnm_deploy_mark_configured() {
    local owns_transaction=0
    if ((PNM_TX_ACTIVE == 0)); then
        PNM_TX_ID_OVERRIDE=tx-state
        pnm_tx_begin install-state || return $?
        owns_transaction=1
    fi
    printf 'PNM_CONFIGURED=yes\n' >"$FIXTURE_ROOT/configured"
    pnm_tx_write_file "$FIXTURE_ROOT/configured" "$PNM_CONFIG_DIR/node.conf" node_config 0600 || return $?
    [[ "$FIXTURE_FAILURE" != configured ]] || return 78
    if ((owns_transaction == 1)); then pnm_tx_commit && pnm_tx_close; fi
    return 0
}

test_late_failure_restores_resources_and_services() (
    local root rc expected_rc=78 failure="${1:-outer-health}"
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    FIXTURE_FAILURE="$failure"
    if [[ "$failure" == deadline ]]; then
        pnm_apply_gate_deadline_check() { return 77; }
        expected_rc=77
    elif [[ "$failure" == commit ]]; then
        pnm_tx_publish_deployment_commit() { return 73; }
        expected_rc=73
    fi
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq "$expected_rc" "$rc" || return 1
    assert_eq 'old binary' "$(<"$root/binary")" || return 1
    assert_eq 750 "$(stat -c '%a' "$root/binary")" || return 1
    assert_eq 'PNM_CONFIGURED=no' "$(<"$PNM_CONFIG_DIR/node.conf")" || return 1
    [[ ! -e "$root/new" && ! -e "$root/units/hysteria-server.service" ]] || return 1
    assert_eq active "${FIXTURE_ACTIVE[xray.service]}" || return 1
    assert_eq enabled "${FIXTURE_ENABLED[xray.service]}" || return 1
    assert_eq inactive "${FIXTURE_ACTIVE[hysteria-server.service]}" || return 1
    assert_eq disabled "${FIXTURE_ENABLED[hysteria-server.service]}" || return 1
    assert_eq 0 "$PNM_TX_ACTIVE" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
)

test_each_phase_failure_restores_baseline() {
    local phase
    for phase in resources xray hysteria inner-health configured deadline commit; do
        test_late_failure_restores_resources_and_services "$phase" || return 1
    done
}

test_active_disabled_baseline_is_restored() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    FIXTURE_ENABLED[xray.service]=disabled FIXTURE_FAILURE=outer-health
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq active "${FIXTURE_ACTIVE[xray.service]}" || return 1
    assert_eq disabled "${FIXTURE_ENABLED[xray.service]}" || return 1
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE"
)

test_baseline_failure_can_be_retried() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    pnm_deploy_record_baseline() { printf 'SCHEMA_VERSION=' >"$PNM_TX_PATH/deployment.env"; return 73; }
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 73 "$rc" || return 1
    assert_eq 'old binary' "$(<"$root/binary")" || return 1
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    PNM_TX_ID_OVERRIDE=tx-after-baseline
    pnm_tx_begin node-init && pnm_tx_commit && pnm_tx_close
)

test_recovered_applied_record_matches_restarted_service() (
    local root rc record old_invocation=11111111111111111111111111111111
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    source "$PROJECT_ROOT/lib/render.sh"
    prepare_deployment_fixture "$root"
    PNM_XRAY_CONFIG="$root/runtime.json" FIXTURE_INVOCATION="$old_invocation"
    # Recovered listener evidence needs actual public runtime fields, rather
    # than an arbitrary string whose digest alone says nothing about its port.
    printf '%s\n' '{"inbounds":[{"port":443,"streamSettings":{"security":"reality","network":"tcp","realitySettings":{"dest":"old.example.net:443","serverNames":["old.example.net"]}}}]}' >"$PNM_XRAY_CONFIG"
    record="$PNM_STATE_DIR/cores/xray/applied.env"
    mkdir -p "${record%/*}"
    printf 'SCHEMA_VERSION=1\nCORE=xray\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=%s\n' \
        "$(pnm_tx_file_sha256 "$PNM_XRAY_CONFIG")" "$old_invocation" >"$record"
    chmod 0600 "$record"
    pnm_systemd_show_value() { printf '%s\n' "$FIXTURE_INVOCATION"; }
    fixture_xray() { FIXTURE_ACTIVE[xray.service]=active; FIXTURE_INVOCATION=22222222222222222222222222222222; }
    FIXTURE_ENABLED[xray.service]=disabled FIXTURE_FAILURE=outer-health
    if [[ "${1-}" == drift ]]; then
        fixture_outer_health() { printf '# external edit\n' >>"$record"; return 78; }
    fi
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    if [[ "${1-}" == drift ]]; then
        assert_eq 70 "$rc" || return 1
        assert_contains "$(<"$record")" '# external edit'
    else
        assert_eq 78 "$rc" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
        assert_contains "$(<"$record")" 'SERVICE_INVOCATION_ID=22222222222222222222222222222222' || return 1
        assert_eq 600 "$(stat -c '%a' "$record")" || return 1
        [[ ! -e "$PNM_STATE_DIR/cores/hysteria2/applied.env" ]]
    fi
)

test_external_applied_edit_is_retained() { test_recovered_applied_record_matches_restarted_service drift; }

check_recovered_custom_listener_port() (
    local core="${1:?Core required}" invalid="${2-}" root config record digest observed='' original_record attributes
    local _fixture_protocol _fixture_port
    local -A recovery_node=() recovery_reality=() recovery_hysteria=()
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    source "$PROJECT_ROOT/lib/render.sh"
    prepare_deployment_fixture "$root"
    # This helper tests recovery of a previously confirmed active generation.
    FIXTURE_ACTIVE[hysteria-server.service]=active
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    pnm_load_node_config recovery_node && pnm_load_reality_secret recovery_reality &&
        pnm_load_hysteria_secret recovery_hysteria || return 1
    PNM_CONFIG_DIR="$root/config"
    recovery_node[XRAY_PORT]=10443 recovery_node[HY2_PORT]=18443
    PNM_XRAY_CONFIG="$root/runtime.json" PNM_HY2_CONFIG="$root/runtime.yaml"
    pnm_render_xray_config recovery_node recovery_reality >"$PNM_XRAY_CONFIG" || return 1
    pnm_render_hysteria_config recovery_node recovery_hysteria >"$PNM_HY2_CONFIG" || return 1
    if [[ -n "$invalid" ]]; then
        if [[ "$core" == xray ]]; then
            if [[ "$invalid" == malformed ]]; then
                printf '{\n' >"$PNM_XRAY_CONFIG"
            else
                python3 - "$PNM_XRAY_CONFIG" "$invalid" <<'PY'
import json, sys
path, problem = sys.argv[1:]
with open(path) as source:
    data = json.load(source)
inbound = data['inbounds'][0]
if problem == 'port':
    inbound['port'] = 0
else:
    inbound['streamSettings']['network'] = 'udp'
with open(path, 'w') as target:
    json.dump(data, target)
PY
            fi
        elif [[ "$invalid" == malformed ]]; then
            printf 'listen: [\n' >"$PNM_HY2_CONFIG"
        else
            printf 'listen: :0\n' >"$PNM_HY2_CONFIG"
        fi
    fi
    if [[ "$core" == xray ]]; then
        config="$PNM_XRAY_CONFIG" _fixture_protocol=tcp _fixture_port=10443
        PNM_DEPLOY_XRAY_CONFIG_HASH="$(pnm_tx_file_sha256 "$config")" PNM_DEPLOY_XRAY_APPLIED=1
    else
        config="$PNM_HY2_CONFIG" _fixture_protocol=udp _fixture_port=18443
        PNM_DEPLOY_HY2_CONFIG_HASH="$(pnm_tx_file_sha256 "$config")" PNM_DEPLOY_HY2_APPLIED=1
    fi
    record="$PNM_STATE_DIR/cores/$core/applied.env"
    mkdir -p -- "${record%/*}"
    digest="$(pnm_tx_file_sha256 "$config")"
    printf 'SCHEMA_VERSION=1\nCORE=%s\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=11111111111111111111111111111111\n' "$core" "$digest" >"$record"
    chmod 0600 -- "$record"
    PNM_DEPLOY_PRIOR_APPLIED_HASH[$core]="$(pnm_tx_file_sha256 "$record")"
    PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[$core]="$(stat -c '%a:%u:%g' -- "$record")"
    original_record="$(pnm_tx_file_sha256 "$record")" attributes="$(stat -c '%a:%u:%g' -- "$record")"
    # Desired state may already be different: the recovered hash-bound runtime
    # is authoritative for the port being verified during compensation.
    declare -gA PNM_NODE_CONFIG=([XRAY_PORT]=443 [HY2_PORT]=8443)
    pnm_systemd_show_value() { printf '22222222222222222222222222222222\n'; }
    pnm_listener_present() {
        observed="$1:$2"
        [[ "$1" == "$_fixture_protocol" && "$2" == "$_fixture_port" ]]
    }
    PNM_TX_ID_OVERRIDE="tx-ports-$core"
    # This unit isolates the existing recovery helper, not the deployment
    # marker publisher (whose complete baseline is covered by other cases).
    pnm_tx_begin "core-lifecycle-$core" || return 1
    run_capture pnm_deploy_refresh_recovered_applied "$core"
    if [[ -n "$invalid" ]]; then
        assert_eq 70 "$RUN_RC" || return 1
        assert_eq '' "$observed" || return 1
        [[ "$(pnm_tx_file_sha256 "$record")" == "$original_record" &&
            "$(stat -c '%a:%u:%g' -- "$record")" == "$attributes" ]] || return 1
        pnm_tx_commit && pnm_tx_close
        return $?
    fi
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq "$_fixture_protocol:$_fixture_port" "$observed" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$config")" || return 1
    pnm_tx_commit && pnm_tx_close
)

test_recovered_xray_custom_port() { check_recovered_custom_listener_port xray; }
test_recovered_hy2_custom_port() { check_recovered_custom_listener_port hysteria2; }
test_recovered_xray_invalid_listener_is_not_promoted() {
    local variant
    for variant in malformed port transport; do
        check_recovered_custom_listener_port xray "$variant" || return 1
    done
}
test_recovered_hy2_invalid_listener_is_not_promoted() {
    local variant
    for variant in malformed port; do
        check_recovered_custom_listener_port hysteria2 "$variant" || return 1
    done
}

test_marker_sync_failure_has_preexisting_uncertainty() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    python3() {
        local script
        script="$(cat)"
        # Simulate the storage failure immediately after marker rename. No
        # post-failure uncertainty write is needed or permitted by this test.
        script="${script/temporary = None$'\n'        # Failure/raise OSError(5)$'\n'        # Failure}"
        command python3 "$@" <<<"$script"
    }
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    [[ -f "$PNM_STATE_DIR/transactions/tx-fixture/commit-uncertain.env" ]] || return 1
    unset -f python3
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE" || return 1
    run_capture pnm_node_links --address 203.0.113.10
    assert_eq 70 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT"
)

test_unowned_loaded_unit_is_not_stopped() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    source "$PROJECT_ROOT/lib/deploy.sh"
    prepare_deployment_fixture "$root"
    PNM_DEPLOY_SANDBOX_ROOT="$root"
    # Match the real CLI's IFS and the expected systemd fragment path, so only
    # ownership proof (not a missing fixture path) can reject the loaded unit.
    IFS=$'\n\t'
    mkdir -p "$root/etc/systemd/system"
    cp "$root/units/xray.service" "$root/etc/systemd/system/xray.service"
    pnm_systemd_show_value() { printf '%s/etc/systemd/system/%s\n' "$root" "$1"; }
    pnm_recovery_unit_has_no_dropins() { return 0; }
    pnm_systemctl() { printf 'unexpected mutation\n' >>"$root/mutations"; return 70; }
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    [[ ! -e "$root/mutations" && ! -e "$root/new" ]] || return 1
    assert_eq 'old binary' "$(<"$root/binary")"
)

test_unowned_binary_is_rejected_with_cli_ifs() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    source "$PROJECT_ROOT/lib/deploy.sh"
    prepare_deployment_fixture "$root"
    PNM_DEPLOY_SANDBOX_ROOT="$root"
    PNM_DEPLOY_XRAY_LOAD=not-found PNM_DEPLOY_HY2_LOAD=not-found
    mkdir -p "$root/usr/local/bin"
    printf 'unowned binary\n' >"$root/usr/local/bin/xray"
    IFS=$'\n\t'
    if pnm_deploy_validate_ownership; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 'unowned binary' "$(<"$root/usr/local/bin/xray")"
)

test_success_has_one_authoritative_commit() (
    local root
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    pnm_apply_gate_execute || return 1
    [[ -f "$PNM_STATE_DIR/transactions/tx-fixture/commit.env" ]] || return 1
    assert_eq 1 "$(find "$PNM_STATE_DIR/transactions" -mindepth 1 -maxdepth 1 -type d | wc -l)" || return 1
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 'new binary' "$(<"$root/binary")" || return 1
    assert_eq 'PNM_CONFIGURED=yes' "$(<"$PNM_CONFIG_DIR/node.conf")" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
)

test_commit_progress_failure_stays_committed() (
    local root
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    pnm_tx_journal() {
        if [[ "$1" == COMMIT ]]; then
            rm -- "$PNM_TX_PATH/journal.tsv"
            return 73
        fi
        printf '%s\t%s\t%s\n' "$(pnm_now_utc)" "$1" "${2-}" >>"$PNM_TX_PATH/journal.tsv"
    }
    pnm_apply_gate_execute || return 1
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 'new binary' "$(<"$root/binary")"
)

test_metadata_drift_is_not_overwritten() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    fixture_outer_health() { chmod 0777 "$FIXTURE_ROOT/binary"; return 78; }
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 777 "$(stat -c '%a' "$root/binary")" || return 1
    assert_eq 'new binary' "$(<"$root/binary")" || return 1
    PNM_TX_ID_OVERRIDE=tx-after-drift
    if pnm_tx_begin node-init; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc"
)

test_uncertain_commit_does_not_blindly_rollback() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    python3() {
        local script
        script="$(cat)"
        script="${script/temporary = None$'\n'        # Failure/os._exit(73)$'\n'        # Failure}"
        command python3 "$@" <<<"$script"
    }
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 'new binary' "$(<"$root/binary")" || return 1
    unset -f python3
    pnm_tx_load_for_inspect tx-fixture || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE" || return 1
    PNM_TX_ID_OVERRIDE=tx-after-uncertain
    if pnm_tx_begin node-init; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc"
)

test_interrupted_deployment_blocks_writes_and_links() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    pnm_apply_gate_begin && pnm_deploy_execute || return 1
    # Simulate lost process memory/locks without inventing a recovery action.
    PNM_TX_ACTIVE=0 PNM_DEPLOY_ACTIVE=0 PNM_APPLY_GATE_ACTIVE=0
    pnm_lock_release && pnm_lock_release || return 1
    run_capture pnm_node_links --address 203.0.113.10
    assert_eq 70 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    PNM_TX_ID_OVERRIDE=tx-after-interruption
    if pnm_tx_begin node-init; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 'new binary' "$(<"$root/binary")"
)

test_term_compensates_before_runtime_cleanup() (
    local root rc
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    prepare_deployment_fixture "$root"
    if (
        pnm_init_runtime
        pnm_apply_gate_begin && pnm_deploy_execute || exit 99
        kill -TERM "$BASHPID"
    ); then rc=0; else rc=$?; fi
    assert_eq 143 "$rc" || return 1
    assert_eq 'old binary' "$(<"$root/binary")" || return 1
    assert_eq 'PNM_CONFIGURED=no' "$(<"$PNM_CONFIG_DIR/node.conf")"
)

run_test 'outer health failure restores resources node state and both service baselines' test_late_failure_restores_resources_and_services
run_test 'phase deadline state and commit failures restore the original resources' test_each_phase_failure_restores_baseline
run_test 'active disabled baseline is restored without changing its enable state' test_active_disabled_baseline_is_restored
run_test 'baseline recording failure permits a clean retry' test_baseline_failure_can_be_retried
run_test 'recovery refreshes only previously confirmed applied evidence' test_recovered_applied_record_matches_restarted_service
run_test 'Xray recovery verifies its recovered runtime listener instead of desired defaults' test_recovered_xray_custom_port
run_test 'HY2 recovery verifies its recovered runtime listener instead of desired defaults' test_recovered_hy2_custom_port
run_test 'Xray recovery rejects malformed ports and transport without applied promotion' test_recovered_xray_invalid_listener_is_not_promoted
run_test 'HY2 recovery rejects malformed listeners without applied promotion' test_recovered_hy2_invalid_listener_is_not_promoted
run_test 'external applied edits are retained and require recovery' test_external_applied_edit_is_retained
run_test 'marker sync failure retains uncertainty persisted before publication' test_marker_sync_failure_has_preexisting_uncertainty
run_test 'unowned loaded services are rejected before any mutation' test_unowned_loaded_unit_is_not_stopped
run_test 'CLI IFS does not bypass ownership checks for an existing binary' test_unowned_binary_is_rejected_with_cli_ifs
run_test 'success publishes one authoritative deployment commit' test_success_has_one_authoritative_commit
run_test 'progress journal failure after durable commit stays committed' test_commit_progress_failure_stays_committed
run_test 'metadata drift is retained and blocks subsequent writes' test_metadata_drift_is_not_overwritten
run_test 'uncertain marker durability retains resources and requires recovery' test_uncertain_commit_does_not_blindly_rollback
run_test 'interrupted deployments block new writes and credential-bearing reads' test_interrupted_deployment_blocks_writes_and_links
run_test 'TERM compensates the live deployment before runtime cleanup' test_term_compensates_before_runtime_cleanup
finish_tests
