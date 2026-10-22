#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
source "$PNM_LIB_DIR/common.sh"
source "$PNM_LIB_DIR/output.sh"
source "$PNM_LIB_DIR/config.sh"
source "$PNM_LIB_DIR/render.sh"
source "$PNM_LIB_DIR/lock.sh"
source "$PNM_LIB_DIR/transaction.sh"
source "$PNM_LIB_DIR/lifecycle.sh"
source "$PNM_LIB_DIR/core-ops.sh"
source "$PROJECT_ROOT/adapters/network.sh"
source "$TEST_ROOT/testlib.sh"
# Preserve trusted library functions for deterministic edits between stages.
source <(declare -f pnm_core_record_applied_config | sed '1s/pnm_core_record_applied_config/pnm_test_real_record_applied_config/')
source <(declare -f pnm_core_applied_config_status | sed '1s/pnm_core_applied_config_status/pnm_test_real_applied_status/')
source <(declare -f pnm_tx_manifest_append | sed '1s/pnm_tx_manifest_append/pnm_test_real_manifest_append/')

suite_root="$(mktemp -d)"
trap 'rm -rf -- "$suite_root"' EXIT

make_version_binary() {
    cat >"$1" <<EOF
#!/usr/bin/env bash
[[ "\${1-}" != run ]] || exit 0
printf 'Version: $2\n'
EOF
    chmod 0755 "$1"
}

prepare_evidence_fixture() {
    fixture_root="$(mktemp -d "$suite_root/case.XXXXXXXX")"
    PNM_STATE_DIR="$fixture_root/state" PNM_CONFIG_DIR="$fixture_root/config"
    PNM_LOCK_FILE="$fixture_root/lock/pnm.lock"
    PNM_XRAY_BIN="$fixture_root/xray" PNM_HY2_BIN="$fixture_root/hysteria"
    PNM_XRAY_CONFIG="$fixture_root/xray.json" PNM_HY2_CONFIG="$fixture_root/hysteria.yaml"
    mkdir -m 0700 "$PNM_STATE_DIR" "$PNM_CONFIG_DIR"
    cp -R "$TEST_ROOT/fixtures/config-secrets/." "$PNM_CONFIG_DIR/"
    printf '{}\n' >"$PNM_XRAY_CONFIG"
    printf 'fixture: configuration\n' >"$PNM_HY2_CONFIG"
    make_version_binary "$PNM_XRAY_BIN" 1.2.3
    make_version_binary "$PNM_HY2_BIN" 1.2.3
    declare -gA fixture_invocations=([xray.service]=0123456789abcdef0123456789abcdef [hysteria-server.service]=0123456789abcdef0123456789abcdef)
    declare -gA fixture_restarts=([xray.service]=0 [hysteria-server.service]=0)
    declare -gA fixture_active=([xray.service]=active [hysteria-server.service]=active)
    fixture_health_failures=0 fixture_edit_record=0 fixture_edit_config=0
    pnm_test_record_applied_config xray "$PNM_XRAY_CONFIG"
    pnm_test_record_applied_config hysteria2 "$PNM_HY2_CONFIG"
    local core
    for core in xray hysteria2; do
        make_version_binary "$PNM_STATE_DIR/cores/$core/previous" 1.2.2
        printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=1.2.2\n' "$core" >"$PNM_STATE_DIR/cores/$core/previous.env"
        chmod 0600 "$PNM_STATE_DIR/cores/$core/previous.env"
    done
}

