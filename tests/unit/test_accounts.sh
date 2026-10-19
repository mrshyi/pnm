#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
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
# shellcheck source=../../lib/accounts.sh
source "$PNM_LIB_DIR/accounts.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

ACCOUNT_USERDEL_FAIL=0
ACCOUNT_GROUPDEL_CALLS=0
ACCOUNT_USERDEL_CALLS=0
ACCOUNT_XRAY_PASSWD_GID=999
ACCOUNT_XRAY_GROUP_GID=999
ACCOUNT_XRAY_HOME=/nonexistent
ACCOUNT_XRAY_SHELL=/usr/sbin/nologin
ACCOUNT_HYSTERIA_PASSWD_GID=998
ACCOUNT_HYSTERIA_GROUP_GID=998
ACCOUNT_HYSTERIA_HOME=/nonexistent
ACCOUNT_HYSTERIA_SHELL=/usr/sbin/nologin

pnm_require_root() { return 0; }
pnm_command_exists() { return 0; }
getent() {
    case "${1-}" in
        passwd)
            case "${2-}" in
                xray) printf 'xray:x:999:%s:Xray service:%s:%s\n' "$ACCOUNT_XRAY_PASSWD_GID" "$ACCOUNT_XRAY_HOME" "$ACCOUNT_XRAY_SHELL" ;;
                hysteria) printf 'hysteria:x:998:%s:Hysteria service:%s:%s\n' "$ACCOUNT_HYSTERIA_PASSWD_GID" "$ACCOUNT_HYSTERIA_HOME" "$ACCOUNT_HYSTERIA_SHELL" ;;
                '') printf 'other:x:1000:999:Other account:/home/other:/bin/bash\n' ;;
                *) return 2 ;;
            esac
            ;;
        group)
            case "${2-}" in
                xray) printf 'xray:x:%s:\n' "$ACCOUNT_XRAY_GROUP_GID" ;;
                hysteria) printf 'hysteria:x:%s:\n' "$ACCOUNT_HYSTERIA_GROUP_GID" ;;
                *) return 2 ;;
            esac
            ;;
        *) return 2 ;;
    esac
}
ps() { return 1; }
userdel() { ACCOUNT_USERDEL_CALLS=$((ACCOUNT_USERDEL_CALLS + 1)); ((ACCOUNT_USERDEL_FAIL == 0)); }
groupdel() { ACCOUNT_GROUPDEL_CALLS=$((ACCOUNT_GROUPDEL_CALLS + 1)); return 0; }
accounts_test_step_failure() { return 69; }

test_service_account_policy_is_fixed() {
    assert_eq 'xray|/nonexistent|/usr/sbin/nologin' "$(pnm_service_account_policy xray)" || return 1
    assert_eq 'hysteria|/nonexistent|/usr/sbin/nologin' "$(pnm_service_account_policy hysteria)"
}

test_unknown_service_account_is_rejected() {
    local rc
    if pnm_service_account_policy root; then rc=0; else rc=$?; fi
    assert_eq 1 "$rc"
}

test_valid_existing_accounts_are_reused() {
    local rc account expected
    for account in xray hysteria; do
        case "$account" in
            xray) expected='xray|999|999|/nonexistent|/usr/sbin/nologin' ;;
            hysteria) expected='hysteria|998|998|/nonexistent|/usr/sbin/nologin' ;;
        esac
        pnm_service_account_existing_valid "$account" || return 1
        assert_eq "$expected" "$(pnm_service_account_state "$account")" || return 1
    done
    pnm_service_accounts_reset
    if pnm_service_accounts_step; then rc=0; else rc=$?; fi
    assert_eq 0 "$rc" || return 1
    assert_eq 0 "${#PNM_ACCOUNTS_CREATED_USERS[@]}" || return 1
    assert_eq 0 "${#PNM_ACCOUNTS_CREATED_GROUPS[@]}"
}

