#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT
child="$suite_root/child.sh"
cat >"$child" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
project=$1 private=$2 action=$3
source "$project/lib/common.sh"
source "$project/lib/output.sh"
source "$project/lib/config.sh"
source "$project/lib/lock.sh"
source "$project/lib/transaction.sh"
PNM_STATE_DIR="$private/state" PNM_LOCK_FILE="$private/lock"
pnm_init_runtime
source <(declare -f pnm_tx_journal | sed '1s/pnm_tx_journal/pnm_test_real_journal/')
signal_sent=0
pnm_tx_journal() {
    if [[ "$action" == rollback-receipt && "$1" == ROLLBACK_COMPLETE && "$signal_sent" == 0 ]]; then
        signal_sent=1
        kill -TERM "$BASHPID"
    fi
    pnm_test_real_journal "$@" || return $?
    if [[ "$action" == commit-receipt && "$1" == COMMIT ]]; then kill -TERM "$BASHPID"; fi
    if [[ "$action" == close-receipt && "$1" == ROLLED_BACK ]]; then kill -TERM "$BASHPID"; fi
}
printf 'original\n' >"$private/resource"
chmod 0640 "$private/resource"
printf 'candidate\n' >"$private/candidate"
pnm_tx_begin core-config-xray
printf '%s\n' "$PNM_TX_ID" >"$private/transaction.id"
recover_resource() {
    printf 'called\n' >>"$private/recovery.calls"
    [[ "$action" != recovery-failure ]] || return 70
    [[ "$action" != repeated-term ]] || kill -TERM "$BASHPID"
    pnm_tx_restore_written_files
}
[[ "$action" == missing-callback ]] || pnm_tx_add_rollback recover_resource
pnm_tx_write_file "$private/candidate" "$private/resource" fixture 0600
case "$action" in
    term) kill -TERM "$BASHPID" ;;
    interrupt) kill -INT "$BASHPID" ;;
    error | recovery-failure | missing-callback | repeated-term) exit 78 ;;
    prior-uncertainty) PNM_TX_RECOVERY_REQUIRED=1; exit 78 ;;
    invalid-receipt) chmod 0644 "$PNM_TX_PATH/journal.tsv"; exit 78 ;;
    invalid-symlink)
        printf 'untouched\n' >"$private/victim"
        mv "$PNM_TX_PATH/journal.tsv" "$PNM_TX_PATH/original-journal.tsv"
        ln -s "$private/victim" "$PNM_TX_PATH/journal.tsv"
        exit 78
        ;;
    retained-uncertainty)
        PNM_TX_RECOVERY_REQUIRED=1
        pnm_tx_rollback
        pnm_tx_journal RECOVERY_REQUIRED 'retained uncertainty'
        kill -TERM "$BASHPID"
        ;;
    unexpected-success) exit 0 ;;
    committed | commit-receipt) pnm_tx_commit; exit 0 ;;
    committed-error) pnm_tx_commit; exit 78 ;;
    already-recovered | rollback-receipt) pnm_tx_rollback; exit 78 ;;
    close-receipt) pnm_tx_rollback; pnm_tx_close; exit 0 ;;
esac
BASH

run_interrupted_child() {
    private="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    run_capture bash "$child" "$PROJECT_ROOT" "$private" "$1"
    PNM_STATE_DIR="$private/state"
    pnm_tx_load_for_inspect "$(<"$private/transaction.id")"
}

assert_original_recovered() {
    assert_eq original "$(<"$private/resource")" || return 1
    assert_eq "640:$EUID:$(id -g)" "$(stat -c '%a:%u:%g' "$private/resource")" || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq called "$(<"$private/recovery.calls")"
}

test_term_recovers_and_preserves_signal_status() {
    run_interrupted_child term || return 1
    assert_eq 143 "$RUN_RC" || return 1
    assert_original_recovered
}
test_int_recovers_and_preserves_signal_status() {
    run_interrupted_child interrupt || return 1
    assert_eq 130 "$RUN_RC" || return 1
    assert_original_recovered
}
test_error_recovers_and_preserves_primary_status() {
    run_interrupted_child error || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_original_recovered
}
test_unclosed_success_cannot_report_success() {
    run_interrupted_child unexpected-success || return 1
    assert_eq 70 "$RUN_RC" || return 1
    assert_original_recovered
}
test_recovery_failure_retains_evidence_and_primary_error() {
    run_interrupted_child recovery-failure || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE" || return 1
    assert_contains "$RUN_ERROR" 'recovery'
}
test_committed_exit_never_rolls_back() {
    run_interrupted_child committed || return 1
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    [[ ! -e "$private/recovery.calls" ]]
}
test_committed_primary_error_is_preserved() {
    run_interrupted_child committed-error || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    [[ ! -e "$private/recovery.calls" ]]
}
test_completed_compensation_is_not_repeated() {
    run_interrupted_child already-recovered || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_original_recovered
}

