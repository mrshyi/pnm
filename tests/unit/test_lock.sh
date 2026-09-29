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
# shellcheck source=../../lib/lock.sh
source "$PNM_LIB_DIR/lock.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_lock_acquire_release() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    pnm_lock_acquire exclusive
    [[ -n "$PNM_LOCK_FD" ]] || return 1
    pnm_lock_release
    [[ -z "$PNM_LOCK_FD" ]]
    rm -rf -- "$temp_dir"
}

test_nested_lock_is_reentrant_and_releases_last_owner() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_LOCK_DEPTH=0
    PNM_LOCK_FD=''
    PNM_LOCK_MODE=''
    pnm_lock_acquire exclusive
    pnm_lock_acquire exclusive
    assert_eq 2 "$PNM_LOCK_DEPTH" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_lock_release
    assert_eq 1 "$PNM_LOCK_DEPTH" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -n "$PNM_LOCK_FD" ]] || { rm -rf -- "$temp_dir"; return 1; }
    pnm_lock_release
    assert_eq 0 "$PNM_LOCK_DEPTH" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -z "$PNM_LOCK_FD" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ -z "$PNM_LOCK_MODE" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_cleanup_registration_is_restricted() {
    local rc
    if pnm_register_cleanup_path /etc/pnm; then rc=0; else rc=$?; fi
    assert_eq 77 "$rc"
}

run_test 'exclusive lock can be acquired and released' test_lock_acquire_release
run_test 'nested lock is reentrant and releases at final owner' test_nested_lock_is_reentrant_and_releases_last_owner
run_test 'cleanup refuses paths outside PNM temporary roots' test_cleanup_registration_is_restricted
finish_tests
