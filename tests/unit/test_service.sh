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
    assert_contains "$unit" $'User=xray\nGroup=xray\n' || return 1
    assert_contains "$unit" $'NoNewPrivileges=true\n' || return 1
    assert_contains "$unit" $'CapabilityBoundingSet=CAP_NET_BIND_SERVICE\n' || return 1
    assert_contains "$unit" $'AmbientCapabilities=CAP_NET_BIND_SERVICE\n' || return 1
    assert_contains "$unit" 'ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json'
    assert_not_contains "$unit" 'CAP_NET_ADMIN'
    assert_not_contains "$unit" 'tailscale'
}

test_hysteria_unit_policy() {
    local unit
    unit="$(pnm_render_hysteria_unit)"
    pnm_unit_validate_text "$unit" hysteria /usr/local/bin/hysteria || return 1
    assert_contains "$unit" $'CapabilityBoundingSet=\n' || return 1
    assert_contains "$unit" $'AmbientCapabilities=\n' || return 1
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

test_rendered_units_validate_with_real_systemd() (
    local temp_dir target unit
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf '#!/bin/sh\nexit 99\n' >"$temp_dir/core" || return 1
    chmod 0700 "$temp_dir/core" || return 1
    # Isolate the verifier from unrelated host units; no service is started.
    for target in basic.target sysinit.target shutdown.target network-online.target; do
        printf '[Unit]\nDescription=PNM offline fixture\nDefaultDependencies=no\n' >"$temp_dir/$target" || return 1
    done
    pnm_render_xray_unit | sed "s#/usr/local/bin/xray#$temp_dir/core#" >"$temp_dir/xray.service" || return 1
    pnm_render_hysteria_unit | sed "s#/usr/local/bin/hysteria#$temp_dir/core#" >"$temp_dir/hysteria-server.service" || return 1
    for unit in xray.service hysteria-server.service; do
        SYSTEMD_UNIT_PATH="$temp_dir" pnm_systemd_validate_unit_file "$temp_dir/$unit" || return 1
        chmod 0600 "$temp_dir/core" || return 1
        if SYSTEMD_UNIT_PATH="$temp_dir" pnm_systemd_validate_unit_file "$temp_dir/$unit"; then return 1; fi
        chmod 0700 "$temp_dir/core" || return 1
    done
)

run_test 'Xray unit has isolated service policy' test_xray_unit_policy
run_test 'Hysteria2 unit has isolated service policy' test_hysteria_unit_policy
run_test 'systemd unit installation is atomic and mode 644' test_unit_install_is_atomic
run_test 'generated units pass the real systemd verifier and reject non-executable Core fixtures' test_rendered_units_validate_with_real_systemd
finish_tests
