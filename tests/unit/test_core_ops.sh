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
# shellcheck source=../../lib/core-ops.sh
source "$PNM_LIB_DIR/core-ops.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_core_mapping_is_fixed() {
    pnm_core_resolve xray || return 1
    assert_eq xray "$PNM_CORE_ID" || return 1
    assert_eq xray.service "$PNM_CORE_UNIT" || return 1
    pnm_core_resolve hy2 || return 1
    assert_eq hysteria2 "$PNM_CORE_ID" || return 1
    assert_eq hysteria-server.service "$PNM_CORE_UNIT"
}

test_unknown_core_is_rejected() {
    local rc
    if pnm_core_resolve ssh; then rc=0; else rc=$?; fi
    assert_eq 64 "$rc"
}

test_log_options_are_validated_before_journal_access() {
    local rc
    if pnm_core_log xray --lines 0; then rc=0; else rc=$?; fi
    assert_eq 64 "$rc"
}

test_dry_run_cannot_mutate_a_core() {
    local rc
    PNM_DRY_RUN=1
    if pnm_core_command restart xray; then rc=0; else rc=$?; fi
    PNM_DRY_RUN=0
    assert_eq 64 "$rc"
}

test_core_command_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help apply
    assert_eq 0 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'pnm apply <xray|hy2>'
}

run_test 'core to unit mapping is explicit' test_core_mapping_is_fixed
run_test 'unsupported service names are rejected' test_unknown_core_is_rejected
run_test 'log options reject invalid line counts' test_log_options_are_validated_before_journal_access
run_test 'dry-run blocks mutating core commands' test_dry_run_cannot_mutate_a_core
run_test 'core command help is available' test_core_command_help
finish_tests
