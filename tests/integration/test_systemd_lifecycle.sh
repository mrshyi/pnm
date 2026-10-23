#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${PNM_RUN_SYSTEMD_TESTS:-0}" == 1 ]] || {
    printf 'Opt in with sudo make test-systemd.\n' >&2; exit 64;
}
((EUID == 0)) || { printf 'Isolated systemd fixtures require root.\n' >&2; exit 77; }
SYSTEMCTL="$(command -v systemctl)" || exit 69
case "$("$SYSTEMCTL" is-system-running 2>/dev/null || true)" in running|degraded) ;; *) exit 69 ;; esac
[[ -d /run/systemd/system && ! -L /run/systemd/system &&
    -d /etc/systemd/system/multi-user.target.wants && ! -L /etc/systemd/system/multi-user.target.wants &&
    -x /usr/bin/sleep ]] || exit 69
id nobody >/dev/null || exit 69

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/adapters/systemd.sh"
source "$PROJECT_ROOT/lib/lifecycle.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"

umask 077
IFS= read -r fixture_uuid </proc/sys/kernel/random/uuid
[[ "$fixture_uuid" =~ ^[a-f0-9-]{36}$ ]] || exit 69
fixture_root="$(mktemp -d /var/tmp/pnm-systemd.XXXXXXXX)"
fixture_identity="$(stat -c '%d:%i' "$fixture_root")"
PNM_SYSTEMCTL_BIN="$SYSTEMCTL"
unit_prefix="pnm-accept-$fixture_uuid"
declare -A fixture_units=([xray.service]="$unit_prefix-xray.service" [hysteria-server.service]="$unit_prefix-hy2.service")
declare -A created_units=()

real_systemctl() { command "$SYSTEMCTL" --no-ask-password --no-pager "$@"; }

