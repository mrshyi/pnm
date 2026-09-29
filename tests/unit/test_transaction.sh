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
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

TX_FIXTURE_TARGET=''
TX_FIXTURE_EXPECTED=''

tx_restore_fixture() {
    pnm_tx_restore_file "$TX_FIXTURE_TARGET" fixture "$TX_FIXTURE_EXPECTED"
}

tx_fail_apply() {
    return 78
}

tx_unexpected_apply() {
    TX_APPLY_CALLED=1
}

tx_fail_rollback() {
    return 23
}

test_transaction_journal_lifecycle() {
    local temp_dir journal metadata
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-transaction'
    PNM_DRY_RUN=0

    pnm_tx_begin install || return 1
    journal="$PNM_TX_PATH/journal.tsv"
    metadata="$PNM_TX_PATH/metadata.env"
    [[ -f "$journal" ]] || return 1
    pnm_tx_commit || return 1
    pnm_tx_close || return 1
    assert_eq '600' "$(stat -c '%a' "$journal")" || return 1
    assert_eq '600' "$(stat -c '%a' "$metadata")" || return 1
    assert_contains "$(<"$journal")" $'BEGIN\toperation=install' && assert_contains "$(<"$journal")" $'COMMIT\t'
    assert_contains "$(<"$metadata")" 'DEPLOYMENT_ID=none'
    rm -rf -- "$temp_dir"
}

test_dry_run_transaction_creates_no_state() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-dry-run'
    PNM_DRY_RUN=1

    pnm_tx_begin install || return 1
    assert_eq 'dry-run:unit-dry-run' "$PNM_TX_PATH" || return 1
    pnm_tx_close || return 1
    [[ ! -e "$PNM_STATE_DIR" ]]
    rm -rf -- "$temp_dir"
}

test_snapshot_restore_uses_expected_written_hash() {
    local temp_dir target current journal
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-snapshot'
    PNM_DRY_RUN=0
    target="$temp_dir/managed.conf"
    printf 'old configuration\n' >"$target"
    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_snapshot_file "$target" fixture || { rm -rf -- "$temp_dir"; return 1; }
    printf 'new configuration\n' >"$target"
    TX_FIXTURE_TARGET="$target"
    TX_FIXTURE_EXPECTED="$(pnm_tx_file_sha256 "$target")"
    pnm_tx_add_rollback tx_restore_fixture || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_TX_PATH/journal.tsv"
    pnm_tx_rollback || { rm -rf -- "$temp_dir"; return 1; }
    current="$(<"$target")"
    pnm_tx_close || true
    assert_contains "$(<"$journal")" $'ROLLBACK_COMPLETE\t' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'ROLLED_BACK\t' || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq 'old configuration' "$current"
}

test_snapshot_restore_refuses_manual_drift() {
    local temp_dir target rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-drift'
    PNM_DRY_RUN=0
    target="$temp_dir/managed.conf"
    printf 'old configuration\n' >"$target"
    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_snapshot_file "$target" fixture || { rm -rf -- "$temp_dir"; return 1; }
    printf 'new configuration\n' >"$target"
    TX_FIXTURE_TARGET="$target"
    TX_FIXTURE_EXPECTED="$(pnm_tx_file_sha256 "$target")"
    printf 'manual change\n' >"$target"
    if pnm_tx_restore_file "$target" fixture "$TX_FIXTURE_EXPECTED"; then rc=0; else rc=$?; fi
    pnm_tx_close || true
    rm -rf -- "$temp_dir"
    assert_eq 70 "$rc"
}

test_transaction_surfaces_rollback_failure() {
    local temp_dir journal rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-rollback-failure'
    PNM_DRY_RUN=0

    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_add_rollback tx_fail_rollback || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_run failing_step tx_fail_apply; then rc=0; else rc=$?; fi
    journal="$PNM_TX_PATH/journal.tsv"
    pnm_tx_close || true
    assert_eq 70 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'RECOVERY_REQUIRED\t'
    rm -rf -- "$temp_dir"
}

