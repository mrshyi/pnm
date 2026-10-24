#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/adapters/systemd.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"
source <(declare -f pnm_tx_manifest_append | sed '1s/pnm_tx_manifest_append/pnm_test_real_manifest_append/')
source <(declare -f pnm_tx_record_written_metadata | sed '1s/pnm_tx_record_written_metadata/pnm_test_real_record_metadata/')

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT

prepare_restore_fixture() {
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    PNM_STATE_DIR="$fixture_root/state" PNM_LOCK_FILE="$fixture_root/lock/pnm.lock"
    PNM_XRAY_CONFIG="$fixture_root/xray.json" PNM_HY2_CONFIG="$fixture_root/hysteria.yaml"
    PNM_CORE_RESTORE_XRAY_ACTIVE=active PNM_CORE_RESTORE_XRAY_ENABLED=disabled
    PNM_CORE_RESTORE_HY2_ACTIVE=inactive PNM_CORE_RESTORE_HY2_ENABLED=enabled
    printf 'original xray\n' >"$PNM_XRAY_CONFIG"
    printf 'original hysteria\n' >"$PNM_HY2_CONFIG"
    printf 'candidate\n' >"$fixture_root/candidate"
    chmod 0751 "$PNM_XRAY_CONFIG"
    chmod 0640 "$PNM_HY2_CONFIG"
    if ((EUID == 0)); then
        command chown 65534:65534 "$PNM_XRAY_CONFIG" "$PNM_HY2_CONFIG"
    fi
    original_xray="$(stat -c '%a:%u:%g' "$PNM_XRAY_CONFIG")"
    original_hy2="$(stat -c '%a:%u:%g' "$PNM_HY2_CONFIG")"
    pnm_tx_begin core-restore || return 1
    pnm_tx_add_rollback pnm_core_restore_rollback
}

# Test the real file/directory transaction and rollback callback. Only service
# operations and named service-account ownership are simulated. Refuse any
# mutation outside private fixtures, including legacy hard-coded TLS paths.
pnm_systemd_daemon_reload() { return 0; }
pnm_systemctl() { return 0; }
pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
pnm_core_fix_owner() { chown root:xray -- "$2" && chmod 0640 -- "$2"; }
chown() {
    local target="${!#}" arg
    [[ "$target" == "$suite_root/"* ]] || return 77
    local -a args=()
    for arg in "$@"; do
        case "$arg" in root:xray|hysteria:hysteria|root:hysteria) arg="$EUID:$(id -g)" ;; esac
        args+=("$arg")
    done
    command chown "${args[@]}"
}
chmod() {
    local target="${!#}"
    [[ "$target" == "$suite_root/"* ]] || return 77
    command chmod "$@"
}

