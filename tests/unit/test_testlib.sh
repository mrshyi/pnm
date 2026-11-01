#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$TEST_ROOT/testlib.sh"

test_case_state_is_isolated() (
    local fixture_state=original
    harness_fixture_command() { printf 'original\n'; }
    mutate_fixture_state() {
        fixture_state=changed
        harness_fixture_command() { printf 'changed\n'; }
    }
    run_test fixture mutate_fixture_state >/dev/null
    assert_eq original "$fixture_state" || return 1
    assert_eq original "$(harness_fixture_command)"
)

test_parent_cleanup_stays_outside_case() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    touch "$temp_dir/fixture"
    check_fixture() { [[ -f "$temp_dir/fixture" ]]; }
    run_test fixture check_fixture >/dev/null
    [[ -f "$temp_dir/fixture" ]]
)

run_test 'test cases cannot leak variables or function replacements' test_case_state_is_isolated
run_test 'parent fixture cleanup waits until all cases finish' test_parent_cleanup_stays_outside_case
finish_tests