test_missing_callback_cannot_claim_recovery() {
    run_interrupted_child missing-callback || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE" || return 1
    assert_contains "$RUN_ERROR" 'recovery is unavailable'
}
test_second_term_does_not_interrupt_compensation() {
    run_interrupted_child repeated-term || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_original_recovered
}

test_persisted_commit_is_authoritative_at_the_signal_boundary() {
    run_interrupted_child commit-receipt || return 1
    assert_eq 143 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    [[ ! -e "$private/recovery.calls" ]]
}
test_completed_callbacks_finish_their_receipt_after_a_signal() {
    run_interrupted_child rollback-receipt || return 1
    assert_eq 143 "$RUN_RC" || return 1
    assert_original_recovered
}

test_prior_uncertainty_remains_inspectable_after_compensation() {
    run_interrupted_child prior-uncertainty || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq original "$(<"$private/resource")" || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE"
}

test_persisted_uncertainty_is_not_replaced_with_a_completion_receipt() {
    run_interrupted_child retained-uncertainty || return 1
    assert_eq 143 "$RUN_RC" || return 1
    assert_eq original "$(<"$private/resource")" || return 1
    assert_eq called "$(<"$private/recovery.calls")" || return 1
    assert_eq RECOVERY_REQUIRED "$PNM_TX_INSPECT_STATE"
}

test_invalid_receipt_requires_manual_inspection_without_replay() {
    if run_interrupted_child invalid-receipt; then return 1; fi
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    [[ ! -e "$private/recovery.calls" ]] || return 1
    assert_contains "$RUN_ERROR" 'receipt is invalid'
}

test_invalid_journal_symlink_target_is_not_written_on_exit() {
    if run_interrupted_child invalid-symlink; then return 1; fi
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq untouched "$(<"$private/victim")" || return 1
    assert_eq candidate "$(<"$private/resource")" || return 1
    [[ ! -e "$private/recovery.calls" ]] || return 1
    assert_contains "$RUN_ERROR" 'receipt is invalid'
}

test_signal_after_terminal_rollback_close_does_not_append_again() {
    run_interrupted_child close-receipt || return 1
    assert_eq 143 "$RUN_RC" || return 1
    assert_original_recovered
}

run_test 'TERM after final rollback close does not append a second terminal event' test_signal_after_terminal_rollback_close_does_not_append_again
run_test 'invalid journal symlink targets remain unchanged during EXIT' test_invalid_journal_symlink_target_is_not_written_on_exit
run_test 'invalid journal evidence prevents automatic recovery replay' test_invalid_receipt_requires_manual_inspection_without_replay
run_test 'persisted recovery uncertainty is retained without replaying callbacks' test_persisted_uncertainty_is_not_replaced_with_a_completion_receipt
run_test 'prior uncertainty remains inspectable after completed callbacks' test_prior_uncertainty_remains_inspectable_after_compensation
run_test 'persisted commit wins over an interrupted in-memory flag update' test_persisted_commit_is_authoritative_at_the_signal_boundary
run_test 'completed callbacks finish a missing rollback receipt after TERM' test_completed_callbacks_finish_their_receipt_after_a_signal
run_test 'missing callback retains uncertainty instead of claiming recovery' test_missing_callback_cannot_claim_recovery
run_test 'a second TERM does not interrupt the recovery attempt' test_second_term_does_not_interrupt_compensation
run_test 'TERM compensates an active standalone transaction and preserves 143' test_term_recovers_and_preserves_signal_status
run_test 'INT compensates an active standalone transaction and preserves 130' test_int_recovers_and_preserves_signal_status
run_test 'unexpected error compensates and preserves its primary exit status' test_error_recovers_and_preserves_primary_status
run_test 'unclosed uncommitted success is compensated and exits with error' test_unclosed_success_cannot_report_success
run_test 'failed compensation retains recovery evidence and the primary error' test_recovery_failure_retains_evidence_and_primary_error
run_test 'committed standalone transaction is never compensated on EXIT' test_committed_exit_never_rolls_back
run_test 'committed transaction keeps a later primary error' test_committed_primary_error_is_preserved
run_test 'EXIT does not repeat already completed compensation' test_completed_compensation_is_not_repeated
finish_tests
