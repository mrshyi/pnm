#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-valid"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/preflight.sh
source "$PNM_LIB_DIR/preflight.sh"
source "$PNM_LIB_DIR/service.sh"
source "$PNM_ADAPTER_DIR/systemd.sh"
source "$PNM_ADAPTER_DIR/network.sh"
# shellcheck source=../../lib/install.sh
source "$PNM_LIB_DIR/install.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

DEPLOY_STARTED=0
pnm_platform_supported() { return 0; }
pnm_platform_summary() { printf 'test platform\n'; }
pnm_systemd_available() { return 0; }
PNM_MISSING_TOOL=unzip
pnm_command_exists() { [[ "$1" != "$PNM_MISSING_TOOL" ]]; }
LISTENER_PRESENT=0
pnm_listener_present() { ((LISTENER_PRESENT == 1)); }
pnm_deploy_apply() { DEPLOY_STARTED=1; return 0; }

RECOVERY_VERIFIED=0
pnm_recovery_listener_owned() { ((RECOVERY_VERIFIED == 1)); }

test_port_preflight_allows_only_verified_recovery_listener() {
    LISTENER_PRESENT=1
    RECOVERY_VERIFIED=1
    pnm_preflight_reset
    pnm_preflight_port udp 8443
    assert_eq OK "${PNM_PREFLIGHT_STATUSES[0]}" || return 1
    assert_contains "${PNM_PREFLIGHT_SUMMARIES[0]}" 'verified PNM service' || return 1

    RECOVERY_VERIFIED=0
    pnm_preflight_reset
    pnm_preflight_port udp 8443
    assert_eq FAIL "${PNM_PREFLIGHT_STATUSES[0]}"
    LISTENER_PRESENT=0
}

test_committed_or_ambiguous_service_is_not_recovery_authorized() {
    RECOVERY_VERIFIED=0
    LISTENER_PRESENT=1
    pnm_preflight_reset
    pnm_preflight_port tcp 443
    assert_eq FAIL "${PNM_PREFLIGHT_STATUSES[0]}"
    assert_contains "${PNM_PREFLIGHT_DETAILS[0]}" 'unknown listener'
    LISTENER_PRESENT=0
}

test_repeat_install_refuses_a_committed_node() {
    local rc
    pnm_preflight_reset
    pnm_preflight_configuration
    assert_eq FAIL "${PNM_PREFLIGHT_STATUSES[0]}" || return 1
    assert_contains "${PNM_PREFLIGHT_SUMMARIES[0]}" 'already marked configured' || return 1
    run_capture pnm_install --apply --yes
    rc="$RUN_RC"
    assert_eq "$PNM_EXIT_FAIL" "$rc" || return 1
    assert_eq 0 "$DEPLOY_STARTED"
}

test_recovery_requires_a_secure_uncommitted_post_health_journal() (
    local temp_dir journal timestamp
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    PNM_STATE_DIR="$temp_dir/state"
    mkdir -p "$PNM_STATE_DIR/deployments/deploy-incomplete"
    journal="$PNM_STATE_DIR/deployments/deploy-incomplete/journal.tsv"
    timestamp='2026-10-19T00:00:00Z'
    printf '%s\tBEGIN\tdeployment orchestration\n%s\tPHASE_DONE\tcore-resources\n%s\tPHASE_DONE\txray-lifecycle\n%s\tPHASE_DONE\thysteria-lifecycle\n%s\tSTOPPED\tafter=post-health rc=78\n%s\tABANDONED\tdeployment closed without commit\n' \
        "$timestamp" "$timestamp" "$timestamp" "$timestamp" "$timestamp" "$timestamp" >"$journal"
    chmod 0700 "$PNM_STATE_DIR" "$PNM_STATE_DIR/deployments" "$PNM_STATE_DIR/deployments/deploy-incomplete" || return 1
    chmod 0600 "$journal" || return 1
    PNM_PREFLIGHT_NODE_CONFIG=([PNM_CONFIGURED]=no)
    pnm_recovery_has_failed_deployment_record || return 1

    chmod 0644 "$journal" || return 1
    if pnm_recovery_has_failed_deployment_record; then return 1; fi
    chmod 0600 "$journal" || return 1
    chmod 0755 "$PNM_STATE_DIR/deployments/deploy-incomplete" || return 1
    if pnm_recovery_has_failed_deployment_record; then return 1; fi
    chmod 0700 "$PNM_STATE_DIR/deployments/deploy-incomplete" || return 1

    printf '%s\tCOMMIT\t\n' "$timestamp" >>"$journal"
    if pnm_recovery_has_failed_deployment_record; then return 1; fi
    PNM_PREFLIGHT_NODE_CONFIG[PNM_CONFIGURED]=yes
    if pnm_recovery_has_failed_deployment_record; then return 1; fi
)

