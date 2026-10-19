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
# shellcheck source=../../lib/preflight.sh
source "$PNM_LIB_DIR/preflight.sh"
# shellcheck source=../../lib/install.sh
source "$PNM_LIB_DIR/install.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

DEPLOY_STARTED=0
pnm_platform_supported() { return 0; }
pnm_platform_summary() { printf 'test platform\n'; }
pnm_systemd_available() { return 0; }
pnm_command_exists() { [[ "$1" != unzip ]]; }
pnm_preflight_configuration() { pnm_preflight_add config OK 'Configuration is valid' ''; }
pnm_preflight_port() { pnm_preflight_add "port_$1_$2" OK 'Port is free' ''; }
pnm_deploy_apply() { DEPLOY_STARTED=1; return 0; }

test_missing_unzip_fails_install_dry_run_before_apply() {
    local rc
    run_capture pnm_install --dry-run
    rc="$RUN_RC"
    assert_eq 2 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'missing: unzip' || return 1
    assert_eq 0 "$DEPLOY_STARTED" || return 1

    PNM_DRY_RUN=0
    PNM_ASSUME_YES=0
    run_capture pnm_install --apply --yes
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'missing: unzip' || return 1
    assert_eq 0 "$DEPLOY_STARTED"
}

run_test 'missing unzip fails dry-run preflight before installation starts' test_missing_unzip_fails_install_dry_run_before_apply
finish_tests
