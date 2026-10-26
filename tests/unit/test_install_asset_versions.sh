#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/adapters/network.sh"
source "$PROJECT_ROOT/lib/sandbox-install.sh"
source "$TEST_ROOT/testlib.sh"

check_staged_versions() (
    local behavior="$1" expected_rc="$2" temp_dir rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_SANDBOX_ROOT=/
    PNM_SANDBOX_STAGING="$temp_dir/staging"
    PNM_SANDBOX_XRAY_ARCHIVE="$temp_dir/archive"
    PNM_SANDBOX_HY2_BINARY="$temp_dir/hysteria"
    : >"$PNM_SANDBOX_XRAY_ARCHIVE"
    printf '%s\n' '#!/usr/bin/env bash' '[[ "${1-}" == version ]] || exit 99' \
        'printf "Xray 1.0.0\\n"' >"$temp_dir/xray"
    printf '%s\n' '#!/usr/bin/env bash' '[[ "${1-}" == version ]] || exit 99' \
        'printf "Version: v2.0.0\\n"' >"$temp_dir/hysteria"
    case "$behavior" in
        xray-mismatch) sed -i 's/Xray 1.0.0/Xray 0.9.0/' "$temp_dir/xray" ;;
        hy2-mismatch) sed -i 's/v2.0.0/v1.9.0/' "$temp_dir/hysteria" ;;
        xray-unparseable) sed -i 's/Xray 1.0.0/unknown/' "$temp_dir/xray" ;;
        hy2-failed) printf '%s\n' '#!/usr/bin/env bash' 'exit 23' >"$temp_dir/hysteria" ;;
        matched) ;;
        *) return 1 ;;
    esac
    chmod 0700 "$temp_dir/xray" "$temp_dir/hysteria"
    # Only fixture staging/providers and publication are substituted. Real
    # version parsing executes safe known scripts; no host path can be written.
    pnm_asset_stage_xray_zip() { printf '%s/xray\n' "$temp_dir"; }
    pnm_asset_stage_hysteria_binary() { printf '%s/hysteria\n' "$temp_dir"; }
    pnm_sandbox_path() { printf '%s%s\n' "$temp_dir" "$1"; }
    pnm_tx_write_file() { printf '%s\n' "$3" >>"$temp_dir/writes"; }
    if pnm_sandbox_step_assets; then rc=0; else rc=$?; fi
    assert_eq "$expected_rc" "$rc" || return 1
    if ((expected_rc == 0)); then
        assert_eq $'xray_binary\nhysteria_binary' "$(<"$temp_dir/writes")"
    else
        [[ ! -e "$temp_dir/writes" ]]
    fi
)

test_wrong_xray() { check_staged_versions xray-mismatch 78; }
test_wrong_hy2() { check_staged_versions hy2-mismatch 78; }
test_unknown_xray() { check_staged_versions xray-unparseable 78; }
test_failed_hy2() { check_staged_versions hy2-failed 78; }
test_matched_pair() { check_staged_versions matched 0; }

run_test 'first-install Xray version mismatch refuses before either binary publication' test_wrong_xray
run_test 'first-install HY2 version mismatch refuses before either binary publication' test_wrong_hy2
run_test 'first-install unparseable Xray version refuses before publication' test_unknown_xray
run_test 'first-install failed HY2 version query refuses before publication' test_failed_hy2
run_test 'first-install matching approved pair permits both publications' test_matched_pair
finish_tests
