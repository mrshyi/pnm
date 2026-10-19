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
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/node.sh
source "$PNM_LIB_DIR/node.sh"
# shellcheck source=../../lib/render.sh
source "$PNM_LIB_DIR/render.sh"
# shellcheck source=../../lib/tls.sh
source "$PNM_LIB_DIR/tls.sh"
# shellcheck source=../../lib/core-ops.sh
source "$PNM_LIB_DIR/core-ops.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

PNM_TEST_APPLY_ROOT=''
PNM_TEST_APPLY_BACKUP=''
PNM_TEST_APPLY_ROLLBACK=''
PNM_TEST_APPLY_WRITTEN=0
PNM_TEST_APPLY_RESTARTS=0
PNM_TEST_APPLY_RESTART_FAIL=0
PNM_TEST_APPLY_HEALTH_CHECKS=0
PNM_TEST_APPLY_HEALTH_FAIL=0

pnm_test_apply_setup() {
    local -A apply_old_node=() apply_old_secret=()
    PNM_TEST_APPLY_ROOT="$(mktemp -d)"
    mkdir -p -- "$PNM_TEST_APPLY_ROOT/config/secrets" "$PNM_TEST_APPLY_ROOT/xray" "$PNM_TEST_APPLY_ROOT/stage"
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$PNM_TEST_APPLY_ROOT/config/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$PNM_TEST_APPLY_ROOT/config/secrets/reality.env"
    PNM_CONFIG_DIR="$PNM_TEST_APPLY_ROOT/config"
    PNM_XRAY_CONFIG="$PNM_TEST_APPLY_ROOT/xray/config.json"
    PNM_XRAY_BIN="$PNM_TEST_APPLY_ROOT/xray-bin"
    PNM_TEST_APPLY_BACKUP="$PNM_TEST_APPLY_ROOT/backup"
    PNM_TEST_APPLY_ROLLBACK=''
    PNM_TEST_APPLY_WRITTEN=0
    PNM_TEST_APPLY_RESTARTS=0
    PNM_TEST_APPLY_RESTART_FAIL=0
    PNM_TEST_APPLY_HEALTH_CHECKS=0
    PNM_TEST_APPLY_HEALTH_FAIL=0
    PNM_TX_ACTIVE=0
    pnm_load_node_config apply_old_node || return 1
    pnm_load_reality_secret apply_old_secret || return 1
    apply_old_node[XRAY_SERVER_NAME]='old.example.net'
    apply_old_node[XRAY_TARGET]='old.example.net:443'
    pnm_render_xray_config apply_old_node apply_old_secret >"$PNM_XRAY_CONFIG" || return 1
    cat >"$PNM_XRAY_BIN" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == x25519 ]]; then
    printf 'PrivateKey: fixture-private\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
    exit 0
fi
[[ "${PNM_TEST_REJECT_XRAY_CONFIG:-0}" != 1 ]]
EOF
    chmod 0755 -- "$PNM_XRAY_BIN"
}

pnm_test_apply_cleanup() {
    [[ -z "$PNM_TEST_APPLY_ROOT" ]] || rm -rf -- "$PNM_TEST_APPLY_ROOT"
    PNM_TEST_APPLY_ROOT=''
}

pnm_require_root() { return 0; }
pnm_core_lifecycle_snapshot() {
    PNM_LIFECYCLE_PRE_ACTIVE=active
    PNM_LIFECYCLE_PRE_ENABLED=enabled
}
pnm_core_fix_owner() { return 0; }
pnm_systemctl() {
    ((PNM_TEST_APPLY_RESTARTS += 1))
    if ((PNM_TEST_APPLY_RESTART_FAIL == 1 && PNM_TEST_APPLY_RESTARTS == 1)); then return 1; fi
}
pnm_systemd_unit_healthy() {
    ((PNM_TEST_APPLY_HEALTH_CHECKS += 1))
    if ((PNM_TEST_APPLY_HEALTH_FAIL == 1 && PNM_TEST_APPLY_HEALTH_CHECKS == 1)); then return 1; fi
}
pnm_tx_begin() { PNM_TX_ACTIVE=1; }
pnm_tx_add_rollback() { PNM_TEST_APPLY_ROLLBACK="$1"; }
pnm_tx_write_file() {
    cp -- "$2" "$PNM_TEST_APPLY_BACKUP" || return 1
    cp -- "$1" "$2"
    PNM_TEST_APPLY_WRITTEN=1
}
pnm_tx_restore_written_files() {
    ((PNM_TEST_APPLY_WRITTEN == 1)) || return 0
    cp -- "$PNM_TEST_APPLY_BACKUP" "$PNM_XRAY_CONFIG"
}
pnm_tx_rollback() {
    pnm_tx_restore_written_files || return 1
    "$PNM_TEST_APPLY_ROLLBACK"
}
pnm_tx_commit() { return 0; }
pnm_tx_close() { PNM_TX_ACTIVE=0; }
pnm_make_temp_dir() { printf '%s\n' "$PNM_TEST_APPLY_ROOT/stage"; }

test_xray_apply_validation_failure_preserves_runtime_config() {
    local original rc
    pnm_test_apply_setup || return 1
    original="$(<"$PNM_XRAY_CONFIG")"
    export PNM_TEST_REJECT_XRAY_CONFIG=1
    if pnm_core_apply_config xray; then rc=0; else rc=$?; fi
    unset PNM_TEST_REJECT_XRAY_CONFIG
    assert_eq "$original" "$(<"$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    pnm_test_apply_cleanup
    assert_eq 78 "$rc" || return 1
    [[ "$PNM_TEST_APPLY_RESTARTS" == 0 ]]
}