test_listener_attribution_uses_pid_not_process_name() {
    ss() { printf 'LISTEN 0 128 0.0.0.0:8443 0.0.0.0:* users:(("hysteria",pid=321,fd=4))\n'; }
    pnm_listener_owned_by_pid udp 8443 321 || return 1
    if pnm_listener_owned_by_pid udp 8443 322; then return 1; fi
    ss() { printf 'LISTEN 0 128 0.0.0.0:8443 0.0.0.0:* users:(("unrelated",pid=322,fd=4))\n'; }
    if pnm_listener_owned_by_pid udp 8443 321; then return 1; fi
    ss() { printf 'LISTEN 0 128 0.0.0.0:8443 0.0.0.0:* users:(("hysteria",pid=321,fd=4))\nLISTEN 0 128 127.0.0.1:8443 0.0.0.0:* users:(("unrelated",pid=322,fd=5))\n'; }
    if pnm_listener_owned_by_pid udp 8443 321; then return 1; fi
}

test_recorded_legacy_unit_is_recoverable_only_while_hash_matches() {
    local temp_dir unit_file transaction_dir target_hash encoded_target
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    transaction_dir="$PNM_STATE_DIR/transactions/tx-recovery"
    unit_file="$temp_dir/xray.service"
    mkdir -p "$transaction_dir"
    cat >"$unit_file" <<'EOF'
[Service]
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
NoNewPrivileges=true
ProtectSystem=strict
CapabilityBoundingSet=
AmbientCapabilities=
EOF
    target_hash="$(sha256sum "$unit_file" | awk '{print $1}')"
    encoded_target="$(printf '%s' "$unit_file" | base64 -w0)"
    printf 'APPLIED\txray_unit\t%s\tMISSING\tMISSING\t%s\n' "$encoded_target" "$target_hash" >"$transaction_dir/changes.tsv"
    PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS=(deploy-incomplete)
    stat() { [[ "$*" == *xray.service* ]] && printf '644|0\n' || printf '700|%s\n' "$EUID"; }
    pnm_tx_load_for_inspect() {
        PNM_TX_INSPECT_STATE=COMMITTED
        PNM_TX_INSPECT_OPERATION=sandbox-install
        PNM_TX_INSPECT_DEPLOYMENT_ID=deploy-incomplete
        return 0
    }
    pnm_tx_file_sha256() { sha256sum -- "$1" | awk '{print $1}'; }
    pnm_recovery_unit_has_committed_pnm_receipt "$unit_file" xray_unit || { rm -rf -- "$temp_dir"; return 1; }

    printf '\n# changed outside PNM\n' >>"$unit_file"
    if pnm_recovery_unit_has_committed_pnm_receipt "$unit_file" xray_unit; then rm -rf -- "$temp_dir"; return 1; fi
    unset -f stat pnm_tx_load_for_inspect pnm_tx_file_sha256
    rm -rf -- "$temp_dir"
}

test_dropin_check_accepts_empty_and_rejects_overrides() {
    local reported_dropins=''
    pnm_systemctl() {
        [[ "$1 $2 $3 $4" == 'show xray.service --property DropInPaths' ]] || return 1
        printf '%s\n' "$reported_dropins"
    }
    pnm_recovery_unit_has_no_dropins xray.service || return 1
    reported_dropins='/etc/systemd/system/xray.service.d/override.conf'
    if pnm_recovery_unit_has_no_dropins xray.service; then return 1; fi
    unset -f pnm_systemctl
}

test_missing_unzip_fails_install_dry_run_before_apply() {
    local rc
    run_capture pnm_install --dry-run
    rc="$RUN_RC"
    assert_eq 2 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'missing during Xray asset staging: unzip' || return 1
    assert_eq 0 "$DEPLOY_STARTED" || return 1

    PNM_DRY_RUN=0
    PNM_ASSUME_YES=0
    run_capture pnm_install --apply --yes
    assert_eq 2 "$RUN_RC" || return 1
    assert_contains "$RUN_OUTPUT" 'missing during Xray asset staging: unzip' || return 1
    assert_eq 0 "$DEPLOY_STARTED"
}

test_missing_python3_fails_install_dry_run_before_apply() {
    local rc
    PNM_MISSING_TOOL=python3
    PNM_DRY_RUN=0
    PNM_ASSUME_YES=0
    run_capture pnm_install --dry-run
    rc="$RUN_RC"
    PNM_MISSING_TOOL=unzip
    PNM_DRY_RUN=0
    PNM_ASSUME_YES=0
    assert_eq 2 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'missing during preflight/transaction: python3' || return 1
    assert_eq 0 "$DEPLOY_STARTED" || return 1
}

test_custom_ports_ignore_busy_defaults() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    cp "$PNM_CONFIG_DIR/node.conf" "$PNM_CONFIG_DIR/versions.conf" "$temp_dir/"
    sed -i -e 's/PNM_CONFIGURED=yes/PNM_CONFIGURED=no/' -e 's/XRAY_PORT=443/XRAY_PORT=1443/' -e 's/HY2_PORT=8443/HY2_PORT=18443/' "$temp_dir/node.conf"
    PNM_CONFIG_DIR="$temp_dir" PNM_MISSING_TOOL=''
    pnm_listener_present() { printf '%s:%s\n' "$1" "$2" >>"$temp_dir/queries"; [[ "$2" == 443 || "$2" == 8443 ]]; }
    pnm_preflight_collect
    assert_eq OK "$(pnm_preflight_overall)" || return 1
    assert_eq $'tcp:1443\nudp:18443' "$(<"$temp_dir/queries")"
)

