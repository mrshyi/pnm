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
source <(declare -f pnm_tx_write_file | sed '1s/pnm_tx_write_file/pnm_test_real_write_file/')
source <(declare -f pnm_tx_begin | sed '1s/pnm_tx_begin/pnm_test_real_tx_begin/')
source <(declare -f pnm_tx_close | sed '1s/pnm_tx_close/pnm_test_real_tx_close/')

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
pnm_make_temp_dir() { local created_stage; created_stage="$(mktemp -d "$fixture_root/stage.XXXXXXXX")" || return $?; printf -v "$1" '%s' "$created_stage"; }
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
source <(declare -f pnm_systemctl | sed '1s/pnm_systemctl/pnm_test_real_systemctl/')
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

capture_binary_slots() {
    local path
    declare -gA fixture_slot_hashes=() fixture_slot_attributes=()
    for path in "$PNM_XRAY_BIN" "$PNM_HY2_BIN" "$PNM_STATE_DIR"/cores/{xray,hysteria2}/{previous,previous.env}; do
        fixture_slot_hashes[$path]="$(pnm_tx_file_sha256 "$path")"
        fixture_slot_attributes[$path]="$(stat -c '%a:%u:%g' "$path")"
    done
}

assert_binary_slots_restored() {
    local path
    for path in "${!fixture_slot_hashes[@]}"; do
        assert_eq "${fixture_slot_hashes[$path]}" "$(pnm_tx_file_sha256 "$path")" || return 1
        assert_eq "${fixture_slot_attributes[$path]}" "$(stat -c '%a:%u:%g' "$path")" || return 1
    done
    assert_eq confirmed "$(pnm_core_applied_config_status "$PNM_CORE_ID" "$PNM_CORE_CONFIG")" || return 1
    assert_peer_untouched "$PNM_CORE_ID" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
}

test_update_slot_publication_failures_restore_pairs() {
    local core operation label point rc faulted=0
    pnm_tx_write_file() {
        if [[ "$3" == "$label" && "$point" == before && "$faulted" == 0 ]]; then faulted=1; return 73; fi
        pnm_test_real_write_file "$@" || return $?
        if [[ "$3" == "$label" && "$point" == after && "$faulted" == 0 ]]; then faulted=1; return 73; fi
    }
    for core in xray hysteria2; do
        for operation in update rollback; do
            for label in core_binary previous_binary previous_metadata; do
                for point in before after; do
                    prepare_evidence_fixture
                    if ((EUID == 0)); then
                        chown +65534:+65534 "$PNM_STATE_DIR/cores/$core/previous" "$PNM_STATE_DIR/cores/$core/previous.env" || return 1
                    fi
                    capture_binary_slots
                    faulted=0
                    if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
                    assert_eq 1 "$faulted" || return 1
                    assert_eq 73 "$rc" || return 1
                    assert_binary_slots_restored || return 1
                done
            done
        done
    done
}

test_update_slot_metadata_edits_are_retained() {
    local core operation slot rc drift_path
    pnm_tx_commit() { chmod 0640 "$drift_path"; return 73; }
    for core in xray hysteria2; do
        for operation in update rollback; do
            for slot in binary previous previous.env; do
                prepare_evidence_fixture
                if [[ "$slot" == binary ]]; then
                    pnm_core_resolve "$core"
                    drift_path="$PNM_CORE_BINARY"
                else
                    drift_path="$PNM_STATE_DIR/cores/$core/$slot"
                fi
                if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
                assert_eq 73 "$rc" || return 1
                assert_eq 640 "$(stat -c '%a' "$drift_path")" || return 1
                assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
                assert_peer_untouched "$core" || return 1
                assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
            done
        done
    done
}

test_update_candidate_version_mismatch_is_nonmutating() {
    local core rc
    pnm_asset_download_verified() { make_version_binary "$4" 9.9.9; }
    for core in xray hysteria2; do
        prepare_evidence_fixture
        capture_binary_slots
        if pnm_core_update "$core"; then rc=0; else rc=$?; fi
        assert_eq 78 "$rc" || return 1
        assert_binary_slots_restored || return 1
        assert_eq 0 "${fixture_restarts[$PNM_CORE_UNIT]}" || return 1
    done
}

