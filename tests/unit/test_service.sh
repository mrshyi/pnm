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
# shellcheck source=../../lib/service.sh
source "$PNM_LIB_DIR/service.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_xray_unit_policy() {
    local unit
    unit="$(pnm_render_xray_unit)"
    pnm_unit_validate_text "$unit" xray /usr/local/bin/xray || return 1
    assert_contains "$unit" 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json'
    assert_not_contains "$unit" 'tailscale'
}

test_hysteria_unit_policy() {
    local unit
    unit="$(pnm_render_hysteria_unit)"
    pnm_unit_validate_text "$unit" hysteria /usr/local/bin/hysteria || return 1
    assert_contains "$unit" 'ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml'
}

test_unit_install_is_atomic() {
    local temp_dir target mode
    temp_dir="$(mktemp -d)"
    pnm_systemd_install_unit pnm-xray.service pnm_render_xray_unit "$temp_dir" || { rm -rf -- "$temp_dir"; return 1; }
    target="$temp_dir/pnm-xray.service"
    mode="$(stat -c '%a' "$target")"
    rm -rf -- "$temp_dir"
    assert_eq 644 "$mode"
}

run_test 'Xray unit has isolated service policy' test_xray_unit_policy
run_test 'Hysteria2 unit has isolated service policy' test_hysteria_unit_policy
run_test 'systemd unit installation is atomic and mode 644' test_unit_install_is_atomic
finish_tests
