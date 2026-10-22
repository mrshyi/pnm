#!/usr/bin/env bash

TESTS_PASSED=0
TESTS_FAILED=0
RUN_OUTPUT=''
RUN_ERROR=''
RUN_RC=0

test_fail() {
    printf 'not ok - %s\n' "$1" >&2
    ((TESTS_FAILED += 1))
}

test_pass() {
    printf 'ok - %s\n' "$1"
    ((TESTS_PASSED += 1))
}

assert_eq() {
    local expected="${1-}"
    local actual="${2-}"
    local message="${3:-values should be equal}"

    if [[ "$actual" != "$expected" ]]; then
        printf 'assert_eq failed: %s\nexpected: <%s>\nactual:   <%s>\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="${1-}"
    local needle="${2-}"
    local message="${3:-output should contain text}"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'assert_contains failed: %s\nmissing: <%s>\noutput:  <%s>\n' "$message" "$needle" "$haystack" >&2
        return 1
    fi
}

assert_not_contains() {
    local haystack="${1-}"
    local needle="${2-}"
    local message="${3:-output should not contain text}"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'assert_not_contains failed: %s\nunexpected: <%s>\noutput:     <%s>\n' "$message" "$needle" "$haystack" >&2
        return 1
    fi
}

run_capture() {
    local stdout_file stderr_file

    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    if "$@" >"$stdout_file" 2>"$stderr_file"; then
        RUN_RC=0
    else
        RUN_RC=$?
    fi
    RUN_OUTPUT="$(<"$stdout_file")"
    RUN_ERROR="$(<"$stderr_file")"
    rm -f -- "$stdout_file" "$stderr_file"
}

pnm_test_record_applied_config() {
    local core="${1:?Core ID required}" config="${2:?config required}" directory
    directory="$PNM_STATE_DIR/cores/$core"
    mkdir -p -- "$directory" || return 1
    printf 'SCHEMA_VERSION=1\nCORE=%s\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=0123456789abcdef0123456789abcdef\n' \
        "$core" "$(sha256sum -- "$config" | awk '{print $1}')" >"$directory/applied.env" || return 1
    chmod 0600 -- "$directory/applied.env"
}

run_test() {
    local name="${1:?test name required}"
    local function_name="${2:?test function required}"

    # A case may replace commands or global flags; keep those changes local.
    # Parent EXIT traps own shared fixtures and must not run in each case.
    if (trap - EXIT; "$function_name"); then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

finish_tests() {
    printf '# passed=%d failed=%d\n' "$TESTS_PASSED" "$TESTS_FAILED"
    ((TESTS_FAILED == 0))
}