test_update_restart_and_recovery_failures_are_reported() {
    local core operation failure rc fixture_restart_attempts=0 fixture_failed_attempt=0
    pnm_systemctl() {
        ((fixture_restart_attempts += 1))
        ((fixture_restart_attempts != fixture_failed_attempt)) || return 69
        pnm_test_real_systemctl "$@"
    }
    for core in xray hysteria2; do
        for operation in update rollback; do
            for failure in restart recovery; do
                prepare_evidence_fixture
                capture_binary_slots
                fixture_restart_attempts=0
                fixture_failed_attempt=1
                if [[ "$failure" == recovery ]]; then fixture_failed_attempt=2; fixture_health_failures=1; fi
                run_capture "pnm_core_$operation" "$core"
                rc="$RUN_RC"
                if [[ "$failure" == restart ]]; then
                    assert_eq 69 "$rc" || return 1
                    assert_binary_slots_restored || return 1
                    assert_contains "$RUN_ERROR" 'previous Core state was restored' || return 1
                else
                    assert_eq 78 "$rc" || return 1
                    assert_eq 1 "$PNM_TX_RECOVERY_REQUIRED" || return 1
                    assert_contains "$RUN_ERROR" 'rollback failed' || return 1
                    assert_contains "$RUN_ERROR" 'recovery files were retained' || return 1
                    assert_eq changed "$(pnm_core_applied_config_status "$core" "$PNM_CORE_CONFIG")" || return 1
                    local -a snapshots=("$PNM_STATE_DIR"/transactions/*/snapshots/core_binary)
                    [[ -f "${snapshots[0]}" ]] || return 1
                    assert_peer_untouched "$core" || return 1
                    assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
                fi
            done
        done
    done
}

prepare_competing_writer() {
    mkdir -p "$(dirname -- "$PNM_LOCK_FILE")" || return 1
    : >"$PNM_LOCK_FILE"
    cat >"$fixture_root/competing-writer.sh" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
current=$1 previous=$2 metadata=$3 core=$4 marker=$5
printf '#!/usr/bin/env bash\nprintf "Version: 1.2.5\\n"\n' >"$current"
printf '#!/usr/bin/env bash\nprintf "Version: 1.2.4\\n"\n' >"$previous"
chmod 0755 "$current" "$previous"
printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=1.2.4\n' "$core" >"$metadata"
touch "$marker"
BASH
}

test_mutable_baselines_are_read_under_the_write_lock() {
    local core operation rc fixture_competitor_rc
    pnm_tx_begin() {
        if flock -n "$PNM_LOCK_FILE" bash "$fixture_root/competing-writer.sh" \
            "$PNM_CORE_BINARY" "$PNM_STATE_DIR/cores/$PNM_CORE_ID/previous" \
            "$PNM_STATE_DIR/cores/$PNM_CORE_ID/previous.env" "$PNM_CORE_ID" "$fixture_root/competed"; then
            fixture_competitor_rc=0
        else
            fixture_competitor_rc=$?
        fi
        pnm_test_real_tx_begin "$@"
    }
    for core in xray hysteria2; do
        for operation in rollback update; do
            prepare_evidence_fixture
            prepare_competing_writer || return 1
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 0 "$rc" || return 1
            if [[ "$operation" == rollback ]]; then
                assert_eq 1.2.2 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
            else
                assert_eq 1.2.4 "$(pnm_binary_version_number "$PNM_CORE_BINARY" xray)" || return 1
            fi
            assert_eq 1 "$fixture_competitor_rc" || return 1
            [[ ! -e "$fixture_root/competed" ]] || return 1
            assert_eq 1.2.3 "$(pnm_binary_version_number "$PNM_STATE_DIR/cores/$core/previous" xray)" || return 1
            assert_contains "$(<"$PNM_STATE_DIR/cores/$core/previous.env")" 'VERSION=1.2.3' || return 1
            assert_peer_untouched "$core" || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
            flock -n "$PNM_LOCK_FILE" true || return 1
        done
    done
}

test_contending_writer_refuses_before_preparation() {
    local core operation fixture_owner_fd rc
    pnm_make_temp_dir() { touch "$fixture_root/prepared"; local created_stage; created_stage="$(mktemp -d "$fixture_root/stage.XXXXXXXX")" || return $?; printf -v "$1" '%s' "$created_stage"; }
    for core in xray hysteria2; do
        for operation in update rollback; do
            prepare_evidence_fixture
            prepare_competing_writer || return 1
            capture_binary_slots
            exec {fixture_owner_fd}>"$PNM_LOCK_FILE"
            flock -x "$fixture_owner_fd" || return 1
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 73 "$rc" || return 1
            [[ ! -e "$fixture_root/prepared" ]] || return 1
            assert_binary_slots_restored || return 1
            # A failed operation must not unlock another owner's descriptor.
            if flock -n "$PNM_LOCK_FILE" true; then return 1; fi
            exec {fixture_owner_fd}>&-
            flock -n "$PNM_LOCK_FILE" true || return 1
        done
    done
}

test_pending_deployment_refuses_before_preparation() {
    local core operation rc
    pnm_tx_assert_no_pending_deployment() { return 70; }
    pnm_make_temp_dir() { touch "$fixture_root/prepared"; local created_stage; created_stage="$(mktemp -d "$fixture_root/stage.XXXXXXXX")" || return $?; printf -v "$1" '%s' "$created_stage"; }
    for core in xray hysteria2; do
        for operation in update rollback; do
            prepare_evidence_fixture
            capture_binary_slots
            if "pnm_core_$operation" "$core"; then rc=0; else rc=$?; fi
            assert_eq 70 "$rc" || return 1
            [[ ! -e "$fixture_root/prepared" ]] || return 1
            assert_binary_slots_restored || return 1
            flock -n "$PNM_LOCK_FILE" true || return 1
        done
    done
}

test_core_operations_preserve_a_callers_reentrant_lock() {
    local core operation
    for core in xray hysteria2; do
        for operation in update rollback; do
            prepare_evidence_fixture
            pnm_lock_acquire exclusive || return 1
            "pnm_core_$operation" "$core" || return 1
            assert_eq 1 "$PNM_LOCK_DEPTH" || return 1
            if flock -n "$PNM_LOCK_FILE" true; then return 1; fi
            pnm_lock_release || return 1
            flock -n "$PNM_LOCK_FILE" true || return 1
            assert_peer_untouched "$core" || return 1
        done
    done
}

test_transaction_close_failure_is_reported_and_releases_outer_lock() {
    local core operation
    pnm_tx_close() { pnm_test_real_tx_close "$@" || return $?; return 70; }
    for core in xray hysteria2; do
        for operation in update rollback; do
            prepare_evidence_fixture
            run_capture "pnm_core_$operation" "$core"
            assert_eq 70 "$RUN_RC" || return 1
            assert_not_contains "$RUN_OUTPUT" 'updated to' || return 1
            assert_not_contains "$RUN_OUTPUT" 'rolled back to' || return 1
            assert_eq 0 "$PNM_LOCK_DEPTH" || return 1
            flock -n "$PNM_LOCK_FILE" true || return 1
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
run_test 'update and rollback publication failures restore all binary metadata pairs' test_update_slot_publication_failures_restore_pairs
run_test 'update and rollback retain binary slot metadata edits' test_update_slot_metadata_edits_are_retained
run_test 'unapproved candidate version does not mutate either Core' test_update_candidate_version_mismatch_is_nonmutating
run_test 'update restart errors recover or explicitly retain recovery failures' test_update_restart_and_recovery_failures_are_reported
run_test 'mutable update and rollback baselines are read under the write lock' test_mutable_baselines_are_read_under_the_write_lock
run_test 'another writer refuses operations before preparation' test_contending_writer_refuses_before_preparation
run_test 'pending deployment refuses operations before preparation' test_pending_deployment_refuses_before_preparation
run_test 'Core operations preserve the callers reentrant lock' test_core_operations_preserve_a_callers_reentrant_lock
run_test 'transaction close failures propagate and release the outer write lock' test_transaction_close_failure_is_reported_and_releases_outer_lock
finish_tests
