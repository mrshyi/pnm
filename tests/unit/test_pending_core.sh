#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/lock.sh"
source "$PROJECT_ROOT/lib/transaction.sh"
source "$PROJECT_ROOT/lib/core-ops.sh"
source "$TEST_ROOT/testlib.sh"

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT

prepare_pending_fixture() {
    local action=$1 operation=${2:-core-config-xray}
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    PNM_STATE_DIR="$fixture_root/state" PNM_LOCK_FILE="$fixture_root/lock"
    pending_child() (
        pnm_init_runtime
        printf 'original\n' >"$fixture_root/resource"
        printf 'candidate\n' >"$fixture_root/candidate"
        pnm_tx_begin "$operation" || exit $?
        printf '%s\n' "$PNM_TX_ID" >"$fixture_root/transaction.id"
        if [[ "$action" == empty ]]; then pnm_tx_close; exit $?; fi
        if [[ "$action" == snapshot-empty ]]; then
            pnm_tx_snapshot_file "$fixture_root/resource" initial || exit $?
            pnm_tx_close
            exit $?
        fi
        if [[ "$action" == abandoned-service ]]; then
            pnm_tx_journal STEP_BEGIN stop_core || exit $?
            pnm_tx_close
            exit $?
        fi
        if [[ "$action" == service-only ]]; then
            pnm_tx_record_core_state xray xray.service active disabled || exit $?
            pnm_tx_journal STEP_BEGIN restart || exit $?
        else
            pnm_tx_add_rollback pnm_tx_restore_written_files || exit $?
            pnm_tx_write_file "$fixture_root/candidate" "$fixture_root/resource" fixture 0600 || exit $?
        fi
        case "$action" in
            committed) pnm_tx_commit; pnm_tx_close ;;
            recovered) pnm_tx_rollback; pnm_tx_close ;;
            uncertain) PNM_TX_RECOVERY_REQUIRED=1; pnm_tx_close ;;
            *) kill -KILL "$BASHPID" ;;
        esac
    )
    run_capture pending_child
    case "$action" in
        committed|recovered|uncertain|empty|snapshot-empty|abandoned-service) assert_eq 0 "$RUN_RC" ;;
        *) assert_eq 137 "$RUN_RC" ;;
    esac
}

writer_preparation() { printf 'ran\n' >"$fixture_root/preparation"; }
protected_reader() { printf 'protected fixture output\n'; }

assert_write_refused() {
    run_capture pnm_core_with_write_lock writer_preparation
    assert_eq 70 "$RUN_RC" || return 1
    [[ ! -e "$fixture_root/preparation" && $PNM_LOCK_DEPTH == 0 ]] || return 1
    flock -n "$PNM_LOCK_FILE" true
}

test_sigkill_blocks_later_writers() {
    prepare_pending_fixture killed || return 1
    assert_write_refused
}
test_sigkill_blocks_protected_readers_without_output() {
    prepare_pending_fixture killed || return 1
    run_capture pnm_with_deployment_read_lock protected_reader
    assert_eq 70 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
}
test_service_only_interruption_also_blocks() {
    prepare_pending_fixture service-only core-lifecycle-xray || return 1
    assert_write_refused
}
test_recovery_uncertainty_blocks_later_writers() {
    prepare_pending_fixture uncertain || return 1
    assert_write_refused
}
test_committed_and_recovered_transactions_allow_writers() {
    local action operation
    for action in committed recovered; do
        for operation in core-config-xray unknown-operation; do
            prepare_pending_fixture "$action" "$operation" || return 1
            run_capture pnm_core_with_write_lock writer_preparation
            assert_eq 0 "$RUN_RC" || return 1
            [[ -f "$fixture_root/preparation" && $PNM_LOCK_DEPTH == 0 ]] || return 1
        done
    done
}
test_empty_abandonment_before_mutation_allows_retry() {
    local operation
    for operation in core-config-xray core-lifecycle-xray; do
        prepare_pending_fixture empty "$operation" || return 1
        run_capture pnm_core_with_write_lock writer_preparation
        assert_eq 0 "$RUN_RC" || return 1
        [[ -f "$fixture_root/preparation" && $PNM_LOCK_DEPTH == 0 ]] || return 1
    done
}
test_damaged_metadata_with_mutation_evidence_is_not_ignored() {
    local transaction
    prepare_pending_fixture killed || return 1
    transaction="$(<"$fixture_root/transaction.id")"
    printf 'malformed metadata\n' >"$PNM_STATE_DIR/transactions/$transaction/metadata.env"
    assert_write_refused
}
test_abandoned_service_attempt_is_not_treated_as_empty() {
    prepare_pending_fixture abandoned-service core-uninstall-xray || return 1
    # Use real receipts and an explicit attempted-step journal; no host service runs.
    assert_write_refused
}