# Only external services, downloads and Core-specific validation are simulated.
# CLI operations, versions, file receipts, recovery and applied checks are real.
pnm_require_root() { return 0; }
pnm_make_temp_dir() { mktemp -d "$fixture_root/stage.XXXXXXXX"; }
pnm_systemd_active_state() { printf '%s\n' "${fixture_active[$1]}"; }
pnm_systemd_enabled_state() { printf 'enabled\n'; }
pnm_systemd_daemon_reload() { return 0; }
pnm_systemd_show_value() { printf '%s\n' "${fixture_invocations[$1]}"; }
pnm_systemctl() {
    if [[ "$1" == stop ]]; then fixture_active[$2]=inactive; return 0; fi
    [[ "$1" == restart ]] || return 70
    fixture_active[$2]=active
    ((fixture_restarts[$2] += 1))
    printf -v 'fixture_invocations[$2]' '%032x' "${fixture_restarts[$2]}"
    if ((fixture_edit_record == 1)); then
        printf '# external edit\n' >>"$PNM_STATE_DIR/cores/$PNM_CORE_ID/applied.env"
        fixture_edit_record=0
    fi
    if ((fixture_edit_config == 1)); then
        printf '\n# external edit\n' >>"$PNM_CORE_CONFIG"
        fixture_edit_config=0
    fi
}
pnm_systemd_unit_healthy() {
    [[ "${fixture_active[$1]}" == active ]] || return 1
    if ((fixture_health_failures > 0)); then
        ((fixture_health_failures -= 1))
        return 1
    fi
    return 0
}
pnm_systemd_stop() { pnm_systemctl stop "$1"; }
pnm_check_deploy_core_health() { pnm_systemd_unit_healthy "$PNM_CORE_UNIT"; }
pnm_assets_load() { declare -gA PNM_ASSET_VERSIONS=([XRAY_VERSION]=v1.2.4 [XRAY_SHA256]=fixture [HY2_VERSION]=v1.2.4 [HY2_SHA256]=fixture); }
pnm_asset_download_verified() { make_version_binary "$4" 1.2.4; }
pnm_asset_stage_xray_zip() { printf '%s\n' "$1"; }
pnm_asset_stage_hysteria_binary() { printf '%s\n' "$1"; }
pnm_hysteria_config_validate_candidate() { return 0; }
pnm_tls_validate_pair() { return 0; }

assert_peer_untouched() {
    local peer=hysteria2 unit=hysteria-server.service config="$PNM_HY2_CONFIG"
    if [[ "$1" == hysteria2 ]]; then peer=xray unit=xray.service config="$PNM_XRAY_CONFIG"; fi
    assert_eq 0 "${fixture_restarts[$unit]}" || return 1
    assert_eq confirmed "$(pnm_core_applied_config_status "$peer" "$config")"
}

test_restart_keeps_confirmed_evidence() {
    local core
    for core in xray hysteria2; do
        prepare_evidence_fixture
        pnm_core_restart "$core" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
        assert_peer_untouched "$core" || return 1
    done
}

test_update_and_rollback_keep_confirmed_evidence() {
    local core
    for core in xray hysteria2; do
        prepare_evidence_fixture
        pnm_core_update "$core" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
        assert_eq 1.2.4 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
        pnm_core_rollback "$core" || return 1
        assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
        assert_eq 1.2.3 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
        assert_peer_untouched "$core" || return 1
    done
}

test_missing_evidence_is_not_promoted() {
    local core operation state original_hash record
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            for state in missing changed damaged; do
                prepare_evidence_fixture
                record="$PNM_STATE_DIR/cores/$core/applied.env"
                case "$state" in
                    missing) rm "$record" ;;
                    changed) sed -i 's/SERVICE_INVOCATION_ID=.*/SERVICE_INVOCATION_ID=ffffffffffffffffffffffffffffffff/' "$record" ;;
                    damaged) printf 'SCHEMA_VERSION=invalid\n' >"$record" ;;
                esac
                original_hash=MISSING
                [[ ! -e "$record" ]] || original_hash="$(pnm_tx_file_sha256 "$record")"
                "pnm_core_$operation" "$core" || return 1
                if [[ "$state" == missing ]]; then
                    [[ ! -e "$record" ]] || return 1
                else
                    assert_eq "$original_hash" "$(pnm_tx_file_sha256 "$record")" || return 1
                fi
                assert_peer_untouched "$core" || return 1
            done
        done
    done
}

test_health_failure_recovers_confirmed_evidence() {
    local core operation rc
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            fixture_health_failures=1
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            [[ "$rc" != 0 ]] || return 1
            ((fixture_restarts[$PNM_CORE_UNIT] > 0)) || return 1
            assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
            assert_eq 1.2.3 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
            assert_peer_untouched "$core" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
        done
    done
}

test_applied_write_failure_recovers_original_state() {
    local core operation rc
    pnm_core_record_applied_config() { return 73; }
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 73 "$rc" || return 1
            assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
            assert_eq 1.2.3 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
            assert_peer_untouched "$core" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
        done
    done
}

test_commit_failure_recovers_confirmed_evidence() {
    local core operation rc
    pnm_tx_commit() { return 73; }
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 73 "$rc" || return 1
            assert_eq confirmed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
            assert_eq 1.2.3 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
            assert_peer_untouched "$core" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
        done
    done
}

test_inactive_baseline_recovers_without_certifying_a_stopped_service() {
    local original_hash rc
    prepare_evidence_fixture
    fixture_active[xray.service]=inactive
    original_hash="$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/xray/applied.env")"
    fixture_health_failures=1
    if pnm_core_restart xray; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq inactive "${fixture_active[xray.service]}" || return 1
    assert_eq "$original_hash" "$(pnm_tx_file_sha256 "$PNM_STATE_DIR/cores/xray/applied.env")" || return 1
    assert_eq 0 "$PNM_TX_RECOVERY_REQUIRED" || return 1
    assert_peer_untouched xray
}

