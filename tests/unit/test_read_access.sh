#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$TEST_ROOT/testlib.sh"

test_nonroot_diagnostics_do_not_claim_deployment_ready() (
    local root
    # This case needs a real UID boundary, rather than a mocked root predicate.
    if ((EUID != 0)) || ! command -v runuser >/dev/null || ! id nobody >/dev/null 2>&1; then
        printf '# SKIP: root, runuser and nobody are required\n'
        return 0
    fi
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    chmod 0755 "$root"
    mkdir -m 0700 "$root/config" "$root/state"
    touch "$root/lock"
    chmod 0600 "$root/lock"
    nonroot_pnm() {
        runuser -u nobody -- env PNM_CONFIG_DIR="$root/config" PNM_STATE_DIR="$root/state" \
            PNM_LOCK_FILE="$root/lock" PNM_OS_RELEASE_FILE="$TEST_ROOT/fixtures/os-release-debian-13" \
            bash "$PROJECT_ROOT/bin/pnm" "$@"
    }
    run_capture nonroot_pnm --json check
    assert_eq 1 "$RUN_RC" || return 1
    CHECK_JSON="$RUN_OUTPUT" python3 - <<'PY'
import json
import os
checks = {check["id"]: check for check in json.loads(os.environ["CHECK_JSON"])["checks"]}
assert checks["deployment_state"]["status"] == "UNKNOWN"
assert checks["configuration"]["status"] == "UNKNOWN"
assert checks["xray_runtime_config"]["status"] == "UNKNOWN"
assert checks["hysteria2_runtime_config"]["status"] == "UNKNOWN"
PY
    run_capture nonroot_pnm node show
    assert_eq 77 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    run_capture nonroot_pnm node links
    assert_eq 77 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    run_capture nonroot_pnm node links --help
    assert_eq 0 "$RUN_RC"
)

run_test 'non-root diagnostics remain available without asserting protected deployment state' test_nonroot_diagnostics_do_not_claim_deployment_ready
finish_tests
