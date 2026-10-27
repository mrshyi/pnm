#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

menu_install_fixture() (
    local mode="$1" canceled="${2:-no}" fixture input expected
    fixture="$(mktemp -d)" || return 1
    trap 'rm -rf -- "$fixture"' EXIT
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/output.sh"
    source "$PROJECT_ROOT/lib/menu.sh"
    PNM_CONFIG_DIR="$fixture"
    sed "s/^HY2_TLS_MODE=.*/HY2_TLS_MODE=$mode/;s/^PNM_CONFIGURED=.*/PNM_CONFIGURED=no/" \
        "$TEST_ROOT/fixtures/config-valid/node.conf" >"$fixture/node.conf"
    chmod 0600 "$fixture/node.conf"
    pnm_install() { printf '%s\n' "$@" >"$fixture/called"; }
    input=$'1\n0'
    expected=$'--apply\n--yes'
    if [[ "$mode" == external-ca ]]; then
        input=$'1\n/certificate with spaces\n/private key with spaces\n0'
        expected+=$'\n--tls-cert\n/certificate with spaces\n--tls-key\n/private key with spaces'
        if [[ "$canceled" == yes ]]; then input=$'1\n/certificate with spaces'; fi
    fi
    run_capture pnm_menu <<<"$input"
    assert_eq 0 "$RUN_RC" || return 1
    if [[ "$canceled" == yes ]]; then
        [[ ! -e "$fixture/called" ]]
    else
        [[ -f "$fixture/called" ]] || return 1
        assert_eq "$expected" "$(<"$fixture/called")"
    fi
)

test_menu_external_tls_installation() { menu_install_fixture external-ca; }
test_menu_selfsigned_installation() { menu_install_fixture selfsigned-pin; }
test_menu_canceled_external_tls_installation() { menu_install_fixture external-ca yes; }

test_external_tls_cli_usage() {
    local args
    for args in cert key; do
        run_capture "$PROJECT_ROOT/bin/pnm" install "--tls-$args"
        assert_eq 64 "$RUN_RC" || return 1
        assert_contains "$RUN_ERROR" 'requires a file' || return 1
    done
    run_capture "$PROJECT_ROOT/bin/pnm" install --tls-cert /unused/cert
    assert_eq 64 "$RUN_RC" || return 1
    assert_contains "$RUN_ERROR" 'must be supplied together' || return 1
    run_capture "$PROJECT_ROOT/bin/pnm" help install
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" '--tls-cert FILE --tls-key FILE'
}

test_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help
    assert_eq 0 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'Proxy Node Manager (PNM)'
}

test_version() {
    run_capture "$PROJECT_ROOT/bin/pnm" version
    assert_eq 0 "$RUN_RC" && assert_eq "pnm $(<"$PROJECT_ROOT/VERSION")" "$RUN_OUTPUT"
}

test_unknown_command() {
    run_capture "$PROJECT_ROOT/bin/pnm" does-not-exist
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_ERROR" 'Unknown command'
}

test_removed_broad_commands_return_usage() {
    local command_name
    for command_name in acceptance deploy preflight assets firewall client change reverify transaction; do
        run_capture "$PROJECT_ROOT/bin/pnm" "$command_name"
        assert_eq 64 "$RUN_RC" || return 1
        assert_contains "$RUN_ERROR" 'Unknown command' || return 1
    done
}

test_core_help_hides_broad_entrypoints() {
    run_capture "$PROJECT_ROOT/bin/pnm" help
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'update <core>' || return 1
    assert_not_contains "$RUN_OUTPUT" 'acceptance' || return 1
    assert_not_contains "$RUN_OUTPUT" 'tailscale'
}

test_node_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help node
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'pnm node <init|change|show|links|validate>' || return 1
    assert_contains "$RUN_OUTPUT" '--xray-sha256 SHA256'
}

test_installer_help() {
    run_capture bash "$PROJECT_ROOT/install.sh" --help
    assert_eq 0 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'Install the PNM CLI and runtime files'
}

test_non_tty_without_command() {
    run_capture "$PROJECT_ROOT/bin/pnm"
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'Usage:'
}

test_json_quiet_conflict() {
    run_capture "$PROJECT_ROOT/bin/pnm" --json --quiet check
    assert_eq 64 "$RUN_RC" && assert_contains "$RUN_ERROR" 'mutually exclusive'
}

test_status_json() {
    run_capture "$PROJECT_ROOT/bin/pnm" --json status
    assert_eq 0 "$RUN_RC" || return 1
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"] == "pnm.status.v1"' <<<"$RUN_OUTPUT"
}

test_update_cli_loads_approved_assets_before_preparation() (
    local root core
    if ((EUID != 0)); then
        printf '# SKIP: real update CLI requires root\n'
        return 0
    fi
    root="$(mktemp -d)"
    trap 'rm -rf -- "$root"' EXIT
    for core in xray hy2; do
        run_capture env PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid" \
            PNM_STATE_DIR="$root/state" PNM_LOCK_FILE="$root/lock" \
            bash "$PROJECT_ROOT/bin/pnm" update "$core" --version v0.0.1
        assert_eq 78 "$RUN_RC" || return 1
        assert_contains "$RUN_ERROR" 'Requested version is not approved' || return 1
        assert_not_contains "$RUN_ERROR" 'command not found' || return 1
        [[ ! -e "$root/state/transactions" ]] || return 1
    done
)

run_test 'help command' test_help
run_test 'menu forwards external TLS paths to the installation CLI' test_menu_external_tls_installation
run_test 'menu preserves self-signed installation without extra prompts' test_menu_selfsigned_installation
run_test 'menu does not install when external TLS path entry ends early' test_menu_canceled_external_tls_installation
run_test 'install TLS arguments require paired values and appear in help' test_external_tls_cli_usage
run_test 'version command' test_version
run_test 'unknown command returns usage' test_unknown_command
run_test 'broad commands are removed from the CLI' test_removed_broad_commands_return_usage
run_test 'help documents the dual-Core CLI' test_core_help_hides_broad_entrypoints
run_test 'node management help is available' test_node_help
run_test 'installer exposes usage information' test_installer_help
run_test 'non-TTY no-argument call does not block' test_non_tty_without_command
run_test 'json and quiet are mutually exclusive' test_json_quiet_conflict
run_test 'status emits valid JSON' test_status_json
run_test 'actual update CLI loads approvals before Core preparation' test_update_cli_loads_approved_assets_before_preparation
finish_tests