test_external_applied_edit_is_retained() {
    prepare_evidence_fixture
    fixture_edit_record=1
    local rc
    if pnm_core_restart xray; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_contains "$(<"$PNM_STATE_DIR/cores/xray/applied.env")" '# external edit' || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED"
}

test_post_publication_metadata_edit_is_retained() {
    local core operation rc
    pnm_tx_commit() {
        chmod 0640 "$PNM_STATE_DIR/cores/$PNM_CORE_ID/applied.env"
        return 73
    }
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 73 "$rc" || return 1
            assert_eq 640 "$(stat -c '%a' "$PNM_STATE_DIR/cores/$core/applied.env")" || return 1
            assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
            assert_peer_untouched "$core" || return 1
        done
    done
}

test_config_edit_at_publication_is_not_certified() {
    local core operation rc
    pnm_core_record_applied_config() {
        printf '\n# edit before applied publication\n' >>"$2"
        pnm_test_real_record_applied_config "$@"
    }
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 70 "$rc" || return 1
            assert_eq changed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
            assert_contains "$(<"$PNM_CORE_CONFIG")" '# edit before applied publication' || return 1
            assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
            assert_peer_untouched "$core" || return 1
        done
    done
}

test_metadata_is_enrolled_before_post_write_receipts() {
    local core operation rc
    pnm_tx_manifest_append() {
        if [[ "$1" == APPLIED && "$2" == applied_* ]]; then
            chmod 0640 "$3"
            return 73
        fi
        pnm_test_real_manifest_append "$@"
    }
    for core in xray hysteria2; do
        for operation in restart update rollback; do
            prepare_evidence_fixture
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 73 "$rc" || return 1
            assert_eq 640 "$(stat -c '%a' "$PNM_STATE_DIR/cores/$core/applied.env")" || return 1
            assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
            assert_peer_untouched "$core" || return 1
        done
    done
}

test_config_edit_during_capture_is_rejected_before_restart() {
    local rc
    prepare_evidence_fixture
    touch "$fixture_root/edit-after-status"
    pnm_core_applied_config_status() {
        local status
        status="$(pnm_test_real_applied_status "$@")" || return 1
        if [[ -f "$fixture_root/edit-after-status" ]]; then
            rm "$fixture_root/edit-after-status"
            printf '\n# edit during baseline capture\n' >>"$2"
        fi
        printf '%s\n' "$status"
    }
    if pnm_core_restart xray; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq 0 "${fixture_restarts[xray.service]}" || return 1
    assert_eq changed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
}

test_external_config_edit_is_not_confirmed() {
    prepare_evidence_fixture
    fixture_edit_config=1
    local rc
    if pnm_core_restart xray; then rc=0; else rc=$?; fi
    assert_eq 70 "$rc" || return 1
    assert_eq changed "$(pnm_core_applied_config_status xray "$PNM_XRAY_CONFIG")" || return 1
    assert_contains "$(<"$PNM_XRAY_CONFIG")" '# external edit' || return 1
    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED"
}

run_test 'restart retains confirmed evidence for each Core' test_restart_keeps_confirmed_evidence
run_test 'update and rollback retain confirmed evidence for each Core' test_update_and_rollback_keep_confirmed_evidence
run_test 'lifecycle commands retain missing changed and damaged evidence' test_missing_evidence_is_not_promoted
run_test 'health failure recovers prior confirmed evidence and binary' test_health_failure_recovers_confirmed_evidence
run_test 'applied write failure recovers prior confirmed evidence and binary' test_applied_write_failure_recovers_original_state
run_test 'commit failure recovers prior confirmed evidence and binary' test_commit_failure_recovers_confirmed_evidence
run_test 'inactive baseline recovery retains its original evidence and stopped service' test_inactive_baseline_recovers_without_certifying_a_stopped_service
run_test 'external applied edits are retained for recovery' test_external_applied_edit_is_retained
run_test 'external config edits are retained without confirming them' test_external_config_edit_is_not_confirmed
run_test 'post-publication metadata edits are retained for recovery' test_post_publication_metadata_edit_is_retained
run_test 'config edits at applied publication are not certified' test_config_edit_at_publication_is_not_certified
run_test 'config edits during baseline capture stop before restart' test_config_edit_during_capture_is_rejected_before_restart
run_test 'metadata enrollment precedes post-write receipt failure' test_metadata_is_enrolled_before_post_write_receipts
finish_tests
