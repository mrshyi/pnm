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

run_test 'Core lifecycle commits independently after health validation' test_lifecycle_success_is_independent
run_test 'Core lifecycle failure compensates the same Core only' test_lifecycle_failure_restores_previous_state
run_test 'Core lifecycle dry-run does not mutate systemd state' test_lifecycle_dry_run_does_not_mutate
finish_tests