test_busy_custom_ports_block_install_before_apply() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    cp "$PNM_CONFIG_DIR/node.conf" "$PNM_CONFIG_DIR/versions.conf" "$temp_dir/"
    sed -i -e 's/PNM_CONFIGURED=yes/PNM_CONFIGURED=no/' -e 's/XRAY_PORT=443/XRAY_PORT=1443/' -e 's/HY2_PORT=8443/HY2_PORT=18443/' "$temp_dir/node.conf"
    PNM_CONFIG_DIR="$temp_dir" PNM_MISSING_TOOL=''
    pnm_listener_present() { [[ "$2" == 1443 || "$2" == 18443 ]]; }
    run_capture pnm_install --apply --yes
    assert_eq "$PNM_EXIT_FAIL" "$RUN_RC" || return 1
    assert_eq 0 "$DEPLOY_STARTED" || return 1
    assert_contains "$RUN_OUTPUT" 'Required TCP/1443 is already in use' || return 1
    assert_contains "$RUN_OUTPUT" 'Required UDP/18443 is already in use'
)

test_invalid_node_does_not_probe_fallback_ports() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    cp "$PNM_CONFIG_DIR/node.conf" "$PNM_CONFIG_DIR/versions.conf" "$temp_dir/"
    sed -i 's/XRAY_PORT=443/XRAY_PORT=invalid/' "$temp_dir/node.conf"
    PNM_CONFIG_DIR="$temp_dir" PNM_MISSING_TOOL=''
    pnm_listener_present() { touch "$temp_dir/probed"; return 1; }
    pnm_preflight_collect
    assert_eq FAIL "$(pnm_preflight_overall)" || return 1
    [[ ! -e "$temp_dir/probed" ]]
)

test_recovery_dispatch_requires_the_configured_port() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    # Restore the real dispatcher; stop before any host resource is inspected.
    source "$PNM_LIB_DIR/preflight.sh"
    PNM_PREFLIGHT_NODE_CONFIG=([XRAY_PORT]=1443 [HY2_PORT]=18443)
    pnm_recovery_has_failed_deployment_record() { touch "$temp_dir/dispatched"; return 1; }
    if pnm_recovery_listener_owned tcp 1443; then return 1; fi
    [[ -e "$temp_dir/dispatched" ]] || return 1
    rm "$temp_dir/dispatched"
    if pnm_recovery_listener_owned udp 18443; then return 1; fi
    [[ -e "$temp_dir/dispatched" ]] || return 1
    rm "$temp_dir/dispatched"
    if pnm_recovery_listener_owned tcp 443; then return 1; fi
    if pnm_recovery_listener_owned udp 8443; then return 1; fi
    [[ ! -e "$temp_dir/dispatched" ]]
)

test_missing_openssl_is_classified_as_tls_stage_dependency() {
    local rc
    PNM_MISSING_TOOL=openssl
    run_capture pnm_install --dry-run
    rc="$RUN_RC"
    PNM_MISSING_TOOL=unzip
    assert_eq 2 "$rc" || return 1
    assert_contains "$RUN_OUTPUT" 'missing during TLS/secret generation: openssl' || return 1
    assert_eq 0 "$DEPLOY_STARTED"
}

run_test 'custom ports ignore busy default listeners' test_custom_ports_ignore_busy_defaults
run_test 'busy custom ports block install before apply' test_busy_custom_ports_block_install_before_apply
run_test 'invalid node configuration does not probe fallback ports' test_invalid_node_does_not_probe_fallback_ports
run_test 'recovery dispatch requires the configured protocol and port' test_recovery_dispatch_requires_the_configured_port
run_test 'missing unzip fails dry-run preflight before installation starts' test_missing_unzip_fails_install_dry_run_before_apply
run_test 'missing python3 fails dry-run preflight before installation starts' test_missing_python3_fails_install_dry_run_before_apply
run_test 'missing openssl is classified as a TLS dependency before apply' test_missing_openssl_is_classified_as_tls_stage_dependency
run_test 'port preflight allows only a verified PNM recovery listener' test_port_preflight_allows_only_verified_recovery_listener
run_test 'unknown and committed service listeners are not recovery-authorized' test_committed_or_ambiguous_service_is_not_recovery_authorized
run_test 'repeat install refuses a previously configured node' test_repeat_install_refuses_a_committed_node
run_test 'recovery requires a secure abandoned deployment that reached post-health' test_recovery_requires_a_secure_uncommitted_post_health_journal
run_test 'listener ownership is attributed by exact PID' test_listener_attribution_uses_pid_not_process_name
run_test 'recovery accepts recorded legacy Unit only while its file hash matches' test_recorded_legacy_unit_is_recoverable_only_while_hash_matches
run_test 'recovery accepts an empty DropInPaths property and rejects overrides' test_dropin_check_accepts_empty_and_rejects_overrides
finish_tests
