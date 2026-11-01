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
TX_APPLY_ARGS=()

tx_restore_fixture() {
    pnm_tx_restore_file "$TX_FIXTURE_TARGET" fixture "$TX_FIXTURE_EXPECTED"
}

tx_fail_apply() {
    return 69
}

tx_unexpected_apply() {
    TX_APPLY_CALLED=1
}

tx_capture_apply_args() {
    TX_APPLY_ARGS=("$@")
}

tx_fail_rollback() {
    return 23
}

test_backslash_path_write_and_recovery_remain_inspectable() (
    local temp_dir target attributes
    temp_dir="$(mktemp -d)"
    trap 'pnm_tx_close >/dev/null 2>&1 || true; rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-backslash PNM_DRY_RUN=0
    mkdir -m 0700 -- "$temp_dir/managed\\area" || return 1
    target="$temp_dir/managed\\area/config"
    printf 'original configuration' >"$target"
    chmod 0640 -- "$target" || return 1
    attributes="$(stat -c '%a|%u|%g' -- "$target")"
    printf 'candidate configuration' >"$temp_dir/candidate"
    pnm_tx_begin install || return 1
    pnm_tx_add_rollback pnm_tx_restore_written_files || return 1
    pnm_tx_write_file "$temp_dir/candidate" "$target" fixture 0600 required || return 1
    assert_eq 'candidate configuration' "$(<"$target")" || return 1
    [[ "${PNM_TX_WRITTEN_HASHES[0]}" =~ ^[a-f0-9]{64}$ ]] || return 1
    pnm_tx_verify_written_resources || return 1
    pnm_tx_rollback || return 1
    pnm_tx_close || return 1
    assert_eq 'original configuration' "$(<"$target")" || return 1
    assert_eq "$attributes" "$(stat -c '%a|%u|%g' -- "$target")" || return 1
    pnm_tx_load_for_inspect unit-backslash || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 0 "$PNM_TX_INSPECT_CHANGES"
)

test_transaction_hash_tool_failure_has_no_digest() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf 'configuration' >"$temp_dir/config"
    sha256sum() { command sha256sum "$@" || return $?; return 23; }
    set +o pipefail
    run_capture pnm_tx_file_sha256 "$temp_dir/config"
    assert_eq "$PNM_EXIT_SOFTWARE" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT"
)

test_inspect_refuses_failed_snapshot_hash_observation() (
    local temp_dir emit_digest
    temp_dir="$(mktemp -d)"
    trap 'pnm_tx_close >/dev/null 2>&1 || true; rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-hash-observation PNM_DRY_RUN=0
    printf 'original configuration' >"$temp_dir/config"
    printf 'candidate configuration' >"$temp_dir/candidate"
    pnm_tx_begin install || return 1
    pnm_tx_write_file "$temp_dir/candidate" "$temp_dir/config" fixture 0600 required || return 1
    pnm_tx_commit || return 1
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-hash-observation || return 1
    assert_eq COMMITTED "$PNM_TX_INSPECT_STATE" || return 1
    pnm_tx_assert_no_pending_deployment || return 1
    sha256sum() {
        if [[ "$emit_digest" == yes ]]; then command sha256sum "$@" || return $?; fi
        return 23
    }
    for emit_digest in yes no; do
        run_capture pnm_tx_load_for_inspect unit-hash-observation
        assert_eq "$PNM_EXIT_CONFIG" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT$RUN_ERROR" || return 1
        run_capture pnm_tx_assert_no_pending_deployment
        assert_eq "$PNM_EXIT_SOFTWARE" "$RUN_RC" || return 1
        assert_eq 'candidate configuration' "$(<"$temp_dir/config")" || return 1
    done
)

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
    assert_eq 69 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq failing_step "$PNM_TX_STEP_FAILURE_NAME" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 69 "$PNM_TX_STEP_FAILURE_RC" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 23 "$PNM_TX_ROLLBACK_FAILURE_RC" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'STEP_FAILED\tfailing_step rc=69' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'RECOVERY_REQUIRED\ttx_fail_rollback rollback_rc=23 original_rc=69'
    rm -rf -- "$temp_dir"
}

