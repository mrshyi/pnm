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
# shellcheck source=../../lib/accounts.sh
source "$PNM_LIB_DIR/accounts.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_service_account_policy_is_fixed() {
    assert_eq 'xray|/nonexistent|/usr/sbin/nologin' "$(pnm_service_account_policy xray)" || return 1
    assert_eq 'hysteria|/nonexistent|/usr/sbin/nologin' "$(pnm_service_account_policy hysteria)"
}

test_unknown_service_account_is_rejected() {
    local rc
    if pnm_service_account_policy root; then rc=0; else rc=$?; fi
    assert_eq 1 "$rc"
}

run_test 'service account policy is fixed for both Cores' test_service_account_policy_is_fixed
run_test 'unknown service account is rejected' test_unknown_service_account_is_rejected
finish_tests