test_restore_callback_preserves_snapshot_metadata() {
    prepare_restore_fixture || return 1
    pnm_tx_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 required || return 1
    pnm_tx_write_file "$fixture_root/candidate" "$PNM_HY2_CONFIG" hysteria_config 0600 required || return 1
    pnm_tx_rollback || return 1
    assert_eq "$original_xray" "$(stat -c '%a:%u:%g' "$PNM_XRAY_CONFIG")" || return 1
    assert_eq "$original_hy2" "$(stat -c '%a:%u:%g' "$PNM_HY2_CONFIG")" || return 1
    assert_eq 'original xray' "$(<"$PNM_XRAY_CONFIG")" || return 1
    assert_eq 'original hysteria' "$(<"$PNM_HY2_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_callback_recovers_directories_after_files() {
    prepare_restore_fixture || return 1
    mkdir -m 0711 "$fixture_root/existing"
    pnm_tx_prepare_directory "$fixture_root/existing" 0755 || return 1
    pnm_tx_prepare_directory "$fixture_root/new/secrets" 0700 || return 1
    pnm_tx_write_file "$fixture_root/candidate" "$fixture_root/new/secrets/key" secret 0600 required || return 1
    pnm_tx_rollback || return 1
    assert_eq 711 "$(stat -c '%a' "$fixture_root/existing")" || return 1
    [[ ! -e "$fixture_root/new" ]] || return 1
    pnm_tx_close
}

test_restore_publication_enrolls_final_metadata() {
    local owner
    prepare_restore_fixture || return 1
    owner="$EUID:$(id -g)"
    ((EUID != 0)) || owner=65534:65534
    pnm_core_restore_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 "$owner" || return 1
    pnm_tx_verify_written_resources || return 1
    assert_eq "640:$owner" "$(stat -c '%a:%u:%g' "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_rollback || return 1
    assert_eq "$original_xray" "$(stat -c '%a:%u:%g' "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_retains_external_publication_metadata_edits() {
    local rc
    prepare_restore_fixture || return 1
    pnm_tx_manifest_append() {
        pnm_test_real_manifest_append "$@" || return $?
        [[ "$1" != APPLIED ]] || chmod 0620 "$3"
    }
    if pnm_core_restore_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 "$EUID:$(id -g)"; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    if pnm_tx_rollback; then return 1; fi
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq 620 "$(stat -c '%a' "$PNM_XRAY_CONFIG")" || return 1
    assert_eq candidate "$(<"$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_owner_failure_recovers_our_partial_change() {
    local rc
    prepare_restore_fixture || return 1
    chown() {
        command chown "$@" || return $?
        [[ "${!#}" != "$PNM_XRAY_CONFIG" || "$1" != -- ]] || return 1
    }
    if pnm_core_restore_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 "$EUID:$(id -g)"; then rc=0; else rc=$?; fi
    assert_eq 77 "$rc" || return 1
    pnm_tx_rollback || return 1
    assert_eq "$original_xray" "$(stat -c '%a:%u:%g' "$PNM_XRAY_CONFIG")" || return 1
    assert_eq 'original xray' "$(<"$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_retains_metadata_edits_during_owner_normalization() {
    local rc
    prepare_restore_fixture || return 1
    chown() {
        command chown "$@" || return $?
        [[ "${!#}" != "$PNM_XRAY_CONFIG" ]] || chmod 0620 "$PNM_XRAY_CONFIG"
    }
    if pnm_core_restore_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 "$EUID:$(id -g)"; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    if pnm_tx_rollback; then return 1; fi
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq 620 "$(stat -c '%a' "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_metadata_enrollment_checks_the_sample_it_records() {
    local rc enrollments=0
    prepare_restore_fixture || return 1
    pnm_tx_record_written_metadata() {
        if [[ "$1" == "$PNM_XRAY_CONFIG" ]]; then
            ((enrollments += 1))
            ((enrollments != 2)) || chmod 0620 "$PNM_XRAY_CONFIG"
        fi
        pnm_test_real_record_metadata "$@"
    }
    if pnm_core_restore_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 "$EUID:$(id -g)"; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    if pnm_tx_rollback; then return 1; fi
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq 620 "$(stat -c '%a' "$PNM_XRAY_CONFIG")" || return 1
    pnm_tx_close
}

test_restore_directory_policy_and_symlink_refusal() {
    local rc
    prepare_restore_fixture || return 1
    mkdir -m 0711 "$fixture_root/private" "$fixture_root/outside"
    ln -s "$fixture_root/outside" "$fixture_root/link"
    if pnm_core_restore_prepare_directory "$fixture_root/link/child" 0700; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    [[ ! -e "$fixture_root/outside/child" ]] || return 1
    if ((EUID == 0)); then
        pnm_core_restore_prepare_directory "$fixture_root/private" 0755 || return 1
        mkdir "$fixture_root/foreign"
        command chown 65534:65534 "$fixture_root/foreign"
        if pnm_core_restore_prepare_directory "$fixture_root/foreign" 0700; then rc=0; else rc=$?; fi
        assert_eq 77 "$rc" || return 1
        assert_eq 65534:65534 "$(stat -c '%u:%g' "$fixture_root/foreign")" || return 1
    fi
    pnm_tx_rollback || return 1
    assert_eq 711 "$(stat -c '%a' "$fixture_root/private")" || return 1
    pnm_tx_close
}

test_restore_applied_records_and_directories_are_compensated() {
    local core config
    prepare_restore_fixture || return 1
    for core in xray hysteria2; do
        config="$PNM_XRAY_CONFIG"
        [[ "$core" == xray ]] || config="$PNM_HY2_CONFIG"
        pnm_core_record_applied_config "$core" "$config" "$fixture_root" || return 1
    done
    pnm_tx_verify_written_resources || return 1
    pnm_tx_rollback || return 1
    [[ ! -e "$PNM_STATE_DIR/cores" ]] || return 1
    pnm_tx_close
}

test_restore_stops_failed_unit_before_file_recovery() {
    local reset_mode="${1:-success}" rc
    local xray_state=active hy2_state=failed xray_enabled=enabled hy2_enabled=enabled
    prepare_restore_fixture || return 1
    PNM_CORE_RESTORE_STARTED=1
    PNM_CORE_RESTORE_XRAY_LOAD=loaded PNM_CORE_RESTORE_HY2_LOAD=loaded
    PNM_CORE_RESTORE_XRAY_ACTIVE=active PNM_CORE_RESTORE_HY2_ACTIVE=active
    PNM_CORE_RESTORE_XRAY_ENABLED=enabled PNM_CORE_RESTORE_HY2_ENABLED=enabled
    pnm_tx_write_file "$fixture_root/candidate" "$PNM_XRAY_CONFIG" xray_config 0640 required || return 1
    pnm_systemd_load_state() { printf 'loaded\n'; }
    pnm_systemd_active_state() {
        if [[ "$1" == xray.service ]]; then printf '%s\n' "$xray_state"; else printf '%s\n' "$hy2_state"; fi
    }
    pnm_systemd_enabled_state() {
        if [[ "$1" == xray.service ]]; then printf '%s\n' "$xray_enabled"; else printf '%s\n' "$hy2_enabled"; fi
    }
    pnm_systemctl() {
        printf '%s %s\n' "$1" "$2" >>"$fixture_root/service-calls"
        case "$1:$2" in
            stop:xray.service) xray_state=inactive ;;
            stop:hysteria-server.service) : ;; # systemd retains the failed state after stop.
            reset-failed:hysteria-server.service)
                [[ "$reset_mode" != error ]] || return 1
                [[ "$reset_mode" != unchanged ]] || return 0
                hy2_state=inactive ;;
            disable:xray.service) xray_enabled=disabled ;;
            disable:hysteria-server.service) hy2_enabled=disabled ;;
            enable:xray.service) xray_enabled=enabled ;;
            enable:hysteria-server.service) hy2_enabled=enabled ;;
            restart:xray.service) xray_state=active ;;
            restart:hysteria-server.service) hy2_state=active ;;
            *) return 1 ;;
        esac
    }
    pnm_core_resolve() {
        PNM_CORE_UNIT=xray.service
        [[ "$1" == xray ]] || PNM_CORE_UNIT=hysteria-server.service
    }
    pnm_core_recover_applied() { return 0; }
    if pnm_tx_rollback; then rc=0; else rc=$?; fi
    if [[ "$reset_mode" == success ]]; then
        assert_eq 0 "$rc" || return 1
        assert_eq 'original xray' "$(<"$PNM_XRAY_CONFIG")" || return 1
        assert_eq active "$hy2_state" || return 1
        assert_eq enabled "$hy2_enabled" || return 1
        assert_contains "$(<"$fixture_root/service-calls")" 'reset-failed hysteria-server.service' || return 1
    else
        assert_eq 70 "$rc" || return 1
        assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
        assert_eq candidate "$(<"$PNM_XRAY_CONFIG")" || return 1
    fi
    pnm_tx_close
}