test_transaction_forwards_apply_arguments() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='unit-apply-args'
    PNM_DRY_RUN=0
    TX_APPLY_ARGS=()

    pnm_tx_begin install || { rm -rf -- "$temp_dir"; return 1; }
    if pnm_tx_run apply_args tx_capture_apply_args first second; then rc=0; else rc=$?; fi
    pnm_tx_commit || { pnm_tx_close || true; rm -rf -- "$temp_dir"; return 1; }
    pnm_tx_close || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
    assert_eq 0 "$rc" || return 1
    assert_eq 2 "${#TX_APPLY_ARGS[@]}" || return 1
    assert_eq first "${TX_APPLY_ARGS[0]}" || return 1
    assert_eq second "${TX_APPLY_ARGS[1]}"
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
    pnm_tx_manifest_append INTENT orphan "$target" PRESENT "$(stat -c '%a' -- "$target")" "$(pnm_tx_file_sha256 "$target")" || { rm -rf -- "$temp_dir"; return 1; }
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

test_snapshot_restores_numeric_ownership() (
    local temp_dir target staged expected
    [[ "$EUID" == 0 ]] || { printf '# SKIP numeric ownership requires root\n'; return 0; }
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-owner PNM_DRY_RUN=0
    target="$temp_dir/target" staged="$temp_dir/staged"
    printf 'old\n' >"$target"
    chown 65534:65534 "$target"
    chmod 2640 "$target"
    printf 'new\n' >"$staged"
    pnm_tx_begin install || return 1
    pnm_tx_write_file "$staged" "$target" owned 0600 || return 1
    expected="$(pnm_tx_file_sha256 "$target")"
    pnm_tx_restore_file "$target" owned "$expected" || return 1
    assert_eq 'old' "$(<"$target")" || return 1
    assert_eq '2640|65534|65534' "$(stat -c '%a|%u|%g' "$target")" || return 1
    pnm_tx_close
)

test_directory_compensation() (
    local temp_dir baseline
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-directories PNM_DRY_RUN=0
    mkdir -m 0750 "$temp_dir/existing"
    if [[ "$EUID" == 0 ]]; then
        chown 65534:65534 "$temp_dir/existing"
        chmod 2750 "$temp_dir/existing"
    fi
    baseline="$(stat -c '%a|%u|%g' "$temp_dir/existing")"
    pnm_tx_begin sandbox-install || return 1
    pnm_tx_add_rollback pnm_tx_restore_directories || return 1
    pnm_tx_prepare_directory "$temp_dir/existing" 0700 || return 1
    pnm_tx_prepare_directory "$temp_dir/new/child" 0700 || return 1
    pnm_tx_rollback || return 1
    assert_eq "$baseline" "$(stat -c '%a|%u|%g' "$temp_dir/existing")" || return 1
    [[ ! -e "$temp_dir/new" ]] || return 1
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-directories || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE"
)

test_snapshot_metadata_rejects_extra_fields() (
    local temp_dir target expected rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-bad-metadata PNM_DRY_RUN=0
    target="$temp_dir/target"
    printf 'original\n' >"$target"
    pnm_tx_begin install || return 1
    pnm_tx_snapshot_file "$target" owned || return 1
    printf 'new\n' >"$target"
    pnm_tx_manifest_append INTENT owned "$target" PRESENT 644 "$(pnm_tx_file_sha256 "$target")" || return 1
    expected="$(pnm_tx_file_sha256 "$target")"
    printf 'PRESENT|640|0|0|unexpected\n' >"$PNM_TX_PATH/snapshots/owned.state"
    if pnm_tx_restore_file "$target" owned "$expected"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq new "$(<"$target")" || return 1
    pnm_tx_close
)

