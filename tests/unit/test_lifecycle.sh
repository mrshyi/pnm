#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/lock.sh
source "$PNM_LIB_DIR/lock.sh"
# shellcheck source=../../lib/transaction.sh
source "$PNM_LIB_DIR/transaction.sh"
# shellcheck source=../../adapters/systemd.sh
source "$PNM_ADAPTER_DIR/systemd.sh"
# shellcheck source=../../lib/lifecycle.sh
source "$PNM_LIB_DIR/lifecycle.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

make_fake_systemctl() {
    local destination="${1:?fake systemctl destination required}"

    cat >"$destination" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state_file="${FAKE_SYSTEMCTL_STATE:?state file required}"
log_file="${FAKE_SYSTEMCTL_LOG:?log file required}"
printf '%s\n' "$*" >>"$log_file"
get_state() {
    awk -F= -v wanted="$1" '$1 == wanted {print $2; exit}' "$state_file"
}
set_state() {
    local key="$1" value="$2" temp
    temp="$(mktemp)"
    awk -F= -v wanted="$key" -v replacement="$value" '$1 == wanted {print wanted "=" replacement; found=1; next} {print} END {if (!found) print wanted "=" replacement}' "$state_file" >"$temp"
    mv -f -- "$temp" "$state_file"
}
[[ "${FAKE_NOOP_ACTION:-}" != "${1-}" ]] || exit 0
case "${1-}" in
    show)
        case "${4-}" in
            LoadState) printf 'loaded\n' ;;
            ActiveState) printf '%s\n' "$(get_state active)" ;;
            SubState) [[ "$(get_state active)" == active ]] && printf 'running\n' || printf 'dead\n' ;;
            *) exit 1 ;;
        esac
        ;;
    is-enabled) printf '%s\n' "$(get_state enabled)" ;;
    daemon-reload) : ;;
    enable) set_state enabled enabled ;;
    disable) set_state enabled disabled ;;
    start)
        [[ "${FAKE_START_FAIL:-0}" == 1 ]] && exit 23
        set_state active active
        ;;
    stop) set_state active inactive ;;
    *) exit 1 ;;
esac
EOF
    chmod 0755 -- "$destination"
}

prepare_lifecycle() {
    local temp_dir="$1"

    PNM_TEST_SYSTEMD=1
    PNM_SYSTEMCTL_BIN="$temp_dir/systemctl"
    FAKE_SYSTEMCTL_STATE="$temp_dir/state"
    FAKE_SYSTEMCTL_LOG="$temp_dir/log"
    export FAKE_SYSTEMCTL_STATE FAKE_SYSTEMCTL_LOG
    printf '%s\n' 'active=inactive' 'enabled=disabled' >"$FAKE_SYSTEMCTL_STATE"
    : >"$FAKE_SYSTEMCTL_LOG"
    make_fake_systemctl "$PNM_SYSTEMCTL_BIN"
    PNM_STATE_DIR="$temp_dir/pnm-state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_DRY_RUN=0
}

test_lifecycle_success_is_independent() {
    local temp_dir journal receipt
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_TX_ID_OVERRIDE='lifecycle-success'
    pnm_core_lifecycle_apply xray || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "active" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == active ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "enabled" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == enabled ]] || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_STATE_DIR/transactions/lifecycle-success/journal.tsv"
    receipt="$PNM_STATE_DIR/transactions/lifecycle-success/core-state.env"
    assert_contains "$(<"$journal")" $'COMMIT\t'
    assert_contains "$(<"$receipt")" 'CORE=xray'
    assert_contains "$(<"$receipt")" 'UNIT=xray.service'
    pnm_tx_load_for_inspect lifecycle-success || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq xray "$PNM_TX_INSPECT_CORE" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq inactive "$PNM_TX_INSPECT_PRE_ACTIVE" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq disabled "$PNM_TX_INSPECT_PRE_ENABLED" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$FAKE_SYSTEMCTL_LOG")" 'daemon-reload'
    assert_contains "$(<"$FAKE_SYSTEMCTL_LOG")" 'start xray.service'
    rm -rf -- "$temp_dir"
}