test_abandoned_private_snapshot_without_mutation_allows_retry() {
    prepare_pending_fixture snapshot-empty || return 1
    run_capture pnm_core_with_write_lock writer_preparation
    assert_eq 0 "$RUN_RC" || return 1
    [[ -f "$fixture_root/preparation" && $PNM_LOCK_DEPTH == 0 ]]
}

test_incomplete_but_parseable_metadata_is_not_ignored() {
    local transaction
    prepare_pending_fixture killed || return 1
    transaction="$(<"$fixture_root/transaction.id")"
    printf 'SCHEMA_VERSION=2\nTRANSACTION_ID=%s\nDEPLOYMENT_ID=none\n' "$transaction" >"$PNM_STATE_DIR/transactions/$transaction/metadata.env"
    assert_write_refused
}
test_unknown_operation_with_evidence_is_not_ignored() {
    local transaction
    prepare_pending_fixture killed || return 1
    transaction="$(<"$fixture_root/transaction.id")"
    sed -i 's/OPERATION=core-config-xray/OPERATION=unknown-operation/' "$PNM_STATE_DIR/transactions/$transaction/metadata.env"
    assert_write_refused
}
test_attributes_receipt_prevents_empty_abandonment_exception() {
    local transaction
    prepare_pending_fixture empty || return 1
    transaction="$(<"$fixture_root/transaction.id")"
    printf 'published attributes receipt\n' >"$PNM_STATE_DIR/transactions/$transaction/file-attributes.tsv"
    chmod 0600 "$PNM_STATE_DIR/transactions/$transaction/file-attributes.tsv"
    assert_write_refused
}

test_invalid_metadata_cannot_hide_dangling_baseline_receipts() {
    local receipt transaction
    for receipt in core-state.env restore.env deployment.env commit.env commit-uncertain.env; do
        prepare_pending_fixture empty || return 1
        transaction="$(<"$fixture_root/transaction.id")"
        : >"$PNM_STATE_DIR/transactions/$transaction/metadata.env"
        : >"$PNM_STATE_DIR/transactions/$transaction/journal.tsv"
        ln -s "$fixture_root/missing" "$PNM_STATE_DIR/transactions/$transaction/$receipt"
        assert_write_refused || return 1
    done
}

run_test 'dangling baseline or commit receipts cannot vanish behind invalid metadata' test_invalid_metadata_cannot_hide_dangling_baseline_receipts
run_test 'parseable metadata missing its operation cannot bypass the guard' test_incomplete_but_parseable_metadata_is_not_ignored
run_test 'unknown operation metadata cannot hide persisted evidence' test_unknown_operation_with_evidence_is_not_ignored
run_test 'attributes receipt prevents the empty-abandonment retry exception' test_attributes_receipt_prevents_empty_abandonment_exception
run_test 'private snapshot-only abandoned preparation permits retry' test_abandoned_private_snapshot_without_mutation_allows_retry
run_test 'SIGKILL standalone file evidence blocks later writers' test_sigkill_blocks_later_writers
run_test 'SIGKILL standalone evidence blocks protected stdout' test_sigkill_blocks_protected_readers_without_output
run_test 'service-only interrupted lifecycle evidence blocks later writers' test_service_only_interruption_also_blocks
run_test 'standalone recovery uncertainty blocks later writers' test_recovery_uncertainty_blocks_later_writers
run_test 'committed and recovered standalone transactions allow later writers' test_committed_and_recovered_transactions_allow_writers
run_test 'empty abandoned preparation permits a safe retry' test_empty_abandonment_before_mutation_allows_retry
run_test 'damaged metadata with mutation evidence cannot bypass the guard' test_damaged_metadata_with_mutation_evidence_is_not_ignored
run_test 'unresolved uninstall evidence cannot be treated as empty' test_abandoned_service_attempt_is_not_treated_as_empty
finish_tests
