#!/usr/bin/env bash

PNM_DEPLOY_ID=''
PNM_DEPLOY_PATH=''
PNM_DEPLOY_ACTIVE=0
PNM_DEPLOY_COMMITTED=0
PNM_DEPLOY_JOURNAL_ERROR=0
PNM_DEPLOY_XRAY_ACTIVE=''
PNM_DEPLOY_XRAY_ENABLED=''
PNM_DEPLOY_HY2_ACTIVE=''
PNM_DEPLOY_HY2_ENABLED=''
PNM_DEPLOY_XRAY_LOAD=''
PNM_DEPLOY_HY2_LOAD=''
PNM_DEPLOY_RESOURCES_STARTED=0
PNM_DEPLOY_XRAY_APPLIED=0
PNM_DEPLOY_HY2_APPLIED=0
PNM_DEPLOY_XRAY_CONFIG_HASH=MISSING
PNM_DEPLOY_HY2_CONFIG_HASH=MISSING
declare -Ag PNM_DEPLOY_PRIOR_APPLIED_HASH=() PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES=()
PNM_DEPLOY_STEP_SANDBOX="${PNM_DEPLOY_STEP_SANDBOX:-pnm_deploy_sandbox_step}"
PNM_DEPLOY_STEP_XRAY="${PNM_DEPLOY_STEP_XRAY:-pnm_core_lifecycle_apply_xray_step}"
PNM_DEPLOY_STEP_HYSTERIA="${PNM_DEPLOY_STEP_HYSTERIA:-pnm_core_lifecycle_apply_hysteria_step}"
PNM_DEPLOY_STEP_HEALTH="${PNM_DEPLOY_STEP_HEALTH:-pnm_deploy_health_step}"

pnm_deploy_new_id() {
    if [[ -n "${PNM_DEPLOY_ID_OVERRIDE:-}" ]]; then
        printf '%s\n' "$PNM_DEPLOY_ID_OVERRIDE"
    else
        printf 'deploy-%s-%s\n' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$"
    fi
}

pnm_deploy_journal() {
    local phase="${1:?deployment phase required}"
    local detail="${2-}"

    ((PNM_DEPLOY_ACTIVE == 1 && PNM_DRY_RUN == 0)) || return 0
    printf '%s\t%s\t%s\n' "$(pnm_now_utc)" "$phase" "$(pnm_one_line "$detail")" >>"$PNM_DEPLOY_PATH/journal.tsv" || return "$PNM_EXIT_CANTCREAT"
}