test_lifecycle_failure_restores_previous_state() {
    local temp_dir rc journal
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_TX_ID_OVERRIDE='lifecycle-failure'
    FAKE_START_FAIL=1
    export FAKE_START_FAIL
    if pnm_core_lifecycle_apply hysteria2; then rc=0; else rc=$?; fi
    journal="$PNM_STATE_DIR/transactions/lifecycle-failure/journal.tsv"
    [[ "$rc" == 70 ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "active" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == inactive ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "enabled" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == disabled ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_not_contains "$(<"$journal")" $'COMMIT\t'
    assert_contains "$(<"$journal")" $'ROLLBACK_DONE\t'
    rm -rf -- "$temp_dir"
}

test_lifecycle_dry_run_does_not_mutate() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_TX_ID_OVERRIDE='lifecycle-dry-run'
    PNM_DRY_RUN=1
    pnm_core_lifecycle_apply xray || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "active" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == inactive ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(awk -F= '$1 == "enabled" {print $2}' "$FAKE_SYSTEMCTL_STATE")" == disabled ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_not_contains "$(<"$FAKE_SYSTEMCTL_LOG")" 'daemon-reload'
    assert_not_contains "$(<"$FAKE_SYSTEMCTL_LOG")" ' start '
    rm -rf -- "$temp_dir"
}

test_recovery_rejects_successful_controls_without_effect() {
    local action temp_dir rc
    for action in start stop enable disable; do
        temp_dir="$(mktemp -d)"
        prepare_lifecycle "$temp_dir"
        PNM_LIFECYCLE_UNIT=xray.service
        case "$action" in
            start) PNM_LIFECYCLE_PRE_ACTIVE=active PNM_LIFECYCLE_PRE_ENABLED=disabled ;;
            enable) PNM_LIFECYCLE_PRE_ACTIVE=inactive PNM_LIFECYCLE_PRE_ENABLED=enabled ;;
            stop|disable)
                printf 'active=active\nenabled=enabled\n' >"$FAKE_SYSTEMCTL_STATE"
                if [[ "$action" == stop ]]; then
                    PNM_LIFECYCLE_PRE_ACTIVE=inactive PNM_LIFECYCLE_PRE_ENABLED=enabled
                else
                    PNM_LIFECYCLE_PRE_ACTIVE=active PNM_LIFECYCLE_PRE_ENABLED=disabled
                fi
                ;;
        esac
        export FAKE_NOOP_ACTION="$action"
        run_capture pnm_core_lifecycle_restore
        rc=$RUN_RC
        rm -rf -- "$temp_dir"
        assert_eq 70 "$rc" "successful $action without baseline recovery must fail" || return 1
    done
}

test_recovery_observes_exact_supported_policy_pairs() {
    local active enabled temp_dir actual_active actual_enabled rc
    for active in active inactive; do
        for enabled in enabled disabled; do
            temp_dir="$(mktemp -d)"
            prepare_lifecycle "$temp_dir"
            PNM_LIFECYCLE_UNIT=xray.service
            PNM_LIFECYCLE_PRE_ACTIVE=$active PNM_LIFECYCLE_PRE_ENABLED=$enabled
            run_capture pnm_core_lifecycle_restore
            rc=$RUN_RC
            actual_active="$(pnm_systemd_active_state xray.service)"
            actual_enabled="$(pnm_systemd_enabled_state xray.service)"
            rm -rf -- "$temp_dir"
            assert_eq 0 "$rc" || return 1
            assert_eq "$active" "$actual_active" || return 1
            assert_eq "$enabled" "$actual_enabled" || return 1
        done
    done
}

test_recovery_rejects_final_failed_query_with_valid_output() {
    local temp_dir rc after_reload=0
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_LIFECYCLE_UNIT=xray.service
    PNM_LIFECYCLE_PRE_ACTIVE=active PNM_LIFECYCLE_PRE_ENABLED=disabled
    pnm_systemd_active_state() { printf 'active\n'; ((after_reload == 0)); }
    pnm_systemd_daemon_reload() { after_reload=1; }
    run_capture pnm_core_lifecycle_restore
    rc=$RUN_RC
    rm -rf -- "$temp_dir"
    assert_eq 70 "$rc"
}

