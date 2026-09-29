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

run_test() {
    local name="${1:?test name required}"
    local function_name="${2:?test function required}"

    if "$function_name"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

finish_tests() {
    printf '# passed=%d failed=%d\n' "$TESTS_PASSED" "$TESTS_FAILED"
    ((TESTS_FAILED == 0))
}