test_directory_rollback_preserves_foreign_contents() (
    local temp_dir rc journal
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-foreign-directory PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || return 1
    pnm_tx_add_rollback pnm_tx_restore_directories || return 1
    pnm_tx_prepare_directory "$temp_dir/new" 0700 || return 1
    printf 'foreign data\n' >"$temp_dir/new/foreign"
    journal="$PNM_TX_PATH/journal.tsv"
    if pnm_tx_rollback 2>/dev/null; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_eq 'foreign data' "$(<"$temp_dir/new/foreign")" || return 1
    assert_not_contains "$(<"$journal")" ROLLBACK_COMPLETE || return 1
    pnm_tx_close
)

test_legacy_schema_inspection_is_read_only() (
    local temp_dir target rc schema
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-legacy PNM_DRY_RUN=0
    target="$temp_dir/target"
    printf 'old\n' >"$target"
    pnm_tx_begin install || return 1
    pnm_tx_snapshot_file "$target" owned || return 1
    printf 'new\n' >"$target"
    pnm_tx_manifest_append INTENT owned "$target" PRESENT 644 "$(pnm_tx_file_sha256 "$target")" || return 1
    for schema in 1 99; do
        sed -i "s/^SCHEMA_VERSION=.*/SCHEMA_VERSION=$schema/" "$PNM_TX_PATH/metadata.env"
        if pnm_tx_restore_file "$target" owned "$(pnm_tx_file_sha256 "$target")"; then rc=0; else rc=$?; fi
        assert_eq 78 "$rc" || return 1
        assert_eq new "$(<"$target")" || return 1
    done
    sed -i 's/^SCHEMA_VERSION=.*/SCHEMA_VERSION=1/' "$PNM_TX_PATH/metadata.env"
    printf 'PRESENT|644\n' >"$PNM_TX_PATH/snapshots/owned.state"
    rm -- "$PNM_TX_PATH/directories.tsv"
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-legacy || return 1
    assert_eq ABANDONED "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 1 "$PNM_TX_INSPECT_CHANGES"
)

test_transaction_rejects_symlink_ancestor_writes() (
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-ancestor PNM_DRY_RUN=0
    mkdir "$temp_dir/outside"
    ln -s "$temp_dir/outside" "$temp_dir/link"
    printf 'new\n' >"$temp_dir/staged"
    pnm_tx_begin install || return 1
    if pnm_tx_write_file "$temp_dir/staged" "$temp_dir/link/target" unsafe 0600; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    [[ ! -e "$temp_dir/outside/target" ]] || return 1
    pnm_tx_close
)

test_directory_recovery_rejects_replacement() (
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-replaced-directory PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || return 1
    pnm_tx_add_rollback pnm_tx_restore_directories || return 1
    pnm_tx_prepare_directory "$temp_dir/new" 0700 || return 1
    mv "$temp_dir/new" "$temp_dir/original"
    mkdir -m 0700 "$temp_dir/new"
    if pnm_tx_rollback; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    [[ -d "$temp_dir/new" && -d "$temp_dir/original" ]] || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    pnm_tx_close
)

test_inspect_handles_missing_applied_receipts() (
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-receipt-failure PNM_DRY_RUN=0
    # Simulate storage rejecting APPLIED, while INTENT and recovery still work.
    pnm_tx_directory_receipt() {
        [[ "$1" != APPLIED ]] || return 73
        printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(printf '%s' "$2" | base64 -w0)" "$3" "$4" "$5" >>"$PNM_TX_PATH/directories.tsv"
    }
    pnm_tx_manifest_append() {
        [[ "$1" != APPLIED ]] || return 73
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | base64 -w0)" "$4" "$5" "$6" >>"$PNM_TX_PATH/changes.tsv"
    }
    printf 'new\n' >"$temp_dir/staged"
    pnm_tx_begin install || return 1
    pnm_tx_add_rollback pnm_tx_restore_directories || return 1
    pnm_tx_add_rollback pnm_tx_restore_written_files || return 1
    if pnm_tx_prepare_directory "$temp_dir/new" 0700; then rc=0; else rc=$?; fi
    assert_eq 73 "$rc" || return 1
    if pnm_tx_write_file "$temp_dir/staged" "$temp_dir/new/target" owned 0600; then rc=0; else rc=$?; fi
    assert_eq 73 "$rc" || return 1
    pnm_tx_rollback || return 1
    [[ ! -e "$temp_dir/new" ]] || return 1
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-receipt-failure || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 0 "$PNM_TX_INSPECT_CHANGES"
)

