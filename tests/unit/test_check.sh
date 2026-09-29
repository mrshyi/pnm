#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
FAKE_COMMAND="$TEST_ROOT/fakebin/fake-command"
FAKE_DIR="$(mktemp -d)"
trap 'rm -rf -- "$FAKE_DIR"' EXIT

for command_name in uname systemctl timedatectl ss xray hysteria apt-get stat; do
    ln -s "$FAKE_COMMAND" "$FAKE_DIR/$command_name"
done

# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

run_fake_pnm() {
    env \
        PATH="$FAKE_DIR:$PATH" \
        PNM_TEST_SYSTEMD=1 \
        PNM_FAKE_PROFILE="${PNM_FAKE_PROFILE:-pass}" \
        PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid" \
        PNM_OS_RELEASE_FILE="$TEST_ROOT/fixtures/os-release-debian13" \
        PNM_XRAY_CONFIG="$TEST_ROOT/fixtures/xray-config.json" \
        PNM_HY2_CONFIG="$TEST_ROOT/fixtures/hysteria-config.yaml" \
        "$PROJECT_ROOT/bin/pnm" "$@"
}

test_passing_check_json() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["overall"] == "OK"; assert d["counts"]["fail"] == 0' <<<"$RUN_OUTPUT"
}

test_failure_exit_precedence() {
    PNM_FAKE_PROFILE=fail run_capture run_fake_pnm --json check
    assert_eq 2 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["overall"] == "FAIL"; assert d["counts"]["fail"] > 0' <<<"$RUN_OUTPUT"
}

test_quiet_has_no_stdout() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --quiet check
    assert_eq 0 "$RUN_RC" && assert_eq '' "$RUN_OUTPUT"
}

test_json_contains_no_fixture_password() {
    PNM_FAKE_PROFILE=pass run_capture run_fake_pnm --json check
    assert_not_contains "$RUN_OUTPUT" 'REDACTED_FIXTURE'
}

run_test 'fully healthy fixture returns PASS JSON' test_passing_check_json
run_test 'FAIL takes exit-code precedence' test_failure_exit_precedence
run_test 'quiet mode emits no stdout' test_quiet_has_no_stdout
run_test 'check output does not expose config secret fixture' test_json_contains_no_fixture_password
finish_tests
