#!/usr/bin/env bash

PNM_CORE_ID=''
PNM_CORE_UNIT=''
PNM_CORE_BINARY=''
PNM_CORE_CONFIG=''
PNM_CORE_BACKUP_PATH=''
PNM_CORE_RESTORE_XRAY_ACTIVE=''
PNM_CORE_RESTORE_XRAY_ENABLED=''
PNM_CORE_RESTORE_HY2_ACTIVE=''
PNM_CORE_RESTORE_HY2_ENABLED=''
PNM_CORE_RESTORE_XRAY_LOAD=''
PNM_CORE_RESTORE_HY2_LOAD=''
PNM_CORE_RESTORE_STARTED=0
declare -Ag PNM_CORE_RESTORE_CONFIG_HASH=() PNM_CORE_RESTORE_APPLIED_HASH=() PNM_CORE_RESTORE_APPLIED_ATTRIBUTES=()
PNM_CORE_UPDATE_FAILURE_STAGE=''

pnm_core_resolve() {
    case "$1" in
        xray)
            PNM_CORE_ID=xray PNM_CORE_UNIT=xray.service
            PNM_CORE_BINARY=$PNM_XRAY_BIN PNM_CORE_CONFIG=$PNM_XRAY_CONFIG
            ;;
        hy2 | hysteria2)
            PNM_CORE_ID=hysteria2 PNM_CORE_UNIT=hysteria-server.service
            PNM_CORE_BINARY=$PNM_HY2_BIN PNM_CORE_CONFIG=$PNM_HY2_CONFIG
            ;;
        *) return "$PNM_EXIT_USAGE" ;;
    esac
}

pnm_core_restart() {
    pnm_core_resolve "$1" || return $?
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_restart_locked "$PNM_CORE_ID"
}

pnm_core_restart_locked() {
    local core rc
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    pnm_core_resolve "$1" || return $?
    core=$PNM_CORE_ID
    pnm_core_lifecycle_snapshot "$core" || return $?
    pnm_tx_begin "core-lifecycle-$core" || return $?
    pnm_core_capture_applied || { rc=$?; pnm_tx_close; return "$rc"; }
    if ((PNM_DRY_RUN == 0)); then
        pnm_tx_record_core_state "$core" "$PNM_CORE_UNIT" "$PNM_LIFECYCLE_PRE_ACTIVE" "$PNM_LIFECYCLE_PRE_ENABLED" || {
            rc=$?; pnm_tx_close; return "$rc";
        }
    fi
    pnm_tx_add_rollback pnm_core_restart_restore || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run restart pnm_core_restart_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run health pnm_core_lifecycle_health_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run applied_evidence pnm_core_refresh_applied; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close || return $?
    pnm_success "$core restarted and healthy."
}

pnm_core_restart_step() {
    pnm_systemctl restart "$PNM_CORE_UNIT"
}

pnm_core_restart_restore() {
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    pnm_core_lifecycle_restore || return "$PNM_EXIT_SOFTWARE"
    pnm_core_recover_applied || return $?
    pnm_tx_restore_directories
}

