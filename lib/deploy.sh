#!/usr/bin/env bash

PNM_DEPLOY_ID=''
PNM_DEPLOY_PATH=''
PNM_DEPLOY_ACTIVE=0
PNM_DEPLOY_COMMITTED=0
PNM_DEPLOY_JOURNAL_ERROR=0
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
    local deployments_dir owner_mode

    ((PNM_DEPLOY_ACTIVE == 0)) || return "$PNM_EXIT_SOFTWARE"
    PNM_DEPLOY_ID="$(pnm_deploy_new_id)"
    PNM_DEPLOY_COMMITTED=0
    PNM_DEPLOY_JOURNAL_ERROR=0
    if ((PNM_DRY_RUN == 1)); then
        PNM_DEPLOY_PATH="dry-run:$PNM_DEPLOY_ID"
        PNM_DEPLOY_ACTIVE=1
        return 0
    fi
    pnm_require_root || return $?
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
        pnm_host_apply_resources_step
        return $?
    fi
    pnm_sandbox_install "$PNM_DEPLOY_SANDBOX_ROOT"
}

pnm_core_lifecycle_apply_xray_step() {
    pnm_core_lifecycle_apply xray
}

pnm_core_lifecycle_apply_hysteria_step() {
    pnm_core_lifecycle_apply hysteria2
}

pnm_deploy_health_step() {
    pnm_systemd_unit_healthy xray.service || return "$PNM_EXIT_CONFIG"
    pnm_systemd_unit_healthy hysteria-server.service || return "$PNM_EXIT_CONFIG"
}

pnm_deploy_mark_configured() {
    local temp_dir staged rc
    local -A node=()

    pnm_load_node_config node || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config node || return "$PNM_EXIT_CONFIG"
    [[ "${node[PNM_CONFIGURED]}" == no ]] || return "$PNM_EXIT_CONFIG"
    temp_dir="$(pnm_make_temp_dir)" || return $?
    staged="$temp_dir/node.conf"
    if ! printf 'SCHEMA_VERSION=%s\nNODE_REGION=%s\nNODE_ADDRESS=%s\nTIMEZONE=%s\nPNM_CONFIGURED=yes\nXRAY_PORT=%s\nXRAY_SERVER_NAME=%s\nXRAY_TARGET=%s\nHY2_PORT=%s\nHY2_TLS_MODE=%s\n' \
        "${node[SCHEMA_VERSION]}" "${node[NODE_REGION]}" "${node[NODE_ADDRESS]-}" "${node[TIMEZONE]}" "${node[XRAY_PORT]}" \
        "${node[XRAY_SERVER_NAME]}" "${node[XRAY_TARGET]}" "${node[HY2_PORT]}" "${node[HY2_TLS_MODE]}" >"$staged"; then
        return "$PNM_EXIT_CANTCREAT"
    fi
    pnm_tx_begin install-state || return $?
    pnm_tx_add_rollback pnm_tx_restore_written_files || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run mark_configured pnm_tx_write_file "$staged" "$PNM_CONFIG_DIR/node.conf" node_config 0600; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    pnm_tx_commit || { rc=$?; pnm_tx_close; return "$rc"; }
    pnm_tx_close
}
pnm_deploy_execute() {
    local rc phase index
    local -a phases=(
        'core-resources'
        'xray-lifecycle'
        'hysteria-lifecycle'
        'post-health'
    )
    local -a functions=(
        "$PNM_DEPLOY_STEP_SANDBOX"
        "$PNM_DEPLOY_STEP_XRAY"
        "$PNM_DEPLOY_STEP_HYSTERIA"
        "$PNM_DEPLOY_STEP_HEALTH"
    )
    pnm_deploy_begin || return $?
    if ((PNM_DRY_RUN == 1)); then
        for phase in "${phases[@]}"; do
            pnm_deploy_journal PLAN "$phase"
        done
        PNM_DEPLOY_COMMITTED=1
        pnm_deploy_close
        return 0
    fi
    for ((index = 0; index < ${#phases[@]}; index += 1)); do
        if pnm_deploy_run_phase "${phases[$index]}" "${functions[$index]}"; then
            continue
        else
            phase=$?
        fi
        if ((PNM_DEPLOY_JOURNAL_ERROR == 1)); then
            pnm_deploy_close || true
            return "$phase"
        fi
        pnm_deploy_journal STOPPED "after=${phases[$index]} rc=$phase" || phase="$PNM_EXIT_CANTCREAT"
        pnm_deploy_close || true
        return "$phase"
    done
    if pnm_deploy_mark_configured; then :; else
        phase=$?
        pnm_deploy_journal STOPPED "after=configuration-commit rc=$phase" || phase="$PNM_EXIT_CANTCREAT"
        pnm_deploy_close || true
        return "$phase"
    fi
    PNM_DEPLOY_COMMITTED=1
    if ! pnm_deploy_journal COMMIT ''; then
        PNM_DEPLOY_COMMITTED=0
        pnm_deploy_close || true
        return "$PNM_EXIT_CANTCREAT"
    fi
    pnm_deploy_close
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