test_transaction_ids_are_unique_and_deploy_bound() {
    local temp_dir old_override id_one id_two metadata
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_DRY_RUN=0
    old_override="${PNM_TX_ID_OVERRIDE-}"
    unset PNM_TX_ID_OVERRIDE
    id_one="$(pnm_tx_new_id)" || { rm -rf -- "$temp_dir"; return 1; }
    id_two="$(pnm_tx_new_id)" || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$id_one" != "$id_two" ]] || { rm -rf -- "$temp_dir"; return 1; }
    PNM_TX_ID_OVERRIDE="$old_override"
    PNM_DEPLOY_ACTIVE=1
    PNM_DEPLOY_ID=deploy-fixture
    PNM_TX_ID_OVERRIDE=unit-deploy-bound
    pnm_tx_begin core-lifecycle-xray || { rm -rf -- "$temp_dir"; return 1; }
    metadata="$PNM_TX_PATH/metadata.env"
    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$metadata")" 'DEPLOYMENT_ID=deploy-fixture' || { rm -rf -- "$temp_dir"; return 1; }
    PNM_DEPLOY_ACTIVE=0
    PNM_DEPLOY_ID=''
    rm -rf -- "$temp_dir"
}

test_transaction_refuses_to_replace_dangling_symlink() {
    local temp_dir source target rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-dangling-link
    PNM_DRY_RUN=0
    source="$temp_dir/staged"
    target="$temp_dir/dangling"
    printf 'managed\n' >"$source"
    ln -s "$temp_dir/missing-target" "$target"
    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_write_file "$source" "$target" dangling 0600; then rc=0; else rc=$?; fi
    pnm_tx_close || true
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -L "$target" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_transaction_stops_before_apply_if_journal_fails() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-journal-full
    PNM_DRY_RUN=0
    TX_APPLY_CALLED=0
    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    rm -f -- "$PNM_TX_PATH/journal.tsv"
    ln -s /dev/full "$PNM_TX_PATH/journal.tsv"
    if pnm_tx_run protected_step tx_unexpected_apply 2>/dev/null; then rc=0; else rc=$?; fi
    pnm_tx_close 2>/dev/null || true
    assert_eq 73 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$TX_APPLY_CALLED" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_transaction_manifest_persists_intent_and_application() {
    local temp_dir target staged manifest expected decoded
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-manifest
    PNM_DRY_RUN=0
    target="$temp_dir/managed.conf"
    staged="$temp_dir/staged.conf"
    printf 'old\n' >"$target"
    printf 'new\n' >"$staged"
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_write_file "$staged" "$target" config_file 0600 || { rm -rf -- "$temp_dir"; return 1; }
    manifest="$PNM_TX_PATH/changes.tsv"
    expected="$(pnm_tx_file_sha256 "$target")"
    assert_eq 600 "$(stat -c '%a' "$manifest")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 2 "$(wc -l <"$manifest" | tr -d ' ')" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$manifest")" $'INTENT\tconfig_file\t' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$manifest")" $'APPLIED\tconfig_file\t' || { rm -rf -- "$temp_dir"; return 1; }
    decoded="$(awk -F '\t' 'NR==2 {print $3}' "$manifest" | base64 -d)"
    assert_eq "$target" "$decoded" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$expected" "$(awk -F '\t' 'NR==2 {print $6}' "$manifest")" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_transaction_inspect_survives_process_state_and_detects_interrupted_write() {
    local temp_dir target staged transaction_path
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-interrupted
    PNM_DRY_RUN=0
    target="$temp_dir/managed.conf"
    staged="$temp_dir/staged.conf"
    printf 'old\n' >"$target"
    printf 'new\n' >"$staged"
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_snapshot_file "$target" orphan || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_snapshot_state orphan >/dev/null || { rm -rf -- "$temp_dir"; return 1; }
    printf 'new\n' >"$target"
    pnm_tx_manifest_append INTENT orphan "$target" PRESENT 644 "$(pnm_tx_file_sha256 "$target")" || { rm -rf -- "$temp_dir"; return 1; }
    transaction_path="$PNM_TX_PATH"
    PNM_TX_ACTIVE=0
    pnm_lock_release || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_load_for_inspect unit-interrupted; then :; else { rm -rf -- "$temp_dir"; return 1; }; fi
    assert_eq INTERRUPTED "$PNM_TX_INSPECT_STATE" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq sandbox-install "$PNM_TX_INSPECT_OPERATION" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "$PNM_TX_INSPECT_CHANGES" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -d "$transaction_path" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_transaction_inspect_rejects_tampered_manifest() {
    local temp_dir target staged rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-tampered-manifest
    PNM_DRY_RUN=0
    target="$temp_dir/managed.conf"
    staged="$temp_dir/staged.conf"
    printf 'new\n' >"$staged"
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_write_file "$staged" "$target" config_file 0600 || { rm -rf -- "$temp_dir"; return 1; }
    printf 'INTENT\tconfig_file\tLi4vZXZpbA==\tMISSING\tMISSING\t%s\n' "$(pnm_tx_file_sha256 "$target")" >>"$PNM_TX_PATH/changes.tsv"
    PNM_TX_ACTIVE=0
    pnm_lock_release || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_load_for_inspect unit-tampered-manifest; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc"
}

