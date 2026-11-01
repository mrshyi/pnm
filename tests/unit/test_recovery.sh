#!/usr/bin/env bash
# shellcheck disable=SC1090
set -Eeuo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
for module in common output config lock transaction recovery; do source "$PROJECT_ROOT/lib/$module.sh"; done
source "$TEST_ROOT/testlib.sh"

recovery_fixture() {
    recovery_root=$(mktemp -d)
    trap 'rm -rf -- "$recovery_root"' EXIT
    PNM_STATE_DIR="$recovery_root/state" PNM_LOCK_FILE="$recovery_root/lock"
    PNM_OUTPUT_MODE=json
    pnm_require_root() { :; }
}

recovery_committed() {
    PNM_TX_ID_OVERRIDE=tx-terminal
    pnm_tx_begin node-init && pnm_tx_commit && pnm_tx_close
}

recovery_pending() {
    PNM_TX_ID_OVERRIDE=tx-pending
    printf 'PRIVATE_SNAPSHOT_SENTINEL\n' >"$recovery_root/managed"
    chmod 0600 "$recovery_root/managed"
    printf 'PRIVATE_CANDIDATE_SENTINEL\n' >"$recovery_root/candidate"
    pnm_tx_begin core-profile || return $?
    pnm_tx_journal STEP_BEGIN 'PRIVATE_JOURNAL_SENTINEL' || return $?
    pnm_tx_write_file "$recovery_root/candidate" "$recovery_root/managed" fixture 0600 || return $?
    pnm_tx_close
}

recovery_fingerprint() {
    python3 - "$PNM_STATE_DIR" <<'PY'
import hashlib, json, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
values = {}
for path in sorted(root.rglob('*')):
    info = path.lstat()
    values[str(path.relative_to(root))] = [stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid,
        info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None]
print(json.dumps(values, sort_keys=True))
PY
}

test_recovery_empty_store() (
    recovery_fixture
    run_capture pnm_recovery_command list
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="pnm.recovery.v1"; assert d["writes_blocked"] is False and d["transactions"]==[]' <<<"$RUN_OUTPUT" || return 1
    [[ ! -e "$PNM_STATE_DIR" ]]
)

test_recovery_committed_record() (
    recovery_fixture
    recovery_committed || return 1
    run_capture pnm_recovery_command inspect tx-terminal
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); t=d["transactions"][0]; assert d["writes_blocked"] is False and t["valid"] is True; assert t["state"]=="COMMITTED" and t["operation"]=="node-init"' <<<"$RUN_OUTPUT"
)

test_recovery_blocked_store_is_readable_and_unchanged() (
    recovery_fixture
    recovery_committed && recovery_pending || return 1
    local before
    before=$(recovery_fingerprint)
    run_capture pnm_with_deployment_read_lock true
    assert_eq 70 "$RUN_RC" || return 1
    assert_contains "$RUN_ERROR" 'pnm recovery list' || return 1
    run_capture pnm_recovery_command list
    assert_eq 1 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["writes_blocked"] is True; t={r["id"]:r for r in d["transactions"]}; assert t["tx-pending"]["state"]=="ABANDONED" and t["tx-pending"]["file_directory_changes"]==1; assert t["tx-terminal"]["state"]=="COMMITTED"' <<<"$RUN_OUTPUT" || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'PRIVATE_' || return 1
    assert_not_contains "$RUN_OUTPUT" "$recovery_root" || return 1
    assert_eq "$before" "$(recovery_fingerprint)" || return 1
    assert_eq 'PRIVATE_CANDIDATE_SENTINEL' "$(<"$recovery_root/managed")" || return 1
    run_capture pnm_tx_assert_no_pending_deployment
    assert_eq 70 "$RUN_RC" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
)

test_recovery_invalid_evidence_is_redacted() (
    recovery_fixture
    recovery_committed || return 1
    printf 'PRIVATE_JOURNAL_SENTINEL\n' >"$PNM_STATE_DIR/transactions/tx-terminal/journal.tsv"
    run_capture pnm_recovery_command inspect tx-terminal
    assert_eq 78 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); t=d["transactions"][0]; assert d["writes_blocked"] is True and t["valid"] is False; assert t["state"]=="INVALID" and t["operation"]=="unknown" and t["file_directory_changes"] is None' <<<"$RUN_OUTPUT" || return 1
    assert_not_contains "$RUN_OUTPUT$RUN_ERROR" 'PRIVATE_'
)

test_recovery_input_and_links_refuse() (
    recovery_fixture
    recovery_committed || return 1
    run_capture pnm_recovery_command inspect ../outside
    assert_eq 64 "$RUN_RC" || return 1
    run_capture pnm_recovery_command inspect ..
    assert_eq 64 "$RUN_RC" || return 1
    run_capture pnm_recovery_command inspect missing
    assert_eq 69 "$RUN_RC" || return 1
    ln -s "$recovery_root" "$PNM_STATE_DIR/transactions/tx-linked"
    run_capture pnm_recovery_command inspect tx-linked
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '"state":"INVALID"'
)

test_recovery_store_permissions_are_not_repaired() (
    recovery_fixture
    recovery_committed || return 1
    chmod 0755 "$PNM_STATE_DIR"
    run_capture pnm_recovery_command list
    assert_eq 77 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    assert_eq 755 "$(stat -c '%a' "$PNM_STATE_DIR")" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
)

run_test 'recovery lists an absent store without creating transaction state' test_recovery_empty_store
run_test 'recovery inspect reports a committed transaction through the existing parser' test_recovery_committed_record
run_test 'blocked transactions remain inspectable without disclosure replay or evidence changes' test_recovery_blocked_store_is_readable_and_unchanged
run_test 'invalid transaction evidence produces a redacted invalid report' test_recovery_invalid_evidence_is_redacted
run_test 'recovery refuses traversal missing records and linked evidence' test_recovery_input_and_links_refuse
run_test 'unsafe store permissions refuse without normalization and release the lock' test_recovery_store_permissions_are_not_repaired
finish_tests