test_existing_accounts_reject_home_shell_and_gid_mismatches() {
    local account prefix field variable expected expected_gid rc
    for account in xray hysteria; do
        prefix="${account^^}"
        if [[ "$account" == xray ]]; then expected_gid=999; else expected_gid=998; fi
        for field in HOME SHELL PASSWD_GID; do
            variable="ACCOUNT_${prefix}_${field}"
            case "$field" in
                HOME) expected=/nonexistent; printf -v "$variable" '%s' /wrong-home ;;
                SHELL) expected=/usr/sbin/nologin; printf -v "$variable" '%s' /bin/false ;;
                PASSWD_GID) expected="$expected_gid"; printf -v "$variable" '%s' 12345 ;;
            esac
            if pnm_service_account_existing_valid "$account"; then rc=0; else rc=$?; fi
            [[ "$rc" -ne 0 ]] || { printf 'expected %s mismatch to be rejected\n' "$field" >&2; return 1; }
            printf -v "$variable" '%s' "$expected"
        done
    done
}

test_failed_user_delete_preserves_group_and_tracking() {
    local rc temp_dir receipt journal userdel_calls
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='account-rollback-retains-receipt'
    PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    receipt="$PNM_TX_PATH/accounts.tsv"
    journal="$PNM_TX_PATH/journal.tsv"
    PNM_ACCOUNTS_CREATED_USERS=(xray)
    PNM_ACCOUNTS_CREATED_GROUPS=(xray)
    pnm_tx_record_account INTENT group xray && pnm_tx_record_account APPLIED group xray || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_record_account INTENT user xray && pnm_tx_record_account APPLIED user xray || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    ACCOUNT_USERDEL_FAIL=1
    ACCOUNT_GROUPDEL_CALLS=0
    ACCOUNT_USERDEL_CALLS=0
    pnm_tx_add_rollback pnm_service_accounts_rollback || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_run stage_assets accounts_test_step_failure; then rc=0; else rc=$?; fi
    assert_eq 69 "$rc" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 69 "$PNM_TX_STEP_FAILURE_RC" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 70 "$PNM_TX_ROLLBACK_FAILURE_RC" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$ACCOUNT_GROUPDEL_CALLS" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "${#PNM_ACCOUNTS_CREATED_USERS[@]}" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "${#PNM_ACCOUNTS_CREATED_GROUPS[@]}" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    userdel_calls="$ACCOUNT_USERDEL_CALLS"

    # A later install safely reuses the now-existing account and does not claim it.
    pnm_service_accounts_step || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "${#PNM_ACCOUNTS_CREATED_USERS[@]}" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "${#PNM_ACCOUNTS_CREATED_GROUPS[@]}" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    pnm_service_accounts_rollback || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$ACCOUNT_GROUPDEL_CALLS" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$userdel_calls" "$ACCOUNT_USERDEL_CALLS" || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }

    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_account_receipt_validate "$receipt" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq APPLIED "${PNM_TX_ACCOUNT_STATES[0]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq APPLIED "${PNM_TX_ACCOUNT_STATES[1]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'RECOVERY_REQUIRED\tpnm_service_accounts_rollback rollback_rc=70 original_rc=69' || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_load_for_inspect 'account-rollback-retains-receipt' || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE"
    rm -rf -- "$temp_dir"
}

test_group_with_primary_user_is_preserved() {
    local rc
    PNM_TX_ACTIVE=0
    PNM_ACCOUNTS_CREATED_USERS=()
    PNM_ACCOUNTS_CREATED_GROUPS=(xray)
    ACCOUNT_GROUPDEL_CALLS=0
    if pnm_service_accounts_rollback; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 0 "$ACCOUNT_GROUPDEL_CALLS" || return 1
    assert_eq 1 "${#PNM_ACCOUNTS_CREATED_GROUPS[@]}"
}

run_test 'service account policy is fixed for both Cores' test_service_account_policy_is_fixed
run_test 'unknown service account is rejected' test_unknown_service_account_is_rejected
run_test 'valid existing service accounts are reused' test_valid_existing_accounts_are_reused
run_test 'existing accounts reject Home, Shell, and primary GID mismatches' test_existing_accounts_reject_home_shell_and_gid_mismatches
run_test 'failed user deletion preserves its group and rollback tracking' test_failed_user_delete_preserves_group_and_tracking
run_test 'group with another primary user is preserved' test_group_with_primary_user_is_preserved
finish_tests