test_core_state_receipt_cannot_cross_failure_domains() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-core-boundary
    PNM_DRY_RUN=0
    pnm_tx_begin core-lifecycle-xray || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_record_core_state hysteria2 hysteria-server.service inactive disabled; then rc=0; else rc=$?; fi
    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc"
}

test_inspect_rejects_recovery_events_after_commit() {
    local temp_dir journal rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-commit-terminal
    PNM_DRY_RUN=0
    pnm_tx_begin core-config-xray || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_TX_PATH/journal.tsv"
    pnm_tx_commit || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    printf '%s\tRECOVERY_REQUIRED\tforged-after-commit\n' "$(pnm_now_utc)" >>"$journal"
    if pnm_tx_load_for_inspect unit-commit-terminal; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc"
}

test_inspect_preserves_service_account_creation_intent() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE=unit-account-receipt
    PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_record_account INTENT group xray || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_record_account APPLIED group xray || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_record_account INTENT user xray || { rm -rf -- "$temp_dir"; return 1; }
    PNM_TX_ACTIVE=0
    pnm_lock_release || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_load_for_inspect unit-account-receipt || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 2 "${#PNM_TX_ACCOUNT_KEYS[@]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq group:xray "${PNM_TX_ACCOUNT_KEYS[0]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq APPLIED "${PNM_TX_ACCOUNT_STATES[0]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq user:xray "${PNM_TX_ACCOUNT_KEYS[1]}" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq INTENT "${PNM_TX_ACCOUNT_STATES[1]}" || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

run_test 'transaction writes an auditable lifecycle journal' test_transaction_journal_lifecycle
run_test 'dry-run transaction creates no state directory' test_dry_run_transaction_creates_no_state
run_test 'snapshot restore is guarded by expected written hash' test_snapshot_restore_uses_expected_written_hash
run_test 'snapshot restore refuses manual drift' test_snapshot_restore_refuses_manual_drift
run_test 'transaction surfaces rollback failure' test_transaction_surfaces_rollback_failure
run_test 'transaction IDs are unique and transactions link to deployment' test_transaction_ids_are_unique_and_deploy_bound
run_test 'transaction refuses to replace a dangling symlink' test_transaction_refuses_to_replace_dangling_symlink
run_test 'transaction stops before apply when journal write fails' test_transaction_stops_before_apply_if_journal_fails
run_test 'transaction manifest persists write intent and applied hash' test_transaction_manifest_persists_intent_and_application
run_test 'transaction inspect reports interrupted write after process state is gone' test_transaction_inspect_survives_process_state_and_detects_interrupted_write
run_test 'transaction inspect rejects tampered manifest paths' test_transaction_inspect_rejects_tampered_manifest
run_test 'Core baseline receipts cannot cross Xray and Hysteria2 boundaries' test_core_state_receipt_cannot_cross_failure_domains
run_test 'transaction inspect rejects recovery events after commit' test_inspect_rejects_recovery_events_after_commit
run_test 'transaction inspect preserves interrupted service-account creation receipts' test_inspect_preserves_service_account_creation_intent
finish_tests