# Only carry forward evidence confirmed before this operation. A lifecycle
# command must not silently certify missing, stale or externally edited state.
pnm_core_capture_applied() {
    local record="$PNM_STATE_DIR/cores/$PNM_CORE_ID/applied.env" attributes
    local -A prior=()
    [[ "$(pnm_core_applied_config_status "$PNM_CORE_ID" "$PNM_CORE_CONFIG")" == confirmed ]] || return 0
    pnm_validate_managed_path "$record" && pnm_validate_managed_path "$PNM_CORE_CONFIG" || return "$PNM_EXIT_CONFIG"
    attributes="$(stat -c '%a:%u:%g' -- "$record")" || return "$PNM_EXIT_CONFIG"
    [[ "$attributes" == "600:$EUID:"* ]] || return "$PNM_EXIT_CONFIG"
    PNM_CORE_PRIOR_APPLIED_HASH="$(pnm_tx_file_sha256 "$record")" || return "$PNM_EXIT_SOFTWARE"
    pnm_config_load "$record" prior SCHEMA_VERSION CORE CONFIG_SHA256 SERVICE_INVOCATION_ID || return "$PNM_EXIT_SOFTWARE"
    PNM_CORE_PRIOR_CONFIG_HASH="$(pnm_tx_file_sha256 "$PNM_CORE_CONFIG")" || return "$PNM_EXIT_SOFTWARE"
    PNM_CORE_PRIOR_APPLIED_ATTRIBUTES="$attributes"
    [[ "${prior[SCHEMA_VERSION]-}" == 1 && "${prior[CORE]-}" == "$PNM_CORE_ID" &&
        "${prior[CONFIG_SHA256]-}" == "$PNM_CORE_PRIOR_CONFIG_HASH" &&
        "${prior[SERVICE_INVOCATION_ID]-}" == "$(pnm_systemd_show_value "$PNM_CORE_UNIT" InvocationID)" &&
        "$(pnm_tx_file_sha256 "$record")" == "$PNM_CORE_PRIOR_APPLIED_HASH" ]] || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_check_applied_baseline() {
    local record="$PNM_STATE_DIR/cores/$PNM_CORE_ID/applied.env"
    pnm_validate_managed_path "$record" && pnm_validate_managed_path "$PNM_CORE_CONFIG" || return "$PNM_EXIT_SOFTWARE"
    [[ "$(pnm_tx_file_sha256 "$PNM_CORE_CONFIG")" == "$PNM_CORE_PRIOR_CONFIG_HASH" &&
        "$(pnm_tx_file_sha256 "$record")" == "$PNM_CORE_PRIOR_APPLIED_HASH" &&
        "$(stat -c '%a:%u:%g' -- "$record")" == "$PNM_CORE_PRIOR_APPLIED_ATTRIBUTES" ]] || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_refresh_applied() {
    [[ -n "${PNM_CORE_PRIOR_CONFIG_HASH:-}" ]] || return 0
    pnm_core_check_applied_baseline || return $?
    pnm_core_record_applied_config "$PNM_CORE_ID" "$PNM_CORE_CONFIG" "$PNM_TX_PATH" "$PNM_CORE_PRIOR_CONFIG_HASH" || return $?
    [[ "$(pnm_core_applied_config_status "$PNM_CORE_ID" "$PNM_CORE_CONFIG")" == confirmed ]] || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_recover_applied() {
    local invocation
    [[ -n "${PNM_CORE_PRIOR_CONFIG_HASH:-}" ]] || return 0
    # An inactive baseline is restored by stopping, not by claiming a healthy
    # running invocation. Keep its original evidence bytes unchanged.
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return 0
    # Recovery must preserve an active-but-disabled baseline. The install
    # health policy additionally requires enabled and is inappropriate here.
    [[ "$(pnm_systemd_active_state "$PNM_CORE_UNIT")" == active ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_core_check_applied_baseline || return $?
    invocation="$(pnm_systemd_show_value "$PNM_CORE_UNIT" InvocationID)" || return "$PNM_EXIT_SOFTWARE"
    [[ "$invocation" =~ ^[a-fA-F0-9]{32}$ ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_tx_refresh_recovered_applied "$PNM_STATE_DIR/cores/$PNM_CORE_ID/applied.env" "$PNM_CORE_ID" \
        "$PNM_CORE_PRIOR_CONFIG_HASH" "${invocation,,}" "$PNM_CORE_PRIOR_APPLIED_HASH" \
        "$PNM_CORE_PRIOR_APPLIED_ATTRIBUTES" || return "$PNM_EXIT_SOFTWARE"
    [[ "$(pnm_core_applied_config_status "$PNM_CORE_ID" "$PNM_CORE_CONFIG")" == confirmed ]] || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_log() {
    local lines=100 follow=0 arg
    pnm_core_resolve "$1" || return $?
    shift
    while (($#)); do
        arg=$1; shift
        case "$arg" in
            --follow) follow=1 ;;
            --lines)
                (($#)) || return "$PNM_EXIT_USAGE"
                lines=$1; shift
                [[ "$lines" =~ ^[1-9][0-9]{0,4}$ ]] || return "$PNM_EXIT_USAGE"
                ;;
            *) return "$PNM_EXIT_USAGE" ;;
        esac
    done
    pnm_command_exists journalctl || return "$PNM_EXIT_UNAVAILABLE"
    if ((follow)); then
        journalctl -u "$PNM_CORE_UNIT" -n "$lines" -f --no-pager
    else
        journalctl -u "$PNM_CORE_UNIT" -n "$lines" --no-pager
    fi
}

pnm_core_restore_config() {
    local rc=0 active enabled
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    if [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]]; then
        pnm_systemctl restart "$PNM_CORE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
        # Compensation verifies the original policy; a disabled baseline is valid.
        active="$(pnm_systemd_active_state "$PNM_CORE_UNIT")" &&
            enabled="$(pnm_systemd_enabled_state "$PNM_CORE_UNIT")" &&
            [[ "$active" == active && "$enabled" == "$PNM_LIFECYCLE_PRE_ENABLED" ]] || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl stop "$PNM_CORE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
    fi
    ((rc == 0)) || return "$rc"
    pnm_core_recover_applied || return $?
    pnm_tx_restore_directories
}

pnm_core_apply_rollback() {
    if pnm_tx_rollback; then
        return 0
    fi
    pnm_error 'Configuration rollback failed; inspect PNM transaction recovery state before retrying.'
    return "$PNM_EXIT_SOFTWARE"
}

pnm_core_record_applied_config() {
    local core="${1:?Core id required}"
    local config="${2:?configuration path required}"
    local stage_dir="${3:?stage directory required}"
    local expected_digest="${4-}"
    local record_dir="$PNM_STATE_DIR/cores/$core"
    local record="$record_dir/applied.env"
    local staged="$stage_dir/applied-$core.env"
    local digest rc unit invocation metadata_policy="${expected_digest:+required}"

    [[ "$core" == xray || "$core" == hysteria2 ]] || return "$PNM_EXIT_CONFIG"
    digest="$(sha256sum -- "$config" 2>/dev/null | awk '{print $1}')" || return "$PNM_EXIT_SOFTWARE"
    [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return "$PNM_EXIT_SOFTWARE"
    # Lifecycle operations may only carry forward the pre-restart digest.
    [[ -z "$expected_digest" || "$digest" == "$expected_digest" ]] || return "$PNM_EXIT_SOFTWARE"
    case "$core" in
        xray) unit=xray.service ;;
        hysteria2) unit=hysteria-server.service ;;
    esac
    invocation="$(pnm_systemd_show_value "$unit" InvocationID 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$invocation" =~ ^[a-fA-F0-9]{32}$ ]] || return "$PNM_EXIT_UNAVAILABLE"
    pnm_tx_prepare_directory "$PNM_STATE_DIR/cores" 0700 || return $?
    pnm_tx_prepare_directory "$record_dir" 0700 || return $?
    printf 'SCHEMA_VERSION=1\nCORE=%s\nCONFIG_SHA256=%s\nSERVICE_INVOCATION_ID=%s\n' \
        "$core" "$digest" "${invocation,,}" >"$staged" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$staged" || { rm -f -- "$staged"; return "$PNM_EXIT_NOPERM"; }
    case "${PNM_TX_OPERATION:-}" in
        core-restore | core-config-xray | core-config-hysteria2) metadata_policy=required ;;
    esac
    if pnm_tx_write_file "$staged" "$record" "applied_$core" 0600 "$metadata_policy"; then
        :
    else
        rc=$?
        rm -f -- "$staged"
        return "$rc"
    fi
    rm -f -- "$staged"
}

pnm_core_apply_config() {
    pnm_core_resolve "$1" || return $?
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_apply_config_locked "$PNM_CORE_ID"
}

pnm_core_apply_config_locked() {
    local core=$1 rc stage config validation_output tls_check tls_status tls_detail mode owner
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    local node_name=PNM_CORE_NODE secret_name=PNM_CORE_SECRET
    local -A PNM_CORE_NODE=() PNM_CORE_SECRET=()
    pnm_core_resolve "$core" || return $?
    core=$PNM_CORE_ID
    [[ -d "$(dirname -- "$PNM_CORE_CONFIG")" && ! -L "$(dirname -- "$PNM_CORE_CONFIG")" ]] || return "$PNM_EXIT_CONFIG"
    pnm_load_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    [[ "${PNM_CORE_NODE[PNM_CONFIGURED]}" == yes ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$core" == xray ]]; then
        pnm_load_reality_secret "$secret_name" && pnm_validate_reality_secret_config "$secret_name" || return "$PNM_EXIT_CONFIG"
        if pnm_node_xray_reality_public_key "${PNM_CORE_SECRET[XRAY_REALITY_PRIVATE_KEY]}" >/dev/null; then
            :
        else
            rc=$?
            pnm_error 'REALITY private key is invalid or Xray could not derive its public key.'
            return "$rc"
        fi
    else
        pnm_load_hysteria_secret "$secret_name" && pnm_validate_hysteria_secret_config "$secret_name" || return "$PNM_EXIT_CONFIG"
    fi
    pnm_make_temp_dir stage || return $?
    config="$stage/config"
    if [[ "$core" == xray ]]; then
        pnm_render_xray_config "$node_name" "$secret_name" >"$config" || return $?
        if ! pnm_capture validation_output "$PNM_XRAY_BIN" run -test -config "$config"; then
            pnm_error 'Generated Xray configuration failed `xray run -test`; the current runtime config was not changed.'
            return "$PNM_EXIT_CONFIG"
        fi
    else
        pnm_render_hysteria_config "$node_name" "$secret_name" >"$config" || return $?
        if ! pnm_hysteria_config_validate_candidate "$config" "$node_name" "$secret_name"; then
            pnm_error 'Generated Hysteria2 configuration failed PNM candidate validation; the current runtime config was not changed.'
            return "$PNM_EXIT_CONFIG"
        fi
        if ! pnm_tls_validate_pair "${PNM_CORE_SECRET[HY2_TLS_CERT_PATH]}" "${PNM_CORE_SECRET[HY2_TLS_KEY_PATH]}"; then
            pnm_error 'Hysteria2 TLS certificate and private key could not be validated; the current runtime config was not changed.'
            return "$PNM_EXIT_CONFIG"
        fi
        if ! pnm_hysteria_tls_server_name "$node_name" "$secret_name" >/dev/null; then
            pnm_error 'Hysteria2 TLS SNI is missing or does not match the configured certificate SAN; the current runtime config was not changed.'
            return "$PNM_EXIT_CONFIG"
        fi
        tls_check="$(pnm_tls_certificate_check "${PNM_CORE_NODE[HY2_TLS_MODE]}" "${PNM_CORE_SECRET[HY2_TLS_CERT_PATH]}")"
        IFS='|' read -r tls_status tls_detail <<<"$tls_check"
        if [[ "$tls_status" != OK ]]; then
            pnm_error "Hysteria2 TLS certificate check returned $tls_status ($tls_detail); the current runtime config was not changed."
            return "$PNM_EXIT_CONFIG"
        fi
    fi
    chmod 0600 -- "$config" || return "$PNM_EXIT_NOPERM"
    pnm_core_lifecycle_snapshot "$core" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    pnm_tx_begin "core-config-$core" || return $?
    pnm_core_capture_applied || { rc=$?; pnm_tx_close; return "$rc"; }
    pnm_tx_add_rollback pnm_core_restore_config || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if [[ "$core" == xray ]]; then mode=0640 owner=root:xray; else mode=0600 owner=hysteria:hysteria; fi
    pnm_core_restore_write_file "$config" "$PNM_CORE_CONFIG" core_config "$mode" "$owner" || {
        rc=$?; pnm_core_apply_rollback || true; pnm_tx_close; return "$rc";
    }
    if pnm_systemctl restart "$PNM_CORE_UNIT"; then
        :
    else
        rc=$?
        pnm_error "$core service restart failed; restoring the previous runtime configuration."
        pnm_core_apply_rollback || true
        pnm_tx_close
        return "$rc"
    fi
    if pnm_systemd_unit_healthy "$PNM_CORE_UNIT"; then
        :
    else
        rc=$?
        pnm_error "$core service did not become healthy after restart; restoring the previous runtime configuration."
        pnm_core_apply_rollback || true
        pnm_tx_close
        return "$rc"
    fi
    if [[ "$core" == xray ]]; then
        if ! cmp -s -- "$config" "$PNM_CORE_CONFIG" ||
            ! pnm_capture validation_output "$PNM_XRAY_BIN" run -test -config "$PNM_CORE_CONFIG"; then
            pnm_error 'Xray restarted, but the active configuration does not match the validated candidate; restoring the previous configuration.'
            pnm_core_apply_rollback || true
            pnm_tx_close
            return "$PNM_EXIT_CONFIG"
        fi
    fi
    if [[ "$core" == hysteria2 ]] && ! pnm_hysteria_config_matches_node "$node_name" "$secret_name"; then
        pnm_error 'Hysteria2 restarted, but the runtime configuration differs from the validated candidate; restoring the previous configuration.'
        pnm_core_apply_rollback || true
        pnm_tx_close
        return "$PNM_EXIT_CONFIG"
    fi
    if pnm_core_record_applied_config "$core" "$PNM_CORE_CONFIG" "$stage"; then
        :
    else
        rc=$?
        pnm_error "$core applied-configuration evidence could not be committed; restoring the previous configuration."
        pnm_core_apply_rollback || true
        pnm_tx_close
        return "$rc"
    fi
    pnm_tx_commit || { rc=$?; pnm_core_apply_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close || return $?
    pnm_success "$core configuration applied."
}

pnm_core_backup_source() {
    printf '/%s\n' "$1"
}

pnm_core_backup() {
    PNM_CORE_BACKUP_PATH=''
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_backup_locked "$1"
}

pnm_core_backup_locked() {
    local destination=$1 directory staging file manifest source publication
    local xray_version hy2_version
    local -A backup_node=()
    local -a files=(etc/pnm/node.conf etc/pnm/versions.conf etc/pnm/secrets/reality.env etc/pnm/secrets/hysteria.env
        usr/local/etc/xray/config.json etc/hysteria/config.yaml etc/hysteria/tls/server.crt etc/hysteria/tls/server.key
        usr/local/bin/xray usr/local/bin/hysteria etc/systemd/system/xray.service etc/systemd/system/hysteria-server.service)
    if [[ -n "$destination" ]]; then
        case "$destination" in
            /*) pnm_validate_managed_path "$destination" || return $? ;;
            *) pnm_validate_managed_path "$PWD/$destination" || return $? ;;
        esac
    fi
    if [[ -z "$destination" ]]; then
        directory=/var/backups/pnm
        pnm_mkdir_mode 0700 "$directory" || return "$PNM_EXIT_CANTCREAT"
        destination="$directory/pnm-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
    else
        directory="$(dirname -- "$destination")"
        [[ -d "$directory" && ! -L "$directory" ]] || return "$PNM_EXIT_CONFIG"
    fi
    [[ ! -e "$destination" && ! -L "$destination" ]] || return "$PNM_EXIT_CANTCREAT"
    for file in "${files[@]}"; do
        source="$(pnm_core_backup_source "$file")" || return $?
        if ! pnm_validate_managed_path "$source" || [[ ! -f "$source" || -L "$source" ]]; then
            pnm_error "Cannot create a complete Core backup; required file is missing or unsafe: /$file"
            return "$PNM_EXIT_CONFIG"
        fi
    done
    pnm_make_temp_dir staging || return $?
    for file in "${files[@]}"; do
        source="$(pnm_core_backup_source "$file")" || return $?
        pnm_validate_managed_path "$source" || return $?
        [[ -f "$source" && ! -L "$source" ]] || return "$PNM_EXIT_CONFIG"
        mkdir -p -- "$staging/$(dirname -- "$file")" || return "$PNM_EXIT_CANTCREAT"
        install -m 0600 -- "$source" "$staging/$file" || return "$PNM_EXIT_CANTCREAT"
    done
    # Read metadata from the bytes being archived, not mutable live paths.
    local PNM_CONFIG_DIR="$staging/etc/pnm"
    pnm_load_node_config backup_node && pnm_validate_node_config backup_node || return "$PNM_EXIT_CONFIG"
    chmod 0700 -- "$staging/usr/local/bin/xray" "$staging/usr/local/bin/hysteria" || return "$PNM_EXIT_NOPERM"
    xray_version="$(pnm_binary_version "$staging/usr/local/bin/xray" xray 2>/dev/null || printf unknown)"
    hy2_version="$(pnm_binary_version "$staging/usr/local/bin/hysteria" hysteria 2>/dev/null || printf unknown)"
    chmod 0600 -- "$staging/usr/local/bin/xray" "$staging/usr/local/bin/hysteria" || return "$PNM_EXIT_NOPERM"
    manifest="$staging/MANIFEST.txt"
    {
        printf 'CONTAINS SECRETS\nPNM_VERSION=%s\nHOSTNAME=%s\nKERNEL=%s\n' "$(pnm_read_version)" "$(hostname)" "$(uname -r)"
        printf 'XRAY_VERSION=%s\nHY2_VERSION=%s\nTCP_PORT=%s\nUDP_PORT=%s\n' \
            "$xray_version" "$hy2_version" "${backup_node[XRAY_PORT]}" "${backup_node[HY2_PORT]}"
        printf 'XRAY_ACTIVE=%s\nXRAY_ENABLED=%s\nHY2_ACTIVE=%s\nHY2_ENABLED=%s\n' \
            "$(pnm_systemd_active_state xray.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_enabled_state xray.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_active_state hysteria-server.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_enabled_state hysteria-server.service 2>/dev/null || printf unknown)"
    } >"$manifest" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$manifest" || return "$PNM_EXIT_NOPERM"
    # Build privately on the destination filesystem, then publish without
    # replacing a file created after the precheck. Protected parents are assumed.
    publication="$(mktemp -- "$directory/.pnm-backup.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$publication" || { rm -f -- "$publication"; return "$PNM_EXIT_NOPERM"; }
    tar --create --gzip --file "$publication" --directory "$staging" . || {
        rm -f -- "$publication"; return "$PNM_EXIT_CANTCREAT";
    }
    ln -T -- "$publication" "$destination" || { rm -f -- "$publication"; return "$PNM_EXIT_CANTCREAT"; }
    rm -f -- "$publication" || return "$PNM_EXIT_SOFTWARE"
    PNM_CORE_BACKUP_PATH="$destination"
    printf '%s\n' "$destination"
}

pnm_core_update() {
    local requested='' arg core
    pnm_core_resolve "$1" || return $?
    core="$PNM_CORE_ID"
    shift
    while (($#)); do
        arg=$1; shift
        case "$arg" in
            --version) (($#)) || return "$PNM_EXIT_USAGE"; requested=$1; shift ;;
            *) return "$PNM_EXIT_USAGE" ;;
        esac
    done
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_update_locked "$core" "$requested"
}

pnm_core_update_locked() {
    local requested="$2" version hash asset staged rc previous_dir previous_file previous_meta old_version style metadata_stage snapshot_stage
    local staged_version staged_validation
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    local -A PNM_UPDATE_NODE=() PNM_UPDATE_SECRET=()
    pnm_core_resolve "$1" || return $?
    pnm_assets_load || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_CORE_ID" == xray ]]; then
        version=${PNM_ASSET_VERSIONS[XRAY_VERSION]} hash=${PNM_ASSET_VERSIONS[XRAY_SHA256]}
        style=xray
    else
        version=${PNM_ASSET_VERSIONS[HY2_VERSION]} hash=${PNM_ASSET_VERSIONS[HY2_SHA256]}
        style=hysteria
    fi
    [[ -z "$requested" || "$requested" == "$version" ]] || {
        pnm_error "Requested version is not approved in $PNM_CONFIG_DIR/versions.conf."
        return "$PNM_EXIT_CONFIG"
    }
    [[ -x "$PNM_CORE_BINARY" && -f "$PNM_CORE_CONFIG" ]] || return "$PNM_EXIT_CONFIG"
    pnm_core_lifecycle_snapshot "$PNM_CORE_ID" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    old_version="$(pnm_binary_version_number "$PNM_CORE_BINARY" "$style")" || return "$PNM_EXIT_CONFIG"
    [[ -n "$old_version" ]] || return "$PNM_EXIT_CONFIG"
    pnm_make_temp_dir PNM_CORE_STAGE || return $?
    asset="$PNM_CORE_STAGE/asset"
    pnm_asset_download_verified "$PNM_CORE_ID" "$version" "$hash" "$asset" || return $?
    if [[ "$PNM_CORE_ID" == xray ]]; then
        staged="$(pnm_asset_stage_xray_zip "$asset" "$PNM_CORE_STAGE/extract")" || return $?
    else
        staged="$(pnm_asset_stage_hysteria_binary "$asset" "$PNM_CORE_STAGE")" || return $?
    fi
    staged_version="$(pnm_binary_version_number "$staged" "$style" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    [[ "$staged_version" == "${version#v}" ]] || return "$PNM_EXIT_CONFIG"
    pnm_load_node_config PNM_UPDATE_NODE && pnm_validate_node_config PNM_UPDATE_NODE || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_CORE_ID" == xray ]]; then
        pnm_load_reality_secret PNM_UPDATE_SECRET && pnm_validate_reality_secret_config PNM_UPDATE_SECRET || return "$PNM_EXIT_CONFIG"
        pnm_capture staged_validation "$staged" run -test -config "$PNM_CORE_CONFIG" || return "$PNM_EXIT_CONFIG"
    else
        pnm_load_hysteria_secret PNM_UPDATE_SECRET && pnm_validate_hysteria_secret_config PNM_UPDATE_SECRET || return "$PNM_EXIT_CONFIG"
        pnm_hysteria_config_validate_candidate "$PNM_CORE_CONFIG" PNM_UPDATE_NODE PNM_UPDATE_SECRET || return "$PNM_EXIT_CONFIG"
        pnm_tls_validate_pair "${PNM_UPDATE_SECRET[HY2_TLS_CERT_PATH]}" "${PNM_UPDATE_SECRET[HY2_TLS_KEY_PATH]}" || return "$PNM_EXIT_CONFIG"
    fi
    previous_dir="$PNM_STATE_DIR/cores/$PNM_CORE_ID"
    previous_file="$previous_dir/previous"
    previous_meta="$previous_dir/previous.env"
    metadata_stage="$PNM_CORE_STAGE/previous.env"
    snapshot_stage="$PNM_CORE_STAGE/previous"
    pnm_tx_begin "core-update-$PNM_CORE_ID" || return $?
    pnm_core_capture_applied || { rc=$?; pnm_tx_close; return "$rc"; }
    pnm_tx_add_rollback pnm_core_update_rollback || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_prepare_directory "$PNM_STATE_DIR/cores" 0700 &&
        pnm_tx_prepare_directory "$previous_dir" 0700 || {
        rc=$?; pnm_core_update_abort update 'previous state directory preparation' "$rc"; return "$rc";
    }
    pnm_tx_write_file "$staged" "$PNM_CORE_BINARY" core_binary 0755 required || {
        rc=$?; pnm_core_update_abort update 'binary publication' "$rc"; return "$rc";
    }
    if [[ "$(pnm_binary_version_number "$PNM_CORE_BINARY" "$style")" != "${version#v}" ]]; then
        pnm_core_update_abort update 'published binary version verification' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG"
    fi
    pnm_systemctl restart "$PNM_CORE_UNIT" || { rc=$?; pnm_core_update_abort update 'service restart' "$rc"; return "$rc"; }
    if declare -F pnm_check_deploy_core_health >/dev/null 2>&1; then
        pnm_check_deploy_core_health "$PNM_CORE_ID" || { pnm_core_update_abort update 'post-update health check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG"; }
    else
        pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || { pnm_core_update_abort update 'post-update health check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG"; }
    fi
    install -m 0755 -- "$PNM_TX_PATH/snapshots/core_binary" "$snapshot_stage" || {
        pnm_core_update_abort update 'previous binary staging' "$PNM_EXIT_CANTCREAT"; return "$PNM_EXIT_CANTCREAT";
    }
    [[ "$(pnm_binary_version_number "$snapshot_stage" "$style" 2>/dev/null)" == "$old_version" ]] || {
        pnm_core_update_abort update 'previous binary version verification' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG";
    }
    printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=%s\n' "$PNM_CORE_ID" "$old_version" >"$metadata_stage" || {
        pnm_core_update_abort update 'previous version metadata staging' "$PNM_EXIT_CANTCREAT"; return "$PNM_EXIT_CANTCREAT";
    }
    chmod 0600 -- "$metadata_stage" || { pnm_core_update_abort update 'previous metadata permissions' "$PNM_EXIT_NOPERM"; return "$PNM_EXIT_NOPERM"; }
    if pnm_core_publish_previous_state "$snapshot_stage" "$metadata_stage" "$previous_file" "$previous_meta"; then :; else
        rc=$?
        pnm_core_update_abort update "$PNM_CORE_UPDATE_FAILURE_STAGE" "$rc"
        return "$rc"
    fi
    [[ "$(pnm_binary_version_number "$previous_file" "$style" 2>/dev/null)" == "$old_version" ]] || {
        pnm_core_update_abort update 'previous binary and metadata consistency check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG";
    }
    pnm_core_refresh_applied || { rc=$?; pnm_core_update_abort update 'applied evidence publication' "$rc"; return "$rc"; }
    pnm_tx_verify_written_resources || { rc=$?; pnm_core_update_abort update 'published resource verification' "$rc"; return "$rc"; }
    pnm_tx_commit || { rc=$?; pnm_core_update_abort update 'transaction commit' "$rc"; return "$rc"; }
    pnm_tx_close || return $?
    pnm_success "$PNM_CORE_ID updated to $version; use 'pnm rollback $PNM_CORE_ID' to revert."
}

pnm_core_update_rollback() {
    local active enabled
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    pnm_systemctl restart "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
    active="$(pnm_systemd_active_state "$PNM_CORE_UNIT")" || return "$PNM_EXIT_SOFTWARE"
    enabled="$(pnm_systemd_enabled_state "$PNM_CORE_UNIT")" || return "$PNM_EXIT_SOFTWARE"
    [[ "$active" == active && "$enabled" == "$PNM_LIFECYCLE_PRE_ENABLED" ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_core_recover_applied || return $?
    pnm_tx_restore_directories
}

pnm_core_publish_previous_state() {
    local binary_source="${1:?previous binary source required}"
    local metadata_source="${2:?previous metadata source required}"
    local binary_target="${3:?previous binary target required}"
    local metadata_target="${4:?previous metadata target required}"

    PNM_CORE_UPDATE_FAILURE_STAGE='previous binary publication'
    pnm_tx_write_file "$binary_source" "$binary_target" previous_binary 0755 required || return $?
    PNM_CORE_UPDATE_FAILURE_STAGE='previous version metadata publication'
    pnm_tx_write_file "$metadata_source" "$metadata_target" previous_metadata 0600 required || return $?
    PNM_CORE_UPDATE_FAILURE_STAGE=''
}

pnm_core_update_abort() {
    local operation="${1:?operation required}" stage="${2:?failure stage required}" original_rc="${3:?original failure code required}" rollback_rc=0
    if pnm_tx_rollback; then
        pnm_error "Core $operation failed during $stage (rc=$original_rc); previous Core state was restored."
    else
        rollback_rc=$?
        pnm_error "Core $operation failed during $stage (rc=$original_rc) and rollback failed (rc=$rollback_rc); recovery files were retained."
    fi
    pnm_tx_close || true
    return "$original_rc"
}

pnm_core_rollback() {
    pnm_core_resolve "$1" || return $?
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_rollback_locked "$PNM_CORE_ID"
}

pnm_core_rollback_locked() {
    local core version current_version previous_dir previous_file previous_meta rc style metadata_stage
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    pnm_core_resolve "$1" || return $?
    core=$PNM_CORE_ID
    style=xray
    [[ "$core" == hysteria2 ]] && style=hysteria
    previous_dir="$PNM_STATE_DIR/cores/$core"
    previous_file="$previous_dir/previous"
    previous_meta="$previous_dir/previous.env"
    [[ -f "$previous_file" && ! -L "$previous_file" && -f "$previous_meta" && ! -L "$previous_meta" ]] || return "$PNM_EXIT_UNAVAILABLE"
    local -A previous=()
    pnm_config_load "$previous_meta" previous SCHEMA_VERSION CORE VERSION || return "$PNM_EXIT_CONFIG"
    [[ "${previous[SCHEMA_VERSION]-}" == 1 && "${previous[CORE]-}" == "$core" && "${previous[VERSION]-}" =~ ^[A-Za-z0-9._+-]+$ ]] || return "$PNM_EXIT_CONFIG"
    version=${previous[VERSION]}
    [[ "$(pnm_binary_version_number "$previous_file" "$style")" == "$version" ]] || return "$PNM_EXIT_CONFIG"
    pnm_core_lifecycle_snapshot "$core" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    pnm_make_temp_dir PNM_CORE_STAGE || return $?
    current_version="$(pnm_binary_version_number "$PNM_CORE_BINARY" "$style")" || return "$PNM_EXIT_CONFIG"
    [[ -n "$current_version" ]] || return "$PNM_EXIT_CONFIG"
    install -m 0755 -- "$PNM_CORE_BINARY" "$PNM_CORE_STAGE/current" || return "$PNM_EXIT_CANTCREAT"
    pnm_tx_begin "core-rollback-$core" || return $?
    pnm_core_capture_applied || { rc=$?; pnm_tx_close; return "$rc"; }
    pnm_tx_add_rollback pnm_core_update_rollback || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_write_file "$previous_file" "$PNM_CORE_BINARY" core_binary 0755 required || {
        rc=$?; pnm_core_update_abort rollback 'binary publication' "$rc"; return "$rc";
    }
    pnm_systemctl restart "$PNM_CORE_UNIT" || { rc=$?; pnm_core_update_abort rollback 'service restart' "$rc"; return "$rc"; }
    if declare -F pnm_check_deploy_core_health >/dev/null 2>&1; then
        pnm_check_deploy_core_health "$core" || { pnm_core_update_abort rollback 'post-rollback health check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG"; }
    else
        pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || { pnm_core_update_abort rollback 'post-rollback health check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG"; }
    fi
    metadata_stage="$PNM_CORE_STAGE/previous.env"
    printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=%s\n' "$core" "$current_version" >"$metadata_stage" || {
        pnm_core_update_abort rollback 'previous version metadata staging' "$PNM_EXIT_CANTCREAT"; return "$PNM_EXIT_CANTCREAT";
    }
    chmod 0600 -- "$metadata_stage" || { pnm_core_update_abort rollback 'previous metadata permissions' "$PNM_EXIT_NOPERM"; return "$PNM_EXIT_NOPERM"; }
    if pnm_core_publish_previous_state "$PNM_CORE_STAGE/current" "$metadata_stage" "$previous_file" "$previous_meta"; then :; else
        rc=$?
        pnm_core_update_abort rollback "$PNM_CORE_UPDATE_FAILURE_STAGE" "$rc"
        return "$rc"
    fi
    [[ "$(pnm_binary_version_number "$previous_file" "$style" 2>/dev/null)" == "$current_version" ]] || {
        pnm_core_update_abort rollback 'previous binary and metadata consistency check' "$PNM_EXIT_CONFIG"; return "$PNM_EXIT_CONFIG";
    }
    pnm_core_refresh_applied || { rc=$?; pnm_core_update_abort rollback 'applied evidence publication' "$rc"; return "$rc"; }
    pnm_tx_verify_written_resources || { rc=$?; pnm_core_update_abort rollback 'published resource verification' "$rc"; return "$rc"; }
    pnm_tx_commit || { rc=$?; pnm_core_update_abort rollback 'transaction commit' "$rc"; return "$rc"; }
    pnm_tx_close || return $?
    pnm_success "$core rolled back to $version."
}

pnm_core_restore_prepare_directory() {
    local path="${1:?restore directory required}" mode="${2:?directory mode required}"
    pnm_validate_managed_path "$path" || return $?
    # Existing private directories must already be administrator-controlled.
    # Refuse foreign ownership instead of changing it outside the transaction.
    if [[ "$mode" != - && -e "$path" ]]; then
        [[ -d "$path" && "$(stat -c '%u:%g' -- "$path")" == 0:0 ]] || return "$PNM_EXIT_NOPERM"
    fi
    pnm_tx_prepare_directory "$path" "$mode"
}

pnm_core_restore_write_file() {
    local source="$1" destination="$2" label="$3" mode="$4" owner="$5" rc=0 metadata_rc
    local owner_uid="${5%%:*}" owner_gid="${5#*:}"
    [[ "$owner" == *:* ]] || return "$PNM_EXIT_CONFIG"
    [[ "$owner_uid" =~ ^[0-9]+$ ]] || owner_uid="$(id -u "$owner_uid")" || return "$PNM_EXIT_NOPERM"
    [[ "$owner_gid" =~ ^[0-9]+$ ]] || owner_gid="$(getent group "$owner_gid" | cut -d: -f3)" || return "$PNM_EXIT_NOPERM"
    [[ "$owner_uid" =~ ^[0-9]+$ && "$owner_gid" =~ ^[0-9]+$ ]] || return "$PNM_EXIT_NOPERM"
    pnm_tx_prepare_directory "$(dirname -- "$destination")" - || return $?
    pnm_tx_write_file "$source" "$destination" "$label" "$mode" required || return $?
    # Check publication receipts before taking responsibility for our own chown.
    # Otherwise a post-publication external chmod could be silently re-enrolled.
    pnm_tx_verify_written_resources || return $?
    chown -- "$owner" "$destination" || rc="$PNM_EXIT_NOPERM"
    # Keep the first ownership error; rejected enrollment leaves its old receipt
    # intact so compensation can either verify it or retain unexpected drift.
    if pnm_tx_record_written_metadata "$destination" required "${mode#0}|$owner_uid|$owner_gid"; then :; else
        metadata_rc=$?
        ((rc != 0)) || rc="$metadata_rc"
    fi
    return "$rc"
}

pnm_core_restore_rollback() {
    local core unit load active enabled prefix
    local PNM_CORE_PRIOR_CONFIG_HASH PNM_CORE_PRIOR_APPLIED_HASH PNM_CORE_PRIOR_APPLIED_ATTRIBUTES PNM_LIFECYCLE_PRE_ACTIVE
    if ((PNM_CORE_RESTORE_STARTED == 1)); then
        for unit in xray.service hysteria-server.service; do
            load="$(pnm_systemd_load_state "$unit")" || return "$PNM_EXIT_SOFTWARE"
            case "$load" in
                loaded)
                    pnm_systemctl stop "$unit" || return "$PNM_EXIT_SOFTWARE"
                    [[ "$(pnm_systemd_active_state "$unit")" == inactive ]] || return "$PNM_EXIT_SOFTWARE"
                    pnm_systemctl disable "$unit" || return "$PNM_EXIT_SOFTWARE"
                    ;;
                not-found) [[ "$(pnm_systemd_active_state "$unit")" == inactive ]] || return "$PNM_EXIT_SOFTWARE" ;;
                *) return "$PNM_EXIT_SOFTWARE" ;;
            esac
        done
    fi
    # Snapshot metadata is authoritative; applying candidate ownership again
    # after restoration would corrupt the pre-operation state.
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    if ((PNM_CORE_RESTORE_STARTED == 1)); then
        pnm_systemd_daemon_reload || return "$PNM_EXIT_SOFTWARE"
        for core in xray hysteria2; do
            pnm_core_resolve "$core" || return $?
            unit="$PNM_CORE_UNIT" prefix=PNM_CORE_RESTORE_XRAY
            [[ "$core" == xray ]] || prefix=PNM_CORE_RESTORE_HY2
            load="${prefix}_LOAD" active="${prefix}_ACTIVE" enabled="${prefix}_ENABLED"
            load="${!load}" active="${!active}" enabled="${!enabled}"
            [[ "$(pnm_systemd_load_state "$unit")" == "$load" ]] || return "$PNM_EXIT_SOFTWARE"
            if [[ "$load" == not-found ]]; then
                [[ "$(pnm_systemd_active_state "$unit")" == inactive ]] || return "$PNM_EXIT_SOFTWARE"
                continue
            fi
            if [[ "$enabled" == enabled ]]; then pnm_systemctl enable "$unit"; else pnm_systemctl disable "$unit"; fi || return "$PNM_EXIT_SOFTWARE"
            if [[ "$active" == active ]]; then pnm_systemctl restart "$unit"; else pnm_systemctl stop "$unit"; fi || return "$PNM_EXIT_SOFTWARE"
            [[ "$(pnm_systemd_active_state "$unit")" == "$active" &&
                "$(pnm_systemd_enabled_state "$unit")" == "$enabled" ]] || return "$PNM_EXIT_SOFTWARE"
            PNM_CORE_PRIOR_CONFIG_HASH="${PNM_CORE_RESTORE_CONFIG_HASH[$core]-}"
            PNM_CORE_PRIOR_APPLIED_HASH="${PNM_CORE_RESTORE_APPLIED_HASH[$core]-}"
            PNM_CORE_PRIOR_APPLIED_ATTRIBUTES="${PNM_CORE_RESTORE_APPLIED_ATTRIBUTES[$core]-}"
            PNM_LIFECYCLE_PRE_ACTIVE="$active"
            pnm_core_recover_applied || return "$PNM_EXIT_SOFTWARE"
        done
    fi
    pnm_tx_restore_directories
}

pnm_core_restore_snapshot() {
    local core unit prefix load active enabled
    local PNM_CORE_PRIOR_CONFIG_HASH PNM_CORE_PRIOR_APPLIED_HASH PNM_CORE_PRIOR_APPLIED_ATTRIBUTES
    PNM_CORE_RESTORE_CONFIG_HASH=() PNM_CORE_RESTORE_APPLIED_HASH=() PNM_CORE_RESTORE_APPLIED_ATTRIBUTES=()
    for core in xray hysteria2; do
        pnm_core_resolve "$core" || return $?
        unit="$PNM_CORE_UNIT" prefix=PNM_CORE_RESTORE_XRAY
        [[ "$core" == xray ]] || prefix=PNM_CORE_RESTORE_HY2
        load="$(pnm_systemd_load_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
        case "$load" in
            loaded)
                active="$(pnm_systemd_active_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
                enabled="$(pnm_systemd_enabled_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
                [[ "$active" =~ ^(active|inactive)$ && "$enabled" =~ ^(enabled|disabled)$ ]] || return "$PNM_EXIT_UNAVAILABLE"
                ;;
            not-found)
                active="$(pnm_systemd_active_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
                enabled="$(pnm_systemd_enabled_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
                [[ "$active" == inactive && ( "$enabled" == not-found || "$enabled" == disabled ) ]] || return "$PNM_EXIT_UNAVAILABLE"
                enabled=disabled
                ;;
            *) return "$PNM_EXIT_UNAVAILABLE" ;;
        esac
        printf -v "${prefix}_LOAD" '%s' "$load"
        printf -v "${prefix}_ACTIVE" '%s' "$active"
        printf -v "${prefix}_ENABLED" '%s' "$enabled"
        PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
        [[ "$load" == not-found ]] || pnm_core_capture_applied || return $?
        PNM_CORE_RESTORE_CONFIG_HASH[$core]="$PNM_CORE_PRIOR_CONFIG_HASH"
        PNM_CORE_RESTORE_APPLIED_HASH[$core]="$PNM_CORE_PRIOR_APPLIED_HASH"
        PNM_CORE_RESTORE_APPLIED_ATTRIBUTES[$core]="$PNM_CORE_PRIOR_APPLIED_ATTRIBUTES"
    done
}

pnm_core_restore_abort() {
    local original_rc="$1" recovery_rc=0
    PNM_TX_STEP_FAILURE_RC="$original_rc"
    if pnm_tx_rollback; then
        pnm_error "Core restore failed (rc=$original_rc); prior resources and service policy were restored."
    else
        recovery_rc=$?
        pnm_error "Core restore failed (rc=$original_rc) and rollback failed (rc=$recovery_rc); recovery files were retained."
    fi
    pnm_tx_close || pnm_warn 'Restore transaction cleanup failed; inspect recovery evidence.'
    return "$original_rc"
}

pnm_core_restore_validate_staged() {
    local staging="${1:?staged restore directory required}" xray_version hy2_version validation_output tls_result tls_status xray_unit_text hysteria_unit_text
    local -A PNM_RESTORE_NODE=() PNM_RESTORE_VERSIONS=() PNM_RESTORE_REALITY=() PNM_RESTORE_HYSTERIA=()

    [[ -f "$staging/etc/hysteria/tls/server.crt" && -f "$staging/etc/hysteria/tls/server.key" &&
        -f "$staging/etc/pnm/secrets/reality.env" && -f "$staging/etc/pnm/secrets/hysteria.env" ]] || return "$PNM_EXIT_CONFIG"
    chmod 0755 -- "$staging/usr/local/bin/xray" "$staging/usr/local/bin/hysteria" || return "$PNM_EXIT_NOPERM"
    chmod 0600 -- "$staging/etc/hysteria/tls/server.key" "$staging/etc/pnm/secrets/reality.env" \
        "$staging/etc/pnm/secrets/hysteria.env" || return "$PNM_EXIT_NOPERM"
    pnm_config_load "$staging/etc/pnm/node.conf" PNM_RESTORE_NODE SCHEMA_VERSION NODE_REGION NODE_ADDRESS TIMEZONE PNM_CONFIGURED XRAY_PORT XRAY_SERVER_NAME XRAY_TARGET HY2_PORT HY2_TLS_MODE HY2_TLS_SERVER_NAME || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config PNM_RESTORE_NODE || return "$PNM_EXIT_CONFIG"
    pnm_config_load "$staging/etc/pnm/versions.conf" PNM_RESTORE_VERSIONS SCHEMA_VERSION XRAY_VERSION XRAY_SHA256 HY2_VERSION HY2_SHA256 APPROVED || return "$PNM_EXIT_CONFIG"
    pnm_validate_versions_config PNM_RESTORE_VERSIONS || return "$PNM_EXIT_CONFIG"
    xray_unit_text="$(<"$staging/etc/systemd/system/xray.service")"
    hysteria_unit_text="$(<"$staging/etc/systemd/system/hysteria-server.service")"
    pnm_unit_validate_text "$xray_unit_text" xray /usr/local/bin/xray || return "$PNM_EXIT_CONFIG"
    pnm_unit_validate_text "$hysteria_unit_text" hysteria /usr/local/bin/hysteria || return "$PNM_EXIT_CONFIG"
    [[ "$xray_unit_text" == *$'CapabilityBoundingSet=CAP_NET_BIND_SERVICE'* &&
        "$xray_unit_text" == *$'AmbientCapabilities=CAP_NET_BIND_SERVICE'* ]] || return "$PNM_EXIT_CONFIG"
    [[ "$hysteria_unit_text"$'\n' == *$'\nCapabilityBoundingSet=\n'* &&
        "$hysteria_unit_text"$'\n' == *$'\nAmbientCapabilities=\n'* ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_validate_unit_file "$staging/etc/systemd/system/xray.service" &&
        pnm_systemd_validate_unit_file "$staging/etc/systemd/system/hysteria-server.service" || return "$PNM_EXIT_CONFIG"
    # Validate the complete candidate set while it is still isolated. Never
    # apply archive contents and then discover that their config/binaries do
    # not agree.
    pnm_config_load "$staging/etc/pnm/secrets/reality.env" PNM_RESTORE_REALITY SCHEMA_VERSION XRAY_UUID XRAY_REALITY_PRIVATE_KEY XRAY_REALITY_SHORT_ID || return "$PNM_EXIT_CONFIG"
    pnm_validate_reality_secret_config PNM_RESTORE_REALITY || return "$PNM_EXIT_CONFIG"
    pnm_config_load "$staging/etc/pnm/secrets/hysteria.env" PNM_RESTORE_HYSTERIA SCHEMA_VERSION HY2_AUTH_PASSWORD HY2_TLS_CERT_PATH HY2_TLS_KEY_PATH HY2_TLS_PIN_SHA256 || return "$PNM_EXIT_CONFIG"
    pnm_validate_hysteria_secret_config PNM_RESTORE_HYSTERIA || return "$PNM_EXIT_CONFIG"
    [[ "${PNM_RESTORE_HYSTERIA[HY2_TLS_CERT_PATH]}" == /etc/hysteria/tls/server.crt &&
        "${PNM_RESTORE_HYSTERIA[HY2_TLS_KEY_PATH]}" == /etc/hysteria/tls/server.key ]] || return "$PNM_EXIT_CONFIG"
    xray_version="$(pnm_binary_version_number "$staging/usr/local/bin/xray" xray 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    hy2_version="$(pnm_binary_version_number "$staging/usr/local/bin/hysteria" hysteria 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    [[ "$xray_version" == "${PNM_RESTORE_VERSIONS[XRAY_VERSION]#v}" &&
        "$hy2_version" == "${PNM_RESTORE_VERSIONS[HY2_VERSION]#v}" ]] || return "$PNM_EXIT_CONFIG"
    pnm_capture validation_output "$staging/usr/local/bin/xray" run -test -config "$staging/usr/local/etc/xray/config.json" || return "$PNM_EXIT_CONFIG"
    pnm_hysteria_config_validate_candidate "$staging/etc/hysteria/config.yaml" PNM_RESTORE_NODE PNM_RESTORE_HYSTERIA || return "$PNM_EXIT_CONFIG"
    pnm_tls_validate_pair "$staging/etc/hysteria/tls/server.crt" "$staging/etc/hysteria/tls/server.key" || return "$PNM_EXIT_CONFIG"
    tls_result="$(pnm_tls_certificate_check "${PNM_RESTORE_NODE[HY2_TLS_MODE]}" "$staging/etc/hysteria/tls/server.crt")"
    IFS='|' read -r tls_status _ <<<"$tls_result"
    [[ "$tls_status" == OK ]] || return "$PNM_EXIT_CONFIG"
    pnm_hysteria_tls_server_name PNM_RESTORE_NODE PNM_RESTORE_HYSTERIA "$staging/etc/hysteria/tls/server.crt" >/dev/null || return "$PNM_EXIT_CONFIG"
}

pnm_core_restore() {
    pnm_require_root || return $?
    pnm_core_with_write_lock pnm_core_restore_locked "$1"
}

pnm_core_restore_locked() {
    local archive=$1 staging rc archive_identity
    PNM_CORE_RESTORE_STARTED=0
    [[ -f "$archive" && ! -L "$archive" ]] || return "$PNM_EXIT_CONFIG"
    archive_identity="$(stat -c '%a:%u:%d:%i' -- "$archive" 2>/dev/null)" || return "$PNM_EXIT_NOPERM"
    [[ "$archive_identity" =~ ^600:0:[0-9]+:[0-9]+$ ]] || return "$PNM_EXIT_NOPERM"
    archive_identity="${archive_identity#600:0:}"
    pnm_platform_supported || return "$PNM_EXIT_CONFIG"
    pnm_make_temp_dir staging || return $?
    if python3 - "$archive" "$staging" "$archive_identity" <<'PY'
import contextlib, os, pathlib, resource, shutil, stat, sys, tarfile
allowed = {"etc/pnm/node.conf", "etc/pnm/versions.conf", "etc/pnm/secrets/reality.env",
 "etc/pnm/secrets/hysteria.env", "usr/local/etc/xray/config.json", "etc/hysteria/config.yaml",
 "etc/hysteria/tls/server.crt", "etc/hysteria/tls/server.key", "usr/local/bin/xray",
 "usr/local/bin/hysteria", "etc/systemd/system/xray.service", "etc/systemd/system/hysteria-server.service"}
root = pathlib.Path(sys.argv[2])
try:
    # tarfile consumes PAX/GNU extension records before yielding a visible
    # member. Bound the whole parser process, including those hidden records.
    # Normal resource files are copied in 1 MiB chunks below.
    for kind, budget in ((resource.RLIMIT_AS, 128 * 1024 * 1024), (resource.RLIMIT_CPU, 30)):
        inherited = resource.getrlimit(kind)
        limit = min([budget] + [value for value in inherited if value != resource.RLIM_INFINITY])
        resource.setrlimit(kind, (limit, limit))
    with contextlib.ExitStack() as resources:
        # Pin the object checked by the caller. NONBLOCK prevents a swapped
        # FIFO from waiting before fstat can reject it; tar reads regular files.
        stream = resources.enter_context(os.fdopen(os.open(
            sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb"))
        identity = os.fstat(stream.fileno())
        if (not stat.S_ISREG(identity.st_mode) or identity.st_uid != os.geteuid()
                or stat.S_IMODE(identity.st_mode) != 0o600
                or f"{identity.st_dev}:{identity.st_ino}" != sys.argv[3]):
            raise ValueError("backup identity or protected permissions changed")
        source = resources.enter_context(tarfile.open(fileobj=stream, mode="r:gz"))
        members, seen, manifest_item = {}, set(), None
        total_size = 0
        # Stop at the limit while enumerating, rather than first retaining an
        # unbounded complete member list. Never normalize absolute paths.
        for member_count, item in enumerate(source, start=1):
            if member_count > 64:
                raise ValueError("too many backup members")
            name = item.name.removeprefix("./")
            if pathlib.PurePosixPath(name).is_absolute() or ".." in pathlib.PurePosixPath(name).parts:
                raise ValueError("unsafe backup path")
            if name in ("", "."):
                if not item.isdir() or item.size != 0:
                    raise ValueError("invalid backup root directory")
                continue
            if name == "MANIFEST.txt":
                if not item.isfile() or manifest_item is not None: raise ValueError("invalid or duplicate manifest")
                if not 0 <= item.size <= 65536: raise ValueError("backup manifest exceeds size limit")
                total_size += item.size
                manifest_item = item
            elif name in allowed:
                if not item.isfile() or name in seen: raise ValueError("unsafe or duplicate backup member")
                if not 0 <= item.size <= 268435456: raise ValueError("backup member exceeds size limit")
                total_size += item.size
                seen.add(name); members[name] = item
            elif not item.isdir() or item.size != 0:
                raise ValueError("unexpected backup member")
            if total_size > 536870912: raise ValueError("backup exceeds total size limit")
        if not allowed <= seen:
            raise ValueError("backup lacks required Core state")
        manifest = None if manifest_item is None else source.extractfile(manifest_item)
        if manifest is None or b"CONTAINS SECRETS" not in manifest.read(256):
            raise ValueError("backup manifest does not identify contained secrets")
        with source.extractfile(manifest_item) as data, (root / "MANIFEST.txt").open("xb") as out:
            out.write(data.read())
        for name, item in members.items():
            target = root / name; target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            data = source.extractfile(item)
            if data is None: raise ValueError("backup member unreadable")
            with data, target.open("xb") as out: shutil.copyfileobj(data, out, 1048576)
except (OSError, tarfile.TarError, ValueError, MemoryError, OverflowError, RecursionError) as error:
    print(f"invalid backup: {error}", file=sys.stderr); sys.exit(1)
PY
    then
        :
    else
        pnm_error 'Restore archive parsing failed; no managed resource was changed.'
        return "$PNM_EXIT_CONFIG"
    fi
    if pnm_core_restore_validate_staged "$staging"; then :; else
        rc=$?
        pnm_error "Restore candidate validation failed before apply (rc=$rc); the current Core files and services were not changed."
        return "$rc"
    fi
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_core_restore_snapshot || return $?
    pnm_tx_begin core-restore || return $?
    pnm_tx_add_rollback pnm_core_restore_rollback || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_core_restore_apply_staged "$staging"; then :; else
        rc=$?; pnm_core_restore_abort "$rc"; return $?;
    fi
    pnm_tx_commit || { rc=$?; pnm_core_restore_abort "$rc"; return $?; }
    pnm_tx_close || return $?
    pnm_success 'Both Cores restored and healthy.'
}

pnm_core_restore_apply_staged() {
    local staging="$1" directory file destination mode owner unit core record index=0
    local -a files=()
    # Retain the service baseline as protected data for manual recovery after
    # an uncatchable interruption. It is never sourced or replayed as code.
    (umask 077; printf 'SCHEMA_VERSION=1\nXRAY_LOAD=%s\nXRAY_ACTIVE=%s\nXRAY_ENABLED=%s\nHY2_LOAD=%s\nHY2_ACTIVE=%s\nHY2_ENABLED=%s\n' \
        "$PNM_CORE_RESTORE_XRAY_LOAD" "$PNM_CORE_RESTORE_XRAY_ACTIVE" "$PNM_CORE_RESTORE_XRAY_ENABLED" \
        "$PNM_CORE_RESTORE_HY2_LOAD" "$PNM_CORE_RESTORE_HY2_ACTIVE" "$PNM_CORE_RESTORE_HY2_ENABLED" \
        >"$PNM_TX_PATH/restore.env") || return "$PNM_EXIT_CANTCREAT"
    PNM_CORE_RESTORE_STARTED=1
    for unit in xray.service hysteria-server.service; do
        if [[ "$(pnm_systemd_load_state "$unit")" == loaded ]]; then
            pnm_systemctl stop "$unit" || return $?
            [[ "$(pnm_systemd_active_state "$unit")" == inactive ]] || return "$PNM_EXIT_SOFTWARE"
        fi
    done
    for directory in /etc/pnm /usr/local/etc/xray /etc/hysteria /etc/hysteria/tls; do
        pnm_core_restore_prepare_directory "$directory" 0755 || return $?
    done
    pnm_core_restore_prepare_directory /etc/pnm/secrets 0700 || return $?
    while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$staging" -type f -print0)
    for file in "${files[@]}"; do
        [[ "$file" == "$staging/MANIFEST.txt" ]] && continue
        destination="/${file#"$staging"/}"
        owner=root:root
        case "$destination" in
            /usr/local/bin/*) mode=0755 ;;
            /etc/systemd/system/*.service) mode=0644 ;;
            /usr/local/etc/xray/config.json) mode=0640 owner=root:xray ;;
            /etc/hysteria/config.yaml|/etc/hysteria/tls/server.key) mode=0600 owner=hysteria:hysteria ;;
            /etc/hysteria/tls/server.crt) mode=0644 owner=root:hysteria ;;
            *) mode=0600 ;;
        esac
        ((index += 1))
        pnm_core_restore_write_file "$file" "$destination" "restore_$index" "$mode" "$owner" || return $?
    done
    pnm_systemd_daemon_reload || return "$PNM_EXIT_SOFTWARE"
    pnm_core_restore_prepare_directory /etc/systemd/system/multi-user.target.wants - || return $?
    pnm_systemctl enable xray.service || return $?
    pnm_systemctl enable hysteria-server.service || return $?
    pnm_systemctl restart xray.service || return $?
    pnm_systemctl restart hysteria-server.service || return $?
    pnm_systemd_unit_healthy xray.service && pnm_systemd_unit_healthy hysteria-server.service || return "$PNM_EXIT_CONFIG"
    declare -F pnm_check_deploy_core_health >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
    pnm_check_deploy_core_health xray && pnm_check_deploy_core_health hysteria2 || return "$PNM_EXIT_CONFIG"
    for core in xray hysteria2; do
        [[ -n "${PNM_CORE_RESTORE_APPLIED_HASH[$core]-}" ]] || continue
        record="$PNM_STATE_DIR/cores/$core/applied.env"
        pnm_validate_managed_path "$record" || return $?
        [[ "$(pnm_tx_file_sha256 "$record")" == "${PNM_CORE_RESTORE_APPLIED_HASH[$core]}" &&
            "$(stat -c '%a:%u:%g' -- "$record")" == "${PNM_CORE_RESTORE_APPLIED_ATTRIBUTES[$core]}" ]] || return "$PNM_EXIT_SOFTWARE"
    done
    pnm_make_temp_dir PNM_CORE_STAGE || return "$PNM_EXIT_CANTCREAT"
    pnm_core_record_applied_config xray "$PNM_XRAY_CONFIG" "$PNM_CORE_STAGE" || return $?
    pnm_core_record_applied_config hysteria2 "$PNM_HY2_CONFIG" "$PNM_CORE_STAGE" || return $?
    pnm_tx_verify_written_resources
}

PNM_CORE_REMOVE_PATHS=()
PNM_CORE_REMOVE_STAGED=()

pnm_core_uninstall_restore() {
    local index rc=0
    for ((index=${#PNM_CORE_REMOVE_PATHS[@]} - 1; index >= 0; index -= 1)); do
        if [[ -e "${PNM_CORE_REMOVE_STAGED[index]}" ]]; then
            mkdir -p -- "$(dirname -- "${PNM_CORE_REMOVE_PATHS[index]}")" || { rc="$PNM_EXIT_SOFTWARE"; continue; }
            mv -n -- "${PNM_CORE_REMOVE_STAGED[index]}" "${PNM_CORE_REMOVE_PATHS[index]}" || rc="$PNM_EXIT_SOFTWARE"
        fi
    done
    pnm_core_lifecycle_restore || rc="$PNM_EXIT_SOFTWARE"
    return "$rc"
}

pnm_core_uninstall_stop() {
    pnm_systemctl stop "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
    pnm_systemctl disable "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_uninstall() {
    pnm_core_resolve "$1" || return $?
    pnm_require_root || return $?
    ((PNM_ASSUME_YES == 1)) || { pnm_error 'Uninstall requires --yes.'; return "$PNM_EXIT_USAGE"; }
    pnm_core_with_write_lock pnm_core_uninstall_locked "$PNM_CORE_ID"
}

pnm_core_uninstall_locked() {
    local core unit binary config secret backup stage path target rc index=0 uninstall_root
    local -a paths=()
    pnm_core_resolve "$1" || return $?
    core=$PNM_CORE_ID unit=$PNM_CORE_UNIT binary=$PNM_CORE_BINARY config=$PNM_CORE_CONFIG
    pnm_core_backup '' >/dev/null || return $?
    backup="$PNM_CORE_BACKUP_PATH"
    if [[ "$core" == xray ]]; then
        secret="$PNM_CONFIG_DIR/secrets/reality.env"
        paths=("$binary" "$config" "$secret" /etc/systemd/system/xray.service)
    else
        secret="$PNM_CONFIG_DIR/secrets/hysteria.env"
        paths=("$binary" "$config" "$secret" /etc/hysteria/tls/server.crt /etc/hysteria/tls/server.key /etc/systemd/system/hysteria-server.service)
    fi
    uninstall_root="$PNM_STATE_DIR/uninstall"
    pnm_mkdir_mode 0700 "$uninstall_root" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$uninstall_root" && ! -L "$uninstall_root" ]] || return "$PNM_EXIT_CONFIG"
    stage="$uninstall_root/$core-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
    [[ "$stage" == "$uninstall_root/"* ]] || return "$PNM_EXIT_CONFIG"
    mkdir -m 0700 -- "$stage" || return "$PNM_EXIT_CANTCREAT"
    pnm_core_lifecycle_snapshot "$core" || { rc=$?; rmdir -- "$stage" || true; return "$rc"; }
    PNM_CORE_REMOVE_PATHS=()
    PNM_CORE_REMOVE_STAGED=()
    pnm_tx_begin "core-uninstall-$core" || { rc=$?; rmdir -- "$stage" || true; return "$rc"; }
    pnm_tx_add_rollback pnm_core_uninstall_restore || { pnm_tx_close; rmdir -- "$stage"; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run stop_core pnm_core_uninstall_stop; then :; else rc=$?; pnm_tx_close; rm -rf -- "$stage"; return "$rc"; fi
    for path in "${paths[@]}"; do
        [[ -e "$path" && ! -L "$path" ]] || continue
        ((index += 1))
        target="$stage/$index"
        if mv -- "$path" "$target"; then
            PNM_CORE_REMOVE_PATHS+=("$path")
            PNM_CORE_REMOVE_STAGED+=("$target")
        else
            pnm_tx_rollback || true
            pnm_tx_close
            rm -rf -- "$stage"
            return "$PNM_EXIT_CANTCREAT"
        fi
    done
    pnm_systemd_daemon_reload || { pnm_tx_rollback || true; pnm_tx_close; rm -rf -- "$stage"; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close || return $?
    rm -rf -- "$stage" || return "$PNM_EXIT_SOFTWARE"
    pnm_success "$core removed; rollback backup: $backup"
}

pnm_core_command() {
    local command=$1
    shift
    if ((PNM_DRY_RUN == 1)) && [[ "$command" != log ]]; then
        pnm_error '--dry-run is supported only by install.'
        return "$PNM_EXIT_USAGE"
    fi
    case "$command" in
        restart) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_restart "$1" ;;
        log) (($# >= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_log "$@" ;;
        apply) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_apply_config "$1" ;;
        backup) (($# <= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_backup "${1-}" ;;
        restore) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_restore "$1" ;;
        update) (($# >= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_update "$@" ;;
        rollback) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_rollback "$1" ;;
        uninstall)
            (($# >= 1 && $# <= 2)) || return "$PNM_EXIT_USAGE"
            [[ "${2-}" != --yes ]] || PNM_ASSUME_YES=1
            (($# == 1)) || [[ "$2" == --yes ]] || return "$PNM_EXIT_USAGE"
            pnm_core_uninstall "$1"
            ;;
        *) return "$PNM_EXIT_USAGE" ;;
    esac
}

pnm_core_menu_select() {
    local action=$1 core
    read -r -p 'Core [xray/hy2]: ' core || return "$PNM_EXIT_USAGE"
    pnm_core_command "$action" "$core"
}

pnm_core_menu_restore() {
    local archive
    read -r -p 'Backup archive path: ' archive || return "$PNM_EXIT_USAGE"
    pnm_core_command restore "$archive"
}

pnm_core_menu_uninstall() {
    local core
    read -r -p 'Core [xray/hy2]: ' core || return "$PNM_EXIT_USAGE"
    read -r -p "Create a Secret-bearing backup and remove $core? Type yes: " answer || return "$PNM_EXIT_USAGE"
    [[ "$answer" == yes ]] || return 0
    pnm_core_command uninstall "$core" --yes
}