pnm_deploy_begin() {
    local deployments_dir owner_mode xray_load hy2_load

    ((PNM_DEPLOY_ACTIVE == 0)) || return "$PNM_EXIT_SOFTWARE"
    PNM_DEPLOY_ID="$(pnm_deploy_new_id)"
    PNM_DEPLOY_COMMITTED=0
    PNM_DEPLOY_JOURNAL_ERROR=0
    PNM_DEPLOY_RESOURCES_STARTED=0
    PNM_DEPLOY_XRAY_APPLIED=0 PNM_DEPLOY_HY2_APPLIED=0
    PNM_DEPLOY_XRAY_CONFIG_HASH=MISSING PNM_DEPLOY_HY2_CONFIG_HASH=MISSING
    PNM_DEPLOY_PRIOR_APPLIED_HASH=() PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES=()
    PNM_ACCOUNTS_CREATED_USERS=() PNM_ACCOUNTS_CREATED_GROUPS=()
    if ((PNM_DRY_RUN == 1)); then
        PNM_DEPLOY_PATH="dry-run:$PNM_DEPLOY_ID"
        PNM_DEPLOY_ACTIVE=1
        return 0
    fi
    pnm_require_root || return $?
    xray_load="$(pnm_systemd_load_state xray.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
    hy2_load="$(pnm_systemd_load_state hysteria-server.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$xray_load" =~ ^(loaded|not-found)$ && "$hy2_load" =~ ^(loaded|not-found)$ ]] || return "$PNM_EXIT_CONFIG"
    PNM_DEPLOY_XRAY_LOAD="$xray_load" PNM_DEPLOY_HY2_LOAD="$hy2_load"
    if [[ "$xray_load" == not-found ]]; then
        PNM_DEPLOY_XRAY_ACTIVE=inactive PNM_DEPLOY_XRAY_ENABLED=disabled
    else
        PNM_DEPLOY_XRAY_ACTIVE="$(pnm_systemd_active_state xray.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
        PNM_DEPLOY_XRAY_ENABLED="$(pnm_systemd_enabled_state xray.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$PNM_DEPLOY_XRAY_ACTIVE" == active || "$PNM_DEPLOY_XRAY_ACTIVE" == inactive ]] || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$PNM_DEPLOY_XRAY_ENABLED" == enabled || "$PNM_DEPLOY_XRAY_ENABLED" == disabled ]] || return "$PNM_EXIT_UNAVAILABLE"
    fi
    if [[ "$hy2_load" == not-found ]]; then
        PNM_DEPLOY_HY2_ACTIVE=inactive PNM_DEPLOY_HY2_ENABLED=disabled
    else
        PNM_DEPLOY_HY2_ACTIVE="$(pnm_systemd_active_state hysteria-server.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
        PNM_DEPLOY_HY2_ENABLED="$(pnm_systemd_enabled_state hysteria-server.service 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$PNM_DEPLOY_HY2_ACTIVE" == active || "$PNM_DEPLOY_HY2_ACTIVE" == inactive ]] || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$PNM_DEPLOY_HY2_ENABLED" == enabled || "$PNM_DEPLOY_HY2_ENABLED" == disabled ]] || return "$PNM_EXIT_UNAVAILABLE"
    fi
    pnm_deploy_validate_ownership || return "$PNM_EXIT_CONFIG"
    [[ "$PNM_STATE_DIR" == /* && "$PNM_STATE_DIR" != / ]] || return "$PNM_EXIT_CONFIG"
    pnm_mkdir_mode 0700 "$PNM_STATE_DIR" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$PNM_STATE_DIR" && ! -L "$PNM_STATE_DIR" ]] || return "$PNM_EXIT_CONFIG"
    owner_mode="$(stat -c '%a|%u' -- "$PNM_STATE_DIR" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return "$PNM_EXIT_NOPERM"
    deployments_dir="$PNM_STATE_DIR/deployments"
    pnm_mkdir_mode 0700 "$deployments_dir" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$deployments_dir" && ! -L "$deployments_dir" ]] || return "$PNM_EXIT_CONFIG"
    owner_mode="$(stat -c '%a|%u' -- "$deployments_dir" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return "$PNM_EXIT_NOPERM"
    [[ "$PNM_DEPLOY_ID" =~ ^deploy-[A-Za-z0-9._-]{1,80}$ ]] || return "$PNM_EXIT_CONFIG"
    PNM_DEPLOY_PATH="$deployments_dir/$PNM_DEPLOY_ID"
    mkdir -m 0700 -- "$PNM_DEPLOY_PATH" || return "$PNM_EXIT_CANTCREAT"
    : >"$PNM_DEPLOY_PATH/journal.tsv" || { rmdir -- "$PNM_DEPLOY_PATH"; return "$PNM_EXIT_CANTCREAT"; }
    chmod 0600 -- "$PNM_DEPLOY_PATH/journal.tsv" || { rm -rf -- "$PNM_DEPLOY_PATH"; return "$PNM_EXIT_NOPERM"; }
    PNM_DEPLOY_ACTIVE=1
    if ! pnm_deploy_journal BEGIN 'deployment orchestration'; then
        rm -rf -- "$PNM_DEPLOY_PATH"
        PNM_DEPLOY_ACTIVE=0
        PNM_DEPLOY_ID=''
        PNM_DEPLOY_PATH=''
        return "$PNM_EXIT_CANTCREAT"
    fi
}

pnm_deploy_run_phase() {
    local phase="${1:?deployment phase required}"
    local function_name="${2:?deployment step required}"
    local rc

    ((PNM_DEPLOY_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    if ! pnm_deploy_journal PHASE_BEGIN "$phase"; then
        PNM_DEPLOY_JOURNAL_ERROR=1
        return "$PNM_EXIT_CANTCREAT"
    fi
    if "$function_name"; then
        if ! pnm_deploy_journal PHASE_DONE "$phase"; then
            PNM_DEPLOY_JOURNAL_ERROR=1
            return "$PNM_EXIT_CANTCREAT"
        fi
        return 0
    else
        rc=$?
    fi
    if ! pnm_deploy_journal PHASE_FAILED "$phase rc=$rc"; then
        PNM_DEPLOY_JOURNAL_ERROR=1
        return "$PNM_EXIT_CANTCREAT"
    fi
    return "$rc"
}

pnm_deploy_sandbox_step() {
    [[ -n "${PNM_DEPLOY_SANDBOX_ROOT:-}" ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_DEPLOY_SANDBOX_ROOT" == '/' ]]; then
        declare -F pnm_host_apply_resources_step >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
        pnm_host_apply_resources_step "$PNM_DEPLOY_ID"
        return $?
    fi
    pnm_sandbox_install_deployment "$PNM_DEPLOY_SANDBOX_ROOT" "$PNM_DEPLOY_ID"
}

pnm_core_lifecycle_apply_xray_step() {
    pnm_core_lifecycle_deployment_apply xray "$PNM_DEPLOY_ID"
}

pnm_core_lifecycle_apply_hysteria_step() {
    pnm_core_lifecycle_deployment_apply hysteria2 "$PNM_DEPLOY_ID"
}

pnm_deploy_health_step() {
    declare -F pnm_check_deploy_core_health >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
    pnm_check_deploy_core_health xray || {
        pnm_error 'post-health failed for Xray; deployment remains uncommitted.'
        return "$PNM_EXIT_CONFIG"
    }
    pnm_check_deploy_core_health hysteria2 || {
        pnm_error 'post-health failed for Hysteria2; deployment remains uncommitted.'
        return "$PNM_EXIT_CONFIG"
    }
}

pnm_deploy_stage_configured() {
    local temp_dir staged rc
    local -A node=()

    pnm_load_node_config node || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config node || return "$PNM_EXIT_CONFIG"
    [[ "${node[PNM_CONFIGURED]}" == no ]] || return "$PNM_EXIT_CONFIG"
    pnm_make_temp_dir temp_dir || return $?
    staged="$temp_dir/node.conf"
    if ! printf 'SCHEMA_VERSION=%s\nNODE_REGION=%s\nNODE_ADDRESS=%s\nTIMEZONE=%s\nPNM_CONFIGURED=yes\nXRAY_PORT=%s\nXRAY_SERVER_NAME=%s\nXRAY_TARGET=%s\nHY2_PORT=%s\nHY2_TLS_MODE=%s\nHY2_TLS_SERVER_NAME=%s\n' \
        "${node[SCHEMA_VERSION]}" "${node[NODE_REGION]}" "${node[NODE_ADDRESS]-}" "${node[TIMEZONE]}" "${node[XRAY_PORT]}" \
        "${node[XRAY_SERVER_NAME]}" "${node[XRAY_TARGET]}" "${node[HY2_PORT]}" "${node[HY2_TLS_MODE]}" \
        "${node[HY2_TLS_SERVER_NAME]-}" >"$staged"; then
        return "$PNM_EXIT_CANTCREAT"
    fi
    declare -F pnm_core_record_applied_config >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
    pnm_core_record_applied_config xray "$PNM_XRAY_CONFIG" "$temp_dir" || return $?
    pnm_core_record_applied_config hysteria2 "$PNM_HY2_CONFIG" "$temp_dir" || return $?
    pnm_tx_write_file "$staged" "$PNM_CONFIG_DIR/node.conf" node_config 0600
}

pnm_deploy_mark_configured() {
    local rc
    if [[ -n "${1-}" ]]; then
        pnm_deploy_require_transaction "$1" || return $?
        pnm_deploy_stage_configured
        return $?
    fi
    pnm_tx_begin install-state || return $?
    # Rollbacks run in reverse registration order: files before directories.
    pnm_tx_add_rollback pnm_tx_restore_directories || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_add_rollback pnm_tx_restore_written_files || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_deploy_stage_configured; then :; else
        rc=$?; pnm_tx_rollback || rc="$PNM_EXIT_SOFTWARE"; pnm_tx_close || true; return "$rc"
    fi
    if pnm_tx_commit; then :; else
        rc=$?
        if ! pnm_tx_rollback; then
            pnm_error 'Node-state transaction commit failed and rollback also failed; inspect transaction recovery state.'
        fi
        pnm_tx_close || true
        return "$rc"
    fi
    pnm_tx_close
}
pnm_deploy_require_transaction() {
    local deployment_id="${1:?deployment id required}"
    ((PNM_TX_ACTIVE == 1 && PNM_DEPLOY_ACTIVE == 1 && PNM_TX_COMMITTED == 0)) || return "$PNM_EXIT_SOFTWARE"
    [[ "$PNM_TX_OPERATION" == deployment && "$deployment_id" == "$PNM_DEPLOY_ID" &&
        "$PNM_TX_DEPLOYMENT_ID" == "$deployment_id" ]] || return "$PNM_EXIT_SOFTWARE"
}

pnm_deploy_record_baseline() {
    local core config status record
    for core in xray hysteria2; do
        if [[ "$core" == xray ]]; then config="$PNM_XRAY_CONFIG"; else config="$PNM_HY2_CONFIG"; fi
        status=unknown
        if declare -F pnm_core_applied_config_status >/dev/null 2>&1; then
            status="$(pnm_core_applied_config_status "$core" "$config")" || return "$PNM_EXIT_CONFIG"
        fi
        if [[ "$status" == confirmed ]]; then
            record="$PNM_STATE_DIR/cores/$core/applied.env"
            pnm_validate_managed_path "$record" || return "$PNM_EXIT_CONFIG"
            [[ -f "$record" && ! -L "$record" && "$(stat -c '%a|%u' -- "$record")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
            PNM_DEPLOY_PRIOR_APPLIED_HASH[$core]="$(pnm_tx_file_sha256 "$record")" || return $?
            PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[$core]="$(stat -c '%a:%u:%g' -- "$record")" || return $?
            if [[ "$core" == xray ]]; then
                PNM_DEPLOY_XRAY_APPLIED=1
                PNM_DEPLOY_XRAY_CONFIG_HASH="$(pnm_tx_file_sha256 "$config")" || return $?
            else
                PNM_DEPLOY_HY2_APPLIED=1
                PNM_DEPLOY_HY2_CONFIG_HASH="$(pnm_tx_file_sha256 "$config")" || return $?
            fi
        fi
    done
    (umask 077; printf 'SCHEMA_VERSION=1\nAPPLY_ID=%s\nXRAY_LOAD=%s\nXRAY_ACTIVE=%s\nXRAY_ENABLED=%s\nHY2_LOAD=%s\nHY2_ACTIVE=%s\nHY2_ENABLED=%s\nXRAY_APPLIED=%s\nHY2_APPLIED=%s\nXRAY_CONFIG_HASH=%s\nHY2_CONFIG_HASH=%s\nXRAY_APPLIED_HASH=%s\nHY2_APPLIED_HASH=%s\nXRAY_APPLIED_ATTRIBUTES=%s\nHY2_APPLIED_ATTRIBUTES=%s\n' \
        "${PNM_APPLY_GATE_ID:-none}" "$PNM_DEPLOY_XRAY_LOAD" "$PNM_DEPLOY_XRAY_ACTIVE" "$PNM_DEPLOY_XRAY_ENABLED" \
        "$PNM_DEPLOY_HY2_LOAD" "$PNM_DEPLOY_HY2_ACTIVE" "$PNM_DEPLOY_HY2_ENABLED" \
        "$PNM_DEPLOY_XRAY_APPLIED" "$PNM_DEPLOY_HY2_APPLIED" "$PNM_DEPLOY_XRAY_CONFIG_HASH" "$PNM_DEPLOY_HY2_CONFIG_HASH" \
        "${PNM_DEPLOY_PRIOR_APPLIED_HASH[xray]-MISSING}" "${PNM_DEPLOY_PRIOR_APPLIED_HASH[hysteria2]-MISSING}" \
        "${PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[xray]-MISSING}" "${PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[hysteria2]-MISSING}" \
        >"$PNM_TX_PATH/deployment.env") || return "$PNM_EXIT_CANTCREAT"
}

# A matching service name is not proof of ownership. Only the established
# legacy failed-install receipts permit replacement of existing host resources.
pnm_deploy_validate_ownership() {
    local root="${PNM_DEPLOY_SANDBOX_ROOT:-/}" relative label mode owner path uid unit load
    root="${root%/}"
    while IFS=' ' read -r relative label mode owner; do
        path="$root$relative"
        pnm_validate_managed_path "$path" || return "$PNM_EXIT_CONFIG"
        [[ -e "$path" || -L "$path" ]] || continue
        if ! declare -F pnm_recovery_has_failed_deployment_record >/dev/null 2>&1 ||
            ! pnm_recovery_has_failed_deployment_record ||
            ! pnm_recovery_resource_has_committed_pnm_receipt "$path" "$label"; then
            pnm_error 'Existing Core resource has no verified PNM ownership receipt; installation stopped.'
            return "$PNM_EXIT_CONFIG"
        fi
        uid="$(id -u "$owner" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
        [[ -f "$path" && ! -L "$path" && "$(stat -c '%a|%u' -- "$path")" == "$mode|$uid" ]] || return "$PNM_EXIT_CONFIG"
    done <<'RESOURCES'
/usr/local/bin/xray xray_binary 755 root
/usr/local/bin/hysteria hysteria_binary 755 root
/usr/local/etc/xray/config.json xray_config 640 root
/etc/hysteria/config.yaml hysteria_config 600 hysteria
/etc/hysteria/tls/server.crt hysteria_cert 644 root
/etc/hysteria/tls/server.key hysteria_key 600 hysteria
/etc/systemd/system/xray.service xray_unit 644 root
/etc/systemd/system/hysteria-server.service hysteria_unit 644 root
RESOURCES
    for unit in xray.service hysteria-server.service; do
        if [[ "$unit" == xray.service ]]; then load="$PNM_DEPLOY_XRAY_LOAD"; else load="$PNM_DEPLOY_HY2_LOAD"; fi
        [[ "$load" == loaded ]] || continue
        path="$root/etc/systemd/system/$unit"
        [[ -f "$path" && ! -L "$path" ]] || {
            pnm_error 'Loaded Core service is outside the verified PNM unit path; installation stopped.'
            return "$PNM_EXIT_CONFIG"
        }
        [[ "$(pnm_systemd_show_value "$unit" FragmentPath)" == "$path" ]] &&
            pnm_recovery_unit_has_no_dropins "$unit" || return "$PNM_EXIT_CONFIG"
    done
}

pnm_deploy_refresh_recovered_applied() {
    local core="$1" config expected confirmed unit record invocation
    local -A old=()
    if [[ "$core" == xray ]]; then
        config="$PNM_XRAY_CONFIG" expected="$PNM_DEPLOY_XRAY_CONFIG_HASH"
        confirmed="$PNM_DEPLOY_XRAY_APPLIED" unit=xray.service
    else
        config="$PNM_HY2_CONFIG" expected="$PNM_DEPLOY_HY2_CONFIG_HASH"
        confirmed="$PNM_DEPLOY_HY2_APPLIED" unit=hysteria-server.service
    fi
    ((confirmed == 1)) || return 0
    [[ "$(pnm_tx_file_sha256 "$config")" == "$expected" ]] || return "$PNM_EXIT_SOFTWARE"
    # Recovery restores the old enable policy, which may legitimately be
    # disabled. Do not apply the fresh-install "must be enabled" policy here.
    if [[ "$core" == xray ]]; then
        pnm_listener_present tcp 443 || return "$PNM_EXIT_SOFTWARE"
    else
        pnm_listener_present udp 8443 || return "$PNM_EXIT_SOFTWARE"
    fi
    record="$PNM_STATE_DIR/cores/$core/applied.env"
    pnm_validate_managed_path "$record" || return "$PNM_EXIT_SOFTWARE"
    [[ -f "$record" && ! -L "$record" &&
        "$(pnm_tx_file_sha256 "$record")" == "${PNM_DEPLOY_PRIOR_APPLIED_HASH[$core]}" &&
        "$(stat -c '%a:%u:%g' -- "$record")" == "${PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[$core]}" ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_config_load "$record" old SCHEMA_VERSION CORE CONFIG_SHA256 SERVICE_INVOCATION_ID || return "$PNM_EXIT_SOFTWARE"
    [[ "${old[SCHEMA_VERSION]-}" == 1 && "${old[CORE]-}" == "$core" && "${old[CONFIG_SHA256]-}" == "$expected" ]] || return "$PNM_EXIT_SOFTWARE"
    invocation="$(pnm_systemd_show_value "$unit" InvocationID)" || return "$PNM_EXIT_SOFTWARE"
    [[ "$invocation" =~ ^[a-fA-F0-9]{32}$ ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_tx_refresh_recovered_applied "$record" "$core" "$expected" "${invocation,,}" \
        "${PNM_DEPLOY_PRIOR_APPLIED_HASH[$core]}" "${PNM_DEPLOY_PRIOR_APPLIED_ATTRIBUTES[$core]}" || return "$PNM_EXIT_SOFTWARE"
    [[ "$(pnm_core_applied_config_status "$core" "$config")" == confirmed ]] || return "$PNM_EXIT_SOFTWARE"
    pnm_tx_journal RECOVERY_APPLIED_REFRESH "core=$core"
}

# One callback owns recovery ordering; component participants never compensate.
pnm_deploy_restore_resources() {
    local unit load current core expected_load active enabled
    ((PNM_DEPLOY_RESOURCES_STARTED == 1)) || return 0
    if ((PNM_DEPLOY_RESOURCES_STARTED == 1)); then
        for unit in xray.service hysteria-server.service; do
            load="$(pnm_systemd_load_state "$unit")" || return "$PNM_EXIT_SOFTWARE"
            if [[ "$load" == loaded ]]; then
                pnm_systemctl stop "$unit" >/dev/null || return "$PNM_EXIT_SOFTWARE"
                pnm_systemctl disable "$unit" >/dev/null || return "$PNM_EXIT_SOFTWARE"
            elif [[ "$load" != not-found ]]; then
                return "$PNM_EXIT_SOFTWARE"
            fi
        done
    fi
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    pnm_systemd_daemon_reload || return "$PNM_EXIT_SOFTWARE"
    pnm_deploy_restore_service_state || return "$PNM_EXIT_SOFTWARE"
    for core in xray hysteria2; do
        if [[ "$core" == xray ]]; then
            unit=xray.service expected_load="$PNM_DEPLOY_XRAY_LOAD"
            active="$PNM_DEPLOY_XRAY_ACTIVE" enabled="$PNM_DEPLOY_XRAY_ENABLED"
        else
            unit=hysteria-server.service expected_load="$PNM_DEPLOY_HY2_LOAD"
            active="$PNM_DEPLOY_HY2_ACTIVE" enabled="$PNM_DEPLOY_HY2_ENABLED"
        fi
        current="$(pnm_systemd_load_state "$unit")" || return "$PNM_EXIT_SOFTWARE"
        [[ "$current" == "$expected_load" ]] || return "$PNM_EXIT_SOFTWARE"
        [[ "$expected_load" != not-found ]] || continue
        [[ "$(pnm_systemd_active_state "$unit")" == "$active" &&
            "$(pnm_systemd_enabled_state "$unit")" == "$enabled" ]] || return "$PNM_EXIT_SOFTWARE"
        if [[ "$active" == active ]]; then
            pnm_deploy_refresh_recovered_applied "$core" || return "$PNM_EXIT_SOFTWARE"
        fi
    done
    if declare -F pnm_service_accounts_rollback >/dev/null 2>&1; then
        pnm_service_accounts_rollback || return "$PNM_EXIT_SOFTWARE"
    fi
    pnm_tx_restore_directories
}

pnm_deploy_abort() {
    local rc="${1:?original exit code required}" recovery_rc=0
    if ((PNM_TX_ACTIVE == 1 && PNM_TX_COMMITTED == 0 && PNM_TX_ROLLED_BACK == 0)); then
        if [[ -e "$PNM_TX_PATH/commit.env" || -L "$PNM_TX_PATH/commit.env" ]]; then
            PNM_TX_RECOVERY_REQUIRED=1
            recovery_rc="$PNM_EXIT_SOFTWARE"
        else
            PNM_TX_STEP_FAILURE_RC="$rc"
            pnm_tx_rollback || recovery_rc="$PNM_EXIT_SOFTWARE"
        fi
    fi
    if ((PNM_TX_RECOVERY_REQUIRED == 1 || recovery_rc != 0)); then
        pnm_error "Deployment failed (original_rc=$rc recovery_rc=$recovery_rc); recovery evidence retained at $PNM_TX_PATH."
        rc="$PNM_EXIT_SOFTWARE"
    elif [[ -n "${PNM_SANDBOX_STAGING:-}" && "$PNM_SANDBOX_STAGING" == "$PNM_TX_PATH/staging" ]]; then
        pnm_sandbox_cleanup_staging || true
    fi
    pnm_tx_close || rc="$PNM_EXIT_SOFTWARE"
    pnm_deploy_close || true
    return "$rc"
}

pnm_deploy_finish() {
    local rc
    pnm_deploy_require_transaction "$PNM_DEPLOY_ID" || return $?
    if pnm_tx_commit; then :; else rc=$?; pnm_deploy_abort "$rc"; return $?; fi
    PNM_DEPLOY_COMMITTED=1
    pnm_deploy_journal COMMIT '' || pnm_warn 'Deployment committed; progress journal could not be completed.'
    if [[ -n "${PNM_SANDBOX_STAGING:-}" && "$PNM_SANDBOX_STAGING" == "$PNM_TX_PATH/staging" ]]; then
        pnm_sandbox_cleanup_staging || pnm_warn 'Deployment committed; private staging cleanup remains pending.'
    fi
    pnm_tx_close || pnm_warn 'Deployment committed; transaction lock cleanup reported an error.'
    pnm_deploy_close || pnm_warn 'Deployment committed; progress cleanup reported an error.'
    return 0
}

pnm_deploy_execute() {
    local rc=0 index unit
    local -a phases=(core-resources xray-lifecycle hysteria-lifecycle post-health)
    local -a functions=("$PNM_DEPLOY_STEP_SANDBOX" "$PNM_DEPLOY_STEP_XRAY" "$PNM_DEPLOY_STEP_HYSTERIA" "$PNM_DEPLOY_STEP_HEALTH")
    pnm_deploy_begin || return $?
    if ((PNM_DRY_RUN == 1)); then
        for unit in "${phases[@]}"; do pnm_deploy_journal PLAN "$unit" || return $?; done
        PNM_DEPLOY_COMMITTED=1
        pnm_deploy_close
        return $?
    fi
    if pnm_tx_begin deployment; then :; else rc=$?; pnm_deploy_close || true; return "$rc"; fi
    pnm_tx_add_rollback pnm_deploy_restore_resources || { pnm_deploy_abort "$PNM_EXIT_SOFTWARE"; return $?; }
    if pnm_deploy_record_baseline; then :; else rc=$?; pnm_deploy_abort "$rc"; return $?; fi
    # Stop prior active processes before publishing replacement runtime files.
    PNM_DEPLOY_RESOURCES_STARTED=1
    for unit in xray.service hysteria-server.service; do
        if [[ "$(pnm_systemd_load_state "$unit")" == loaded ]]; then
            pnm_systemctl stop "$unit" >/dev/null || { pnm_deploy_abort "$PNM_EXIT_SOFTWARE"; return $?; }
        fi
    done
    for ((index=0; index<${#phases[@]}; index+=1)); do
        if pnm_deploy_run_phase "${phases[index]}" "${functions[index]}"; then continue; else rc=$?; fi
        pnm_deploy_journal STOPPED "after=${phases[index]} rc=$rc" || true
        pnm_deploy_abort "$rc"
        return $?
    done
    if pnm_deploy_mark_configured "$PNM_DEPLOY_ID"; then :; else rc=$?; pnm_deploy_abort "$rc"; return $?; fi
    # The controlled gate still has deadline and health checks to run.
    (( ${PNM_APPLY_GATE_ACTIVE:-0} == 0 )) || return 0
    pnm_deploy_finish
}

pnm_deploy_close() {
    local rc=0

    ((PNM_DEPLOY_ACTIVE == 1)) || return 0
    if ((PNM_DEPLOY_COMMITTED == 0)); then
        pnm_deploy_journal ABANDONED 'deployment closed without commit' || rc="$PNM_EXIT_CANTCREAT"
    fi
    PNM_DEPLOY_ACTIVE=0
    PNM_DEPLOY_ID=''
    PNM_DEPLOY_PATH=''
    PNM_DEPLOY_COMMITTED=0
    return "$rc"
}

pnm_deploy_restore_service_state() {
    local rc=0
    local unit active enabled
    for unit in xray.service hysteria-server.service; do
        if [[ "$unit" == xray.service ]]; then
            [[ "${PNM_DEPLOY_XRAY_LOAD:-loaded}" != not-found ]] || continue
            active=$PNM_DEPLOY_XRAY_ACTIVE enabled=$PNM_DEPLOY_XRAY_ENABLED
        else
            [[ "${PNM_DEPLOY_HY2_LOAD:-loaded}" != not-found ]] || continue
            active=$PNM_DEPLOY_HY2_ACTIVE enabled=$PNM_DEPLOY_HY2_ENABLED
        fi
        if [[ "$enabled" == enabled ]]; then
            pnm_systemctl enable "$unit" >/dev/null || rc="$PNM_EXIT_SOFTWARE"
        else
            pnm_systemctl disable "$unit" >/dev/null || rc="$PNM_EXIT_SOFTWARE"
        fi
        if [[ "$active" == active ]]; then
            pnm_systemctl restart "$unit" >/dev/null || rc="$PNM_EXIT_SOFTWARE"
        else
            pnm_systemctl stop "$unit" >/dev/null || rc="$PNM_EXIT_SOFTWARE"
        fi
    done
    return "$rc"
}

pnm_deploy_apply() {
    local rc

    pnm_preflight_collect
    if pnm_preflight_exit_code; then rc=0; else rc=$?; fi
    if ((rc != 0)); then
        pnm_error 'Deployment preflight failed; no host change was made.'
        return "$rc"
    fi
    PNM_DEPLOY_SANDBOX_ROOT=/
    PNM_HOST_APPLY_CONFIRMED=yes
    declare -F pnm_apply_gate_execute >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
    pnm_apply_gate_execute
}