run_test 'restore recovers a stopped unit that retains failed state' test_restore_stops_failed_unit_before_file_recovery
test_restore_failed_reset_refusal() { test_restore_stops_failed_unit_before_file_recovery error; }
test_restore_failed_reset_verification() { test_restore_stops_failed_unit_before_file_recovery unchanged; }
run_test 'restore retains uncertainty when failed-state reset fails' test_restore_failed_reset_refusal
run_test 'restore verifies inactivity after failed-state reset' test_restore_failed_reset_verification
run_test 'restore compensation preserves original file ownership and modes' test_restore_callback_preserves_snapshot_metadata
run_test 'restore compensation recovers directories after removing new files' test_restore_callback_recovers_directories_after_files
run_test 'restore publication enrolls final owner and mode' test_restore_publication_enrolls_final_metadata
run_test 'restore retains external publication metadata edits' test_restore_retains_external_publication_metadata_edits
run_test 'restore compensates ownership changes even when chown reports failure' test_restore_owner_failure_recovers_our_partial_change
run_test 'restore retains external metadata edits during owner normalization' test_restore_retains_metadata_edits_during_owner_normalization
run_test 'restore metadata enrollment validates its own sampled attributes' test_restore_metadata_enrollment_checks_the_sample_it_records
run_test 'restore refuses symlink and foreign-owned private directories' test_restore_directory_policy_and_symlink_refusal
run_test 'restore compensates applied records and their new directories' test_restore_applied_records_and_directories_are_compensated
finish_tests
