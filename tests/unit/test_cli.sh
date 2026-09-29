#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help
    assert_eq 0 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'Proxy Node Manager (PNM)'
}

test_version() {
    run_capture "$PROJECT_ROOT/bin/pnm" version
    assert_eq 0 "$RUN_RC" && assert_eq "pnm $(<"$PROJECT_ROOT/VERSION")" "$RUN_OUTPUT"
}

test_unknown_command() {
    run_capture "$PROJECT_ROOT/bin/pnm" does-not-exist
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_ERROR" 'Unknown command'
}

test_removed_broad_commands_return_usage() {
    local command_name
    for command_name in acceptance deploy preflight assets firewall client change reverify transaction; do
        run_capture "$PROJECT_ROOT/bin/pnm" "$command_name"
        assert_eq 64 "$RUN_RC" || return 1
        assert_contains "$RUN_ERROR" 'Unknown command' || return 1
    done
}

test_core_help_hides_broad_entrypoints() {
    run_capture "$PROJECT_ROOT/bin/pnm" help
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'update <core>' || return 1
    assert_not_contains "$RUN_OUTPUT" 'acceptance' || return 1
    assert_not_contains "$RUN_OUTPUT" 'tailscale'
}

test_node_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help node
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'pnm node <init|change|show|validate>' || return 1
    assert_contains "$RUN_OUTPUT" '--xray-sha256 SHA256'
}

test_installer_help() {
    run_capture bash "$PROJECT_ROOT/install.sh" --help
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'Install the PNM CLI and runtime files'
}

test_non_tty_without_command() {
    run_capture "$PROJECT_ROOT/bin/pnm"
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'Usage:'
}

test_json_quiet_conflict() {
    run_capture "$PROJECT_ROOT/bin/pnm" --json --quiet check
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_ERROR" 'mutually exclusive'
}

test_status_json() {
    run_capture "$PROJECT_ROOT/bin/pnm" --json status
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"] == "pnm.status.v1"' <<<"$RUN_OUTPUT"
}

run_test 'help command' test_help
run_test 'version command' test_version
run_test 'unknown command returns usage' test_unknown_command
run_test 'broad commands are removed from the CLI' test_removed_broad_commands_return_usage
run_test 'help documents the dual-Core CLI' test_core_help_hides_broad_entrypoints
run_test 'node management help is available' test_node_help
run_test 'installer exposes usage information' test_installer_help
run_test 'non-TTY no-argument call does not block' test_non_tty_without_command
run_test 'json and quiet are mutually exclusive' test_json_quiet_conflict
run_test 'status emits valid JSON' test_status_json
finish_tests