test_xray_apply_restart_failure_restores_previous_config_and_service() {
    local original rc
    pnm_test_apply_setup || return 1
    original="$(<"$PNM_XRAY_CONFIG")"
    PNM_TEST_APPLY_RESTART_FAIL=1
    if pnm_core_apply_config xray; then rc=0; else rc=$?; fi
    assert_eq 1 "$rc" || { pnm_test_apply_cleanup; return 1; }
    assert_eq "$original" "$(<"$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    assert_eq 2 "$PNM_TEST_APPLY_RESTARTS" || { pnm_test_apply_cleanup; return 1; }
    pnm_test_apply_cleanup
}

test_xray_apply_health_failure_restores_previous_config_and_service() {
    local original rc
    pnm_test_apply_setup || return 1
    original="$(<"$PNM_XRAY_CONFIG")"
    PNM_TEST_APPLY_HEALTH_FAIL=1
    if pnm_core_apply_config xray; then rc=0; else rc=$?; fi
    assert_eq 1 "$rc" || { pnm_test_apply_cleanup; return 1; }
    assert_eq "$original" "$(<"$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    assert_eq 2 "$PNM_TEST_APPLY_RESTARTS" || { pnm_test_apply_cleanup; return 1; }
    pnm_test_apply_cleanup
}

test_xray_apply_is_stable_when_repeated() {
    local first rc
    pnm_test_apply_setup || return 1
    pnm_core_apply_config xray || { pnm_test_apply_cleanup; return 1; }
    first="$(<"$PNM_XRAY_CONFIG")"
    pnm_core_apply_config xray || { pnm_test_apply_cleanup; return 1; }
    rc=$?
    assert_eq "$first" "$(<"$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    pnm_test_apply_cleanup
    assert_eq 0 "$rc"
}

test_hysteria_apply_rejects_unreadable_tls_before_apply() {
    local original rc old_hy2_config
    pnm_test_apply_setup || return 1
    mkdir -p -- "$PNM_CONFIG_DIR/secrets"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$PNM_CONFIG_DIR/secrets/hysteria.env"
    sed -i 's#^HY2_TLS_CERT_PATH=.*#HY2_TLS_CERT_PATH=/tmp/pnm-test-certificate-does-not-exist#' \
        "$PNM_CONFIG_DIR/secrets/hysteria.env"
    old_hy2_config="$PNM_HY2_CONFIG"
    mkdir -p -- "$PNM_TEST_APPLY_ROOT/hysteria"
    PNM_HY2_CONFIG="$PNM_TEST_APPLY_ROOT/hysteria/config.yaml"
    printf 'previous-runtime-config\n' >"$PNM_HY2_CONFIG"
    original="$(<"$PNM_HY2_CONFIG")"
    if pnm_core_apply_config hy2; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || { PNM_HY2_CONFIG="$old_hy2_config"; pnm_test_apply_cleanup; return 1; }
    assert_eq "$original" "$(<"$PNM_HY2_CONFIG")" || { PNM_HY2_CONFIG="$old_hy2_config"; pnm_test_apply_cleanup; return 1; }
    assert_eq 0 "$PNM_TEST_APPLY_RESTARTS" || { PNM_HY2_CONFIG="$old_hy2_config"; pnm_test_apply_cleanup; return 1; }
    PNM_HY2_CONFIG="$old_hy2_config"
    pnm_test_apply_cleanup
}

test_core_mapping_is_fixed() {
    pnm_core_resolve xray || return 1
    assert_eq xray "$PNM_CORE_ID" || return 1
    assert_eq xray.service "$PNM_CORE_UNIT" || return 1
    pnm_core_resolve hy2 || return 1
    assert_eq hysteria2 "$PNM_CORE_ID" || return 1
    assert_eq hysteria-server.service "$PNM_CORE_UNIT"
}

test_unknown_core_is_rejected() {
    local rc
    if pnm_core_resolve ssh; then rc=0; else rc=$?; fi
    assert_eq 64 "$rc"
}

test_log_options_are_validated_before_journal_access() {
    local rc
    if pnm_core_log xray --lines 0; then rc=0; else rc=$?; fi
    assert_eq 64 "$rc"
}

test_dry_run_cannot_mutate_a_core() {
    local rc
    PNM_DRY_RUN=1
    if pnm_core_command restart xray; then rc=0; else rc=$?; fi
    PNM_DRY_RUN=0
    assert_eq 64 "$rc"
}

test_core_command_help() {
    run_capture "$PROJECT_ROOT/bin/pnm" help apply
    assert_eq 0 "$RUN_RC" && assert_contains "$RUN_OUTPUT" 'pnm apply <xray|hy2>'
}

run_test 'core to unit mapping is explicit' test_core_mapping_is_fixed
run_test 'unsupported service names are rejected' test_unknown_core_is_rejected
run_test 'log options reject invalid line counts' test_log_options_are_validated_before_journal_access
run_test 'dry-run blocks mutating core commands' test_dry_run_cannot_mutate_a_core
run_test 'core command help is available' test_core_command_help
run_test 'invalid Xray candidate leaves current runtime config untouched' test_xray_apply_validation_failure_preserves_runtime_config
run_test 'Xray restart failure restores previous config and service' test_xray_apply_restart_failure_restores_previous_config_and_service
run_test 'Xray health-check failure restores previous config and service' test_xray_apply_health_failure_restores_previous_config_and_service
run_test 'repeated Xray apply produces stable runtime config' test_xray_apply_is_stable_when_repeated
run_test 'Hysteria2 apply rejects invalid TLS before changing runtime config' test_hysteria_apply_rejects_unreadable_tls_before_apply
finish_tests
