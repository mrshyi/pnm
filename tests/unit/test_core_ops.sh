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
source "$PNM_LIB_DIR/lock.sh"
source "$PNM_LIB_DIR/transaction.sh"
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
    PNM_STATE_DIR="$PNM_TEST_APPLY_ROOT/state"
    PNM_LOCK_FILE="$PNM_TEST_APPLY_ROOT/pnm.lock"
    mkdir -p -- "$PNM_STATE_DIR"
    PNM_XRAY_CONFIG="$PNM_TEST_APPLY_ROOT/xray/config.json"
    PNM_XRAY_BIN="$PNM_TEST_APPLY_ROOT/xray-bin"
    PNM_TEST_APPLY_BACKUP="$PNM_TEST_APPLY_ROOT/backup"
    PNM_TEST_APPLY_ROLLBACK=''
    PNM_TEST_APPLY_WRITTEN=0
    PNM_TEST_APPLY_RESTARTS=0
    PNM_TEST_APPLY_RESTART_FAIL=0
    PNM_TEST_APPLY_HEALTH_CHECKS=0
    PNM_TEST_APPLY_HEALTH_FAIL=0
    PNM_TEST_APPLY_LISTENER_RC=0
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
if [[ "${PNM_TEST_REQUIRE_XRAY_FORMAT:-0}" == 1 && "${1-}" == run ]]; then
    # Match the real Core's auto-format contract: an unrecognised filename
    # cannot be validated as JSON merely because its contents are JSON.
    [[ "$#" == 4 && "$2" == -test && "$3" == -config && "$4" == *.json ]] || exit 23
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
pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
pnm_core_lifecycle_snapshot() {
    PNM_LIFECYCLE_PRE_ACTIVE=active
    PNM_LIFECYCLE_PRE_ENABLED=enabled
}
pnm_systemd_active_state() { printf 'active\n'; }
pnm_systemd_enabled_state() { printf 'enabled\n'; }
# This suite maps all transaction I/O; evidence tests exercise the real publisher.
pnm_core_restore_write_file() { pnm_tx_write_file "$1" "$2" "$3" "$4" required; }
pnm_systemctl() {
    ((PNM_TEST_APPLY_RESTARTS += 1))
    if ((PNM_TEST_APPLY_RESTART_FAIL == 1 && PNM_TEST_APPLY_RESTARTS == 1)); then return 1; fi
}
pnm_core_runtime_listener_ready() { return "${PNM_TEST_APPLY_LISTENER_RC:-0}"; }
pnm_systemd_unit_healthy() {
    ((PNM_TEST_APPLY_HEALTH_CHECKS += 1))
    if ((PNM_TEST_APPLY_HEALTH_FAIL == 1 && PNM_TEST_APPLY_HEALTH_CHECKS == 1)); then return 1; fi
}
pnm_tx_begin() { PNM_TX_ACTIVE=1; }
pnm_tx_prepare_directory() { pnm_mkdir_mode "$2" "$1"; }
pnm_tx_restore_directories() { return 0; }
pnm_tx_add_rollback() { PNM_TEST_APPLY_ROLLBACK="$1"; }
pnm_tx_write_file() {
    if [[ "$2" == "$PNM_XRAY_CONFIG" ]]; then
        cp -- "$2" "$PNM_TEST_APPLY_BACKUP" || return 1
    fi
    mkdir -p -- "$(dirname -- "$2")" || return 1
    cp -- "$1" "$2"
    chmod "$4" -- "$2" || return 1
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
pnm_make_temp_dir() { printf -v "$1" '%s' "$PNM_TEST_APPLY_ROOT/stage"; }

test_apply_close_failure_is_not_reported_as_success() {
    local failed=0
    pnm_test_apply_setup || return 1
    pnm_tx_close() { PNM_TX_ACTIVE=0; return 70; }
    run_capture pnm_core_apply_config xray
    assert_eq 70 "$RUN_RC" || failed=1
    assert_not_contains "$RUN_OUTPUT" 'configuration applied' || failed=1
    assert_eq 0 "$PNM_LOCK_DEPTH" || failed=1
    pnm_test_apply_cleanup
    return "$failed"
}

test_xray_apply_supports_core_auto_format() (
    pnm_test_apply_setup || return 1
    trap pnm_test_apply_cleanup EXIT
    export PNM_TEST_REQUIRE_XRAY_FORMAT=1
    run_capture pnm_core_apply_config xray
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq 1 "$PNM_TEST_APPLY_RESTARTS" || return 1
    assert_contains "$RUN_OUTPUT" 'configuration applied'
)

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

test_xray_apply_listener_failure_restores_previous_config_and_service() {
    local original rc
    pnm_test_apply_setup || return 1
    original="$(<"$PNM_XRAY_CONFIG")"
    PNM_TEST_APPLY_LISTENER_RC=70
    if pnm_core_apply_config xray; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || { pnm_test_apply_cleanup; return 1; }
    assert_eq "$original" "$(<"$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    assert_eq 2 "$PNM_TEST_APPLY_RESTARTS" || { pnm_test_apply_cleanup; return 1; }
    [[ ! -e "$PNM_STATE_DIR/cores/xray/applied.env" ]] || { pnm_test_apply_cleanup; return 1; }
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

test_successful_apply_records_the_exact_runtime_config_digest() {
    local record status
    pnm_test_apply_setup || return 1
    pnm_core_apply_config xray || { pnm_test_apply_cleanup; return 1; }
    record="$PNM_STATE_DIR/cores/xray/applied.env"
    [[ -f "$record" ]] || { pnm_test_apply_cleanup; return 1; }
    status="$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || { pnm_test_apply_cleanup; return 1; }
    pnm_test_apply_cleanup
    assert_eq confirmed "$status"
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

test_core_update_metadata_publish_failure_keeps_original_code_and_reports_rollback_failure() {
    local temp_dir rc writes=0 rollback_calls=0
    temp_dir="$(mktemp -d)"
    printf 'binary-old\n' >"$temp_dir/previous"
    printf 'metadata\n' >"$temp_dir/previous.env"
    pnm_tx_write_file() {
        ((writes += 1))
        [[ "$3" != previous_metadata ]] || return 69
        cp -- "$1" "$2"
    }
    pnm_tx_rollback() { ((rollback_calls += 1)); return 70; }
    pnm_tx_close() { :; }
    if pnm_core_publish_previous_state "$temp_dir/previous" "$temp_dir/previous.env" \
        "$temp_dir/published-binary" "$temp_dir/published-meta"; then
        rc=0
    else
        rc=$?
    fi
    assert_eq 69 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 'previous version metadata publication' "$PNM_CORE_UPDATE_FAILURE_STAGE" || { rm -rf -- "$temp_dir"; return 1; }
    run_capture pnm_core_update_abort update "$PNM_CORE_UPDATE_FAILURE_STAGE" "$rc"
    rc="$RUN_RC"
    rm -rf -- "$temp_dir"
    assert_eq 69 "$rc" || return 1
    assert_eq 2 "$writes" || return 1
    assert_eq 1 "$rollback_calls" || return 1
    assert_contains "$RUN_ERROR" 'rollback failed (rc=70)' || return 1
    assert_contains "$RUN_ERROR" 'recovery files were retained'
}

test_restore_validates_all_staged_assets_before_apply() {
    local temp_dir rc
    temp_dir="$(mktemp -d)"
    mkdir -p "$temp_dir/etc/pnm/secrets" "$temp_dir/etc/hysteria/tls" \
        "$temp_dir/etc/systemd/system" "$temp_dir/usr/local/bin" "$temp_dir/usr/local/etc/xray"
    touch "$temp_dir/etc/pnm/node.conf" "$temp_dir/etc/pnm/versions.conf" \
        "$temp_dir/etc/pnm/secrets/reality.env" "$temp_dir/etc/pnm/secrets/hysteria.env" \
        "$temp_dir/etc/hysteria/tls/server.crt" "$temp_dir/etc/hysteria/tls/server.key" \
        "$temp_dir/etc/hysteria/config.yaml" "$temp_dir/usr/local/etc/xray/config.json" \
        "$temp_dir/usr/local/bin/xray" "$temp_dir/usr/local/bin/hysteria"
    cat >"$temp_dir/etc/systemd/system/xray.service" <<'EOF'
[Service]
User=xray
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
NoNewPrivileges=true
ProtectSystem=strict
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
EOF
    cat >"$temp_dir/etc/systemd/system/hysteria-server.service" <<'EOF'
[Service]
User=hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
NoNewPrivileges=true
ProtectSystem=strict
CapabilityBoundingSet=
AmbientCapabilities=
EOF
    PNM_TEST_RESTORE_XRAY_INVALID=1
    PNM_TEST_RESTORE_HY2_CALLS=0
    cp -- "$TEST_ROOT/fixtures/config-secrets/node.conf" "$temp_dir/etc/pnm/node.conf"
    printf 'PNM_PROFILE=dual\n' >>"$temp_dir/etc/pnm/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$temp_dir/etc/pnm/versions.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/"*.env "$temp_dir/etc/pnm/secrets/"
    pnm_validate_node_config() { return 0; }
    pnm_validate_versions_config() { return 0; }
    pnm_validate_reality_secret_config() { return 0; }
    pnm_validate_hysteria_secret_config() { return 0; }
    pnm_unit_validate_text() { return 0; }
    pnm_systemd_validate_unit_file() { return 0; }
    pnm_systemd_validate_unit_file() { return 0; }
    pnm_binary_version_number() { [[ "$2" == xray ]] && printf '1.0.0\n' || printf '2.0.0\n'; }
    pnm_capture() { [[ "$PNM_TEST_RESTORE_XRAY_INVALID" != 1 ]]; }
    pnm_hysteria_config_validate_candidate() { ((PNM_TEST_RESTORE_HY2_CALLS += 1)); }
    pnm_tls_validate_pair() { return 0; }
    pnm_tls_certificate_check() { printf 'OK|fixture certificate is valid\n'; }
    pnm_hysteria_tls_server_name() { return 0; }

    if pnm_core_restore_validate_staged "$temp_dir"; then rc=0; else rc=$?; fi
    assert_eq "$PNM_EXIT_CONFIG" "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 0 "$PNM_TEST_RESTORE_HY2_CALLS" || { rm -rf -- "$temp_dir"; return 1; }
    PNM_TEST_RESTORE_XRAY_INVALID=0
    pnm_core_restore_validate_staged "$temp_dir" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 1 "$PNM_TEST_RESTORE_HY2_CALLS"
    rm -rf -- "$temp_dir"
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
run_test 'configuration close failure suppresses success and releases the outer lock' test_apply_close_failure_is_not_reported_as_success
run_test 'invalid Xray candidate leaves current runtime config untouched' test_xray_apply_validation_failure_preserves_runtime_config
run_test 'Xray apply candidates support the Core auto-format loader' test_xray_apply_supports_core_auto_format
run_test 'Xray restart failure restores previous config and service' test_xray_apply_restart_failure_restores_previous_config_and_service
run_test 'Xray health-check failure restores previous config and service' test_xray_apply_health_failure_restores_previous_config_and_service
run_test 'apply refuses an active Core without its listener and restores prior state' test_xray_apply_listener_failure_restores_previous_config_and_service
run_test 'repeated Xray apply produces stable runtime config' test_xray_apply_is_stable_when_repeated
run_test 'successful Xray apply records the exact applied configuration digest' test_successful_apply_records_the_exact_runtime_config_digest
run_test 'Hysteria2 apply rejects invalid TLS before changing runtime config' test_hysteria_apply_rejects_unreadable_tls_before_apply
run_test 'Core update preserves the original error and reports rollback failure' test_core_update_metadata_publish_failure_keeps_original_code_and_reports_rollback_failure
run_test 'Restore validates staged Core, unit, and TLS resources before applying them' test_restore_validates_all_staged_assets_before_apply
finish_tests