test_low_mode_metadata_survives_recovery() (
    local temp_dir
    [[ "$EUID" == 0 ]] || { printf '# SKIP low-mode recovery requires root\n'; return 0; }
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-low-mode PNM_DRY_RUN=0
    mkdir -m 0000 "$temp_dir/existing"
    printf 'old\n' >"$temp_dir/target"
    printf 'new\n' >"$temp_dir/staged"
    chmod 0040 "$temp_dir/target"
    pnm_tx_begin install || return 1
    pnm_tx_add_rollback pnm_tx_restore_directories || return 1
    pnm_tx_add_rollback pnm_tx_restore_written_files || return 1
    pnm_tx_prepare_directory "$temp_dir/existing" 0700 || return 1
    pnm_tx_write_file "$temp_dir/staged" "$temp_dir/target" low 0600 || return 1
    pnm_tx_rollback || return 1
    assert_eq 0 "$(stat -c '%a' "$temp_dir/existing")" || return 1
    assert_eq 40 "$(stat -c '%a' "$temp_dir/target")" || return 1
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-low-mode || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE"
)

test_inspect_handles_multiple_file_restores() (
    local temp_dir path
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state" PNM_LOCK_FILE="$temp_dir/lock"
    PNM_TX_ID_OVERRIDE=unit-many-restores PNM_DRY_RUN=0
    printf 'new\n' >"$temp_dir/staged"
    pnm_tx_begin install || return 1
    pnm_tx_add_rollback pnm_tx_restore_written_files || return 1
    for path in first second; do
        printf 'old\n' >"$temp_dir/$path"
        pnm_tx_write_file "$temp_dir/staged" "$temp_dir/$path" "$path" 0600 || return 1
    done
    pnm_tx_rollback || return 1
    pnm_tx_close || return 1
    pnm_tx_load_for_inspect unit-many-restores || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 0 "$PNM_TX_INSPECT_CHANGES"
)

run_test 'backslash paths retain valid write, rollback and inspect receipts' test_backslash_path_write_and_recovery_remain_inspectable
run_test 'failed transaction hash queries emit no digest independently of pipefail' test_transaction_hash_tool_failure_has_no_digest
run_test 'transaction inspect refuses failed snapshot hash observations' test_inspect_refuses_failed_snapshot_hash_observation
run_test 'recovery remains inspectable when APPLIED receipt writes fail' test_inspect_handles_missing_applied_receipts
run_test 'low permission modes survive recovery and inspection' test_low_mode_metadata_survives_recovery
run_test 'transaction writes reject symlink ancestors' test_transaction_rejects_symlink_ancestor_writes
run_test 'directory recovery refuses a replacement with identical modes' test_directory_recovery_rejects_replacement
run_test 'directory rollback retains foreign contents and recovery evidence' test_directory_rollback_preserves_foreign_contents
run_test 'legacy transactions stay inspectable and legacy or unknown recovery writes fail' test_legacy_schema_inspection_is_read_only
run_test 'transaction inspection accepts reverse recovery of multiple files' test_inspect_handles_multiple_file_restores
run_test 'snapshot restores numeric UID GID and mode' test_snapshot_restores_numeric_ownership
run_test 'directory rollback restores modes and removes only new empty paths' test_directory_compensation
run_test 'snapshot metadata rejects unexpected fields before restoration' test_snapshot_metadata_rejects_extra_fields
run_test 'transaction writes an auditable lifecycle journal' test_transaction_journal_lifecycle
run_test 'dry-run transaction creates no state directory' test_dry_run_transaction_creates_no_state
run_test 'snapshot restore is guarded by expected written hash' test_snapshot_restore_uses_expected_written_hash
run_test 'snapshot restore refuses manual drift' test_snapshot_restore_refuses_manual_drift
run_test 'transaction surfaces rollback failure' test_transaction_surfaces_rollback_failure
run_test 'transaction forwards apply arguments' test_transaction_forwards_apply_arguments
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