cleanup() {
    local rc=$1 cleanup_rc=0 unit file digest active
    trap - EXIT
    trap '' INT TERM
    for unit in "${!created_units[@]}"; do
        file="/run/systemd/system/$unit"
        if [[ "$unit" != "$unit_prefix-xray.service" && "$unit" != "$unit_prefix-hy2.service" ]] ||
            [[ ! -f "$file" || -L "$file" || "$(stat -c '%a:%u' "$file")" != 644:0 ]]; then
            printf 'Changed test unit retained for inspection.\n' >&2; cleanup_rc=70; continue
        fi
        digest="$(sha256sum -- "$file")"; digest=${digest%% *}
        if [[ "$digest" != "${created_units[$unit]}" ]]; then
            printf 'Edited test unit retained for inspection.\n' >&2; cleanup_rc=70; continue
        fi
        if ! real_systemctl stop "$unit"; then cleanup_rc=70; continue; fi
        active="$(real_systemctl show "$unit" --property ActiveState --value)" || { cleanup_rc=70; continue; }
        [[ "$active" == inactive || "$active" == failed ]] || { cleanup_rc=70; continue; }
        if ! real_systemctl disable "$unit"; then cleanup_rc=70; continue; fi
        real_systemctl reset-failed "$unit" >/dev/null 2>&1 || true
        rm -f -- "$file" || cleanup_rc=70
        [[ ! -e "/etc/systemd/system/multi-user.target.wants/$unit" &&
            ! -L "/etc/systemd/system/multi-user.target.wants/$unit" ]] || cleanup_rc=70
    done
    if ((${#created_units[@]} > 0)); then real_systemctl daemon-reload || cleanup_rc=70; fi
    ((rc != 0 || cleanup_rc == 0)) || rc="$cleanup_rc"
    if ((rc == 0)) && [[ "$fixture_root" == /var/tmp/pnm-systemd.* && "$(dirname -- "$fixture_root")" == /var/tmp &&
        -d "$fixture_root" && ! -L "$fixture_root" && "$(stat -c '%a:%u' "$fixture_root")" == 700:0 &&
        "$(stat -c '%d:%i' "$fixture_root")" == "$fixture_identity" ]]; then
        rm -rf -- "$fixture_root" || rc=70
    else
        ((rc != 0)) || rc=70
        printf 'Private fixture evidence retained: %s\n' "$fixture_root" >&2
    fi
    exit "$rc"
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

create_test_units() {
    local unit file load text digest
    for unit in "${fixture_units[@]}"; do
        file="/run/systemd/system/$unit"
        [[ ! -e "$file" && ! -L "$file" && ! -e "/etc/systemd/system/$unit" && ! -L "/etc/systemd/system/$unit" ]] || return 73
        load="$(real_systemctl show "$unit" --property LoadState --value)" || return 69
        [[ "$load" == not-found ]] || return 73
    done
    text=$'[Unit]\nDescription=PNM isolated lifecycle acceptance fixture\n[Service]\nType=exec\nUser=nobody\nExecStart=/usr/bin/sleep infinity\nNoNewPrivileges=yes\nCapabilityBoundingSet=\nAmbientCapabilities=\nTimeoutStartSec=10\nTimeoutStopSec=5\n[Install]\nWantedBy=multi-user.target\n'
    digest="$(printf '%s' "$text" | sha256sum)"; digest=${digest%% *}
    for unit in "${fixture_units[@]}"; do
        file="/run/systemd/system/$unit"
        created_units[$unit]=$digest
        (umask 022; set -o noclobber; printf '%s' "$text" >"$file") || return 73
    done
    real_systemctl daemon-reload
}

# Only this I/O boundary maps Core identities into the owned test namespace.
# systemd operations and observations below are real, not mocked responses.
pnm_systemctl() {
    local action=${1:?action required} unit mapped property
    shift
    case "$action" in
        daemon-reload) (($# == 0)) || return 64; real_systemctl daemon-reload; return $? ;;
        show)
            (($# == 4)) && [[ "$2" == --property && "$4" == --value ]] || return 64
            unit=$1 property=$3
            case "$property" in LoadState|ActiveState|SubState|InvocationID|MainPID|User) ;; *) return 77 ;; esac
            ;;
        is-enabled|enable|disable|start|stop|restart) (($# == 1)) || return 64; unit=$1 ;;
        *) return 77 ;;
    esac
    case "$unit" in xray.service|hysteria-server.service) mapped=${fixture_units[$unit]} ;; *) return 77 ;; esac
    [[ -n "${created_units[$mapped]-}" ]] || return 77
    if [[ "$action" == show ]]; then
        real_systemctl show "$mapped" --property "$property" --value
    else
        real_systemctl "$action" "$mapped"
    fi
}

PNM_STATE_DIR="$fixture_root/state" PNM_LOCK_FILE="$fixture_root/pnm.lock"
PNM_XRAY_CONFIG="$fixture_root/xray.json" PNM_HY2_CONFIG="$fixture_root/hy2.yaml"
mkdir -m 0700 "$PNM_STATE_DIR"
printf '{}\n' >"$PNM_XRAY_CONFIG"
printf 'fixture: true\n' >"$PNM_HY2_CONFIG"

seed_applied_fixture() {
    local core=$1 config=$2 unit=$3 directory="$PNM_STATE_DIR/cores/$1"
    pnm_mkdir_mode 0700 "$directory" || return $?
    printf 'SCHEMA_VERSION=1\nCORE=%s\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=%s\n' \
        "$core" "$(pnm_tx_file_sha256 "$config")" "$(pnm_systemd_show_value "$unit" InvocationID)" >"$directory/applied.env" || return 73
    chmod 0600 "$directory/applied.env" || return 77
}
assert_service_policy() {
    assert_eq "$2" "$(pnm_systemd_active_state "$1")" || return 1
    assert_eq "$3" "$(pnm_systemd_enabled_state "$1")"
}

test_real_activation() {
    pnm_core_lifecycle_apply xray || return 1
    pnm_core_lifecycle_apply hysteria2 || return 1
    assert_service_policy xray.service active enabled || return 1
    assert_service_policy hysteria-server.service active enabled || return 1
    assert_eq nobody "$(pnm_systemd_show_value xray.service User)"
}
test_real_restart_retains_peer_and_binds_applied_invocation() {
    local previous peer current
    seed_applied_fixture xray "$PNM_XRAY_CONFIG" xray.service || return 1
    previous="$(pnm_systemd_show_value xray.service InvocationID)"
    peer="$(pnm_systemd_show_value hysteria-server.service InvocationID)"
    pnm_core_restart xray || return 1
    current="$(pnm_systemd_show_value xray.service InvocationID)"
    [[ "$current" =~ ^[a-f0-9]{32}$ && "$current" != "$previous" ]] || return 1
    assert_eq "$peer" "$(pnm_systemd_show_value hysteria-server.service InvocationID)" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")"
}
test_real_inactive_disabled_recovery() {
    pnm_systemctl stop xray.service && pnm_systemctl disable xray.service || return 1
    pnm_core_lifecycle_health_step() { return 78; }
    run_capture pnm_core_lifecycle_apply xray
    assert_eq 78 "$RUN_RC" || return 1
    assert_service_policy xray.service inactive disabled
}
test_real_active_disabled_recovery() {
    pnm_systemctl start xray.service && pnm_systemctl disable xray.service || return 1
    pnm_core_lifecycle_health_step() { return 78; }
    run_capture pnm_core_lifecycle_apply xray
    assert_eq 78 "$RUN_RC" || return 1
    assert_service_policy xray.service active disabled
}
test_real_term_recovery() {
    pnm_systemctl stop xray.service && pnm_systemctl disable xray.service || return 1
    term_child() (
        pnm_init_runtime
        pnm_core_lifecycle_health_step() { kill -TERM "$BASHPID"; }
        pnm_core_lifecycle_apply xray
    )
    run_capture term_child
    assert_eq 143 "$RUN_RC" || return 1
    assert_service_policy xray.service inactive disabled || return 1
    assert_service_policy hysteria-server.service active enabled || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_real_config_compensation_preserves_disabled_policy() {
    pnm_systemctl start xray.service && pnm_systemctl disable xray.service || return 1
    pnm_core_resolve xray || return 1
    pnm_core_lifecycle_snapshot xray || return 1
    printf 'candidate\n' >"$fixture_root/candidate"
    pnm_tx_begin core-config-xray || return 1
    pnm_tx_add_rollback pnm_core_restore_config || return 1
    pnm_tx_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" core_config 0640 required || return 1
    pnm_tx_rollback || return 1
    pnm_tx_close || return 1
    assert_eq '{}' "$(<"$PNM_XRAY_CONFIG")" || return 1
    assert_service_policy xray.service active disabled
}

test_real_update_compensation_preserves_disabled_policy() {
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    pnm_systemctl start xray.service && pnm_systemctl disable xray.service || return 1
    pnm_core_resolve xray || return 1
    pnm_core_lifecycle_snapshot xray || return 1
    seed_applied_fixture xray "$PNM_XRAY_CONFIG" xray.service || return 1
    pnm_tx_begin core-update-xray || return 1
    pnm_core_capture_applied || return 1
    pnm_tx_add_rollback pnm_core_update_rollback || return 1
    pnm_tx_rollback || return 1
    pnm_tx_close || return 1
    assert_service_policy xray.service active disabled || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")"
}

test_real_apply_failure_recovers_confirmed_invocation() {
    local original peer temporary
    pnm_init_runtime
    PNM_CONFIG_DIR="$fixture_root/apply-config"
    mkdir -m 0700 "$PNM_CONFIG_DIR"
    cp -R "$TEST_ROOT/fixtures/config-secrets/." "$PNM_CONFIG_DIR/"
    PNM_XRAY_BIN="$fixture_root/core-validation-stub"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$PNM_XRAY_BIN"
    chmod 0700 "$PNM_XRAY_BIN"
    pnm_node_xray_reality_public_key() { return 0; }
    pnm_core_fix_owner() { return 0; }
    pnm_systemd_unit_healthy() { return 78; } # Inject forward health failure.
    pnm_systemctl enable xray.service && pnm_systemctl start xray.service || return 1
    seed_applied_fixture xray "$PNM_XRAY_CONFIG" xray.service || return 1
    original="$(pnm_tx_file_sha256 "$PNM_XRAY_CONFIG")"
    peer="$(pnm_systemd_show_value hysteria-server.service InvocationID)"
    run_capture pnm_core_apply_config xray
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq "$original" "$(pnm_tx_file_sha256 "$PNM_XRAY_CONFIG")" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    assert_eq 0 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq "$peer" "$(pnm_systemd_show_value hysteria-server.service InvocationID)" || return 1
    assert_service_policy xray.service active enabled || return 1
    pnm_cleanup || return 1
    for temporary in "${PNM_CLEANUP_PATHS[@]}"; do
        [[ ! -e "$temporary" && ! -L "$temporary" ]] || return 1
    done
}

create_test_units
run_test 'real systemd activates both isolated nobody fixtures' test_real_activation
run_test 'real restart changes its invocation and preserves the peer' test_real_restart_retains_peer_and_binds_applied_invocation
run_test 'real lifecycle failure restores inactive and disabled' test_real_inactive_disabled_recovery
run_test 'real lifecycle failure preserves active but disabled' test_real_active_disabled_recovery
run_test 'TERM compensates real isolated lifecycle state and releases its lock' test_real_term_recovery
run_test 'real config compensation accepts the original disabled policy' test_real_config_compensation_preserves_disabled_policy
run_test 'real update compensation refreshes evidence with disabled policy' test_real_update_compensation_preserves_disabled_policy
run_test 'real config apply failure rebinds confirmed applied InvocationID' test_real_apply_failure_recovers_confirmed_invocation
finish_tests