test_recovery_rejects_invalid_baseline_before_controls() {
    local temp_dir rc log
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_LIFECYCLE_UNIT=xray.service
    PNM_LIFECYCLE_PRE_ACTIVE=unknown PNM_LIFECYCLE_PRE_ENABLED=disabled
    run_capture pnm_core_lifecycle_restore
    rc=$RUN_RC log="$(<"$FAKE_SYSTEMCTL_LOG")"
    rm -rf -- "$temp_dir"
    assert_eq 70 "$rc" || return 1
    assert_eq '' "$log" 'invalid baseline must not control services'
}

test_ineffective_compensation_keeps_transaction_uncertain() {
    local temp_dir rc recovery journal
    temp_dir="$(mktemp -d)"
    prepare_lifecycle "$temp_dir"
    PNM_TX_ID_OVERRIDE=ineffective-recovery
    export FAKE_START_FAIL=1 FAKE_NOOP_ACTION=disable
    run_capture pnm_core_lifecycle_apply hysteria2
    rc=$RUN_RC recovery=$PNM_TX_RECOVERY_REQUIRED
    journal="$(<"$PNM_STATE_DIR/transactions/ineffective-recovery/journal.tsv")"
    rm -rf -- "$temp_dir"
    assert_eq 70 "$rc" || return 1
    assert_eq 1 "$recovery" || return 1
    assert_contains "$journal" $'RECOVERY_REQUIRED\t' || return 1
    assert_not_contains "$journal" $'ROLLBACK_COMPLETE\t'
}

test_verified_stop_normalizes_only_observed_failure() (
    local scenario current controls rc
    for scenario in inactive failed stop-error reset-error query-error ineffective reset-ineffective final-query-error; do
        current=active controls=''
        pnm_systemctl() {
            controls+="$1,"
            case "$1" in
                stop)
                    [[ "$scenario" != stop-error ]] || return 1
                    case "$scenario" in failed|reset-error|reset-ineffective|final-query-error) current=failed ;; ineffective) current=active ;; *) current=inactive ;; esac
                    ;;
                reset-failed) [[ "$scenario" != reset-error ]] || return 1; [[ "$scenario" == reset-ineffective ]] || current=inactive ;;
                *) return 77 ;;
            esac
        }
        pnm_systemd_active_state() {
            [[ "$scenario" != query-error ]] || return 1
            printf '%s\n' "$current"
            [[ "$scenario" != final-query-error || "$controls" != 'stop,reset-failed,' ]]
        }
        if pnm_systemd_stop_verified xray.service; then rc=0; else rc=$?; fi
        case "$scenario" in
            inactive) assert_eq 0 "$rc" && assert_eq 'stop,' "$controls" || return 1 ;;
            failed) assert_eq 0 "$rc" && assert_eq 'stop,reset-failed,' "$controls" || return 1 ;;
            *) assert_eq 70 "$rc" || return 1 ;;
        esac
    done
)

run_test 'verified stop normalizes failed state and rejects ineffective or failed controls' test_verified_stop_normalizes_only_observed_failure
run_test 'lifecycle recovery rejects successful controls without effect' test_recovery_rejects_successful_controls_without_effect
run_test 'lifecycle recovery accepts all exact supported policies' test_recovery_observes_exact_supported_policy_pairs
run_test 'lifecycle recovery rejects failed final query with matching stdout' test_recovery_rejects_final_failed_query_with_valid_output
run_test 'lifecycle recovery rejects invalid baseline before controls' test_recovery_rejects_invalid_baseline_before_controls
run_test 'ineffective lifecycle compensation retains recovery-required' test_ineffective_compensation_keeps_transaction_uncertain
run_test 'Core lifecycle commits independently after health validation' test_lifecycle_success_is_independent
run_test 'Core lifecycle failure compensates the same Core only' test_lifecycle_failure_restores_previous_state
run_test 'Core lifecycle dry-run does not mutate systemd state' test_lifecycle_dry_run_does_not_mutate
finish_tests
