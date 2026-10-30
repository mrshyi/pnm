#!/usr/bin/env bash

pnm_profile_command() {
    local action="${1:-show}" desired
    (($# == 0)) || shift
    case "$action" in
        -h | --help) pnm_print_help profile ;;
        show)
            (($# == 0)) || return "$PNM_EXIT_USAGE"
            pnm_require_root || return $?
            pnm_with_deployment_read_lock pnm_profile_show
            ;;
        set)
            (($# >= 1 && $# <= 2)) || return "$PNM_EXIT_USAGE"
            desired=$1
            pnm_validate_profile "$desired" || return "$PNM_EXIT_USAGE"
            [[ "${2-}" != --yes ]] || PNM_ASSUME_YES=1
            (($# == 1)) || [[ "$2" == --yes ]] || return "$PNM_EXIT_USAGE"
            ((PNM_DRY_RUN == 0 && PNM_ASSUME_YES == 1)) || {
                pnm_error 'Profile switching requires --yes and does not support --dry-run.'
                return "$PNM_EXIT_USAGE"
            }
            pnm_require_root || return $?
            pnm_core_with_write_lock pnm_profile_set "$desired"
            ;;
        *) pnm_error 'Usage: pnm profile show | set <dual|reality|hy2> --yes'; return "$PNM_EXIT_USAGE" ;;
    esac
}

pnm_profile_show() {
    local core unit active enabled wanted comma=''
    local -A profile_node=()
    pnm_load_node_config profile_node && pnm_validate_node_config profile_node || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.profile.v1","desired":%s,"cores":[' "$(pnm_json_string "${profile_node[PNM_PROFILE]-dual}")"
    else
        printf 'Desired profile: %s\n' "${profile_node[PNM_PROFILE]-dual}"
    fi
    for core in xray hysteria2; do
        unit="$(pnm_core_lifecycle_unit "$core")" || return $?
        active="$(pnm_systemd_active_state "$unit")" || active=unknown
        enabled="$(pnm_systemd_enabled_state "$unit")" || enabled=unknown
        wanted=false
        if pnm_profile_includes "${profile_node[PNM_PROFILE]-dual}" "$core"; then wanted=true; fi
        if [[ "$PNM_OUTPUT_MODE" == json ]]; then
            printf '%s{"core":%s,"desired_enabled":%s,"active":%s,"enabled":%s}' "$comma" \
                "$(pnm_json_string "$core")" "$wanted" "$(pnm_json_string "$active")" "$(pnm_json_string "$enabled")"
            comma=','
        else
            printf '%s: desired_enabled=%s active=%s enabled=%s\n' "$core" "$wanted" "$active" "$enabled"
        fi
    done
    [[ "$PNM_OUTPUT_MODE" != json ]] || printf ']}\n'
}

pnm_profile_validate_core() {
    local core=$1 unit_file expected
    local -A profile_secret=()
    pnm_core_resolve "$core" || return $?
    unit_file="/etc/systemd/system/$PNM_CORE_UNIT"
    pnm_validate_managed_path "$unit_file" || return $?
    [[ -f "$unit_file" && ! -L "$unit_file" && "$(stat -c '%a:%u' -- "$unit_file")" == '644:0' &&
        "$(pnm_systemd_show_value "$PNM_CORE_UNIT" FragmentPath)" == "$unit_file" ]] || return "$PNM_EXIT_CONFIG"
    pnm_recovery_unit_has_no_dropins "$PNM_CORE_UNIT" || return "$PNM_EXIT_CONFIG"
    if [[ "$core" == xray ]]; then expected="$(pnm_render_xray_unit)"; else expected="$(pnm_render_hysteria_unit)"; fi
    [[ "$(<"$unit_file")" == "$expected" ]] || return "$PNM_EXIT_CONFIG"
    [[ -f "$PNM_CORE_BINARY" && ! -L "$PNM_CORE_BINARY" && -x "$PNM_CORE_BINARY" &&
        "$(stat -c '%a:%u' -- "$PNM_CORE_BINARY")" == '755:0' ]] || return "$PNM_EXIT_CONFIG"
    if pnm_profile_includes "$PNM_PROFILE_TARGET" "$core"; then
        if [[ "$core" == xray ]]; then
            pnm_load_reality_secret profile_secret && pnm_validate_reality_secret_config profile_secret &&
                pnm_xray_config_matches_node PNM_PROFILE_NODE profile_secret || return "$PNM_EXIT_CONFIG"
            "$PNM_CORE_BINARY" run -test -config "$PNM_CORE_CONFIG" >/dev/null 2>&1 || return "$PNM_EXIT_CONFIG"
        else
            pnm_load_hysteria_secret profile_secret && pnm_validate_hysteria_secret_config profile_secret &&
                pnm_hysteria_config_validate_candidate "$PNM_CORE_CONFIG" PNM_PROFILE_NODE profile_secret &&
                pnm_tls_validate_pair "${profile_secret[HY2_TLS_CERT_PATH]}" "${profile_secret[HY2_TLS_KEY_PATH]}" &&
                pnm_hysteria_tls_server_name PNM_PROFILE_NODE profile_secret >/dev/null || return "$PNM_EXIT_CONFIG"
        fi
    fi
}

pnm_profile_restore() {
    local core state
    local PNM_CORE_PRIOR_CONFIG_HASH PNM_CORE_PRIOR_APPLIED_HASH PNM_CORE_PRIOR_APPLIED_ATTRIBUTES
    local PNM_LIFECYCLE_UNIT PNM_LIFECYCLE_PRE_ACTIVE PNM_LIFECYCLE_PRE_ENABLED
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    for core in "${PNM_PROFILE_CHANGED[@]}"; do
        pnm_core_resolve "$core" || return $?
        PNM_LIFECYCLE_UNIT=$PNM_CORE_UNIT
        PNM_LIFECYCLE_PRE_ACTIVE=${PNM_PROFILE_ACTIVE[$core]}
        PNM_LIFECYCLE_PRE_ENABLED=${PNM_PROFILE_ENABLED[$core]}
        state="$(pnm_systemd_active_state "$PNM_CORE_UNIT")" || return "$PNM_EXIT_SOFTWARE"
        case "$state" in
            failed | activating | deactivating)
                pnm_systemd_stop_verified "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE" ;;
            active | inactive) ;;
            *) return "$PNM_EXIT_SOFTWARE" ;;
        esac
        pnm_core_lifecycle_restore || return "$PNM_EXIT_SOFTWARE"
        PNM_CORE_PRIOR_CONFIG_HASH=${PNM_PROFILE_CONFIG_HASH[$core]}
        PNM_CORE_PRIOR_APPLIED_HASH=${PNM_PROFILE_APPLIED_HASH[$core]}
        PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=${PNM_PROFILE_APPLIED_ATTRIBUTES[$core]}
        pnm_core_recover_applied || return "$PNM_EXIT_SOFTWARE"
    done
    pnm_tx_restore_directories
}

pnm_profile_wait_listener() {
    local core=$1 unit=$2 pid attempt protocol port
    if [[ "$core" == xray ]]; then
        protocol=tcp port=${PNM_PROFILE_NODE[XRAY_PORT]}
    else
        protocol=udp port=${PNM_PROFILE_NODE[HY2_PORT]}
    fi
    for ((attempt=0; attempt<26; attempt+=1)); do
        [[ "$(pnm_systemd_active_state "$unit")" == active ]] || return "$PNM_EXIT_CONFIG"
        pid="$(pnm_systemd_show_value "$unit" MainPID)" || return "$PNM_EXIT_CONFIG"
        if pnm_listener_owned_by_pid "$protocol" "$port" "$pid" &&
            [[ "$(pnm_systemd_active_state "$unit")" == active && "$(pnm_systemd_show_value "$unit" MainPID)" == "$pid" ]]; then
            return 0
        fi
        if ((attempt<25)); then sleep 0.2 || return "$PNM_EXIT_SOFTWARE"; fi
    done
    return "$PNM_EXIT_CONFIG"
}

pnm_profile_apply() {
    local core wanted_active wanted_enabled
    pnm_tx_prepare_directory /etc/systemd/system/multi-user.target.wants - || return $?
    for core in xray hysteria2; do
        pnm_core_resolve "$core" || return $?
        wanted_active=inactive wanted_enabled=disabled
        if pnm_profile_includes "$PNM_PROFILE_TARGET" "$core"; then wanted_active=active wanted_enabled=enabled; fi
        if [[ "${PNM_PROFILE_ACTIVE[$core]}" != "$wanted_active" || "${PNM_PROFILE_ENABLED[$core]}" != "$wanted_enabled" ]]; then
            PNM_PROFILE_CHANGED+=("$core")
            if [[ "$wanted_active" == active ]]; then
                pnm_systemctl enable "$PNM_CORE_UNIT" && pnm_systemctl start "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
                pnm_profile_wait_listener "$core" "$PNM_CORE_UNIT" || return "$PNM_EXIT_CONFIG"
                pnm_check_deploy_core_health "$core" || return "$PNM_EXIT_CONFIG"
                pnm_core_record_applied_config "$core" "$PNM_CORE_CONFIG" "$PNM_TX_PATH" || return $?
            else
                pnm_systemd_stop_verified "$PNM_CORE_UNIT" && pnm_systemctl disable "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
            fi
        fi
        [[ "$(pnm_systemd_active_state "$PNM_CORE_UNIT")" == "$wanted_active" &&
            "$(pnm_systemd_enabled_state "$PNM_CORE_UNIT")" == "$wanted_enabled" ]] || return "$PNM_EXIT_CONFIG"
        if [[ "$wanted_active" == active ]]; then pnm_check_deploy_core_health "$core" || return "$PNM_EXIT_CONFIG"; fi
    done
    pnm_tx_write_file "$PNM_TX_PATH/profile-node.conf" "$PNM_CONFIG_DIR/node.conf" node_config 0600
}

pnm_profile_set() {
    local PNM_PROFILE_TARGET=$1 core rc key
    local PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
    local -A PNM_PROFILE_NODE=() PNM_PROFILE_ACTIVE=() PNM_PROFILE_ENABLED=()
    local -A PNM_PROFILE_CONFIG_HASH=() PNM_PROFILE_APPLIED_HASH=() PNM_PROFILE_APPLIED_ATTRIBUTES=()
    local -a PNM_PROFILE_CHANGED=()
    pnm_platform_supported && pnm_systemd_available || return "$PNM_EXIT_CONFIG"
    pnm_load_node_config PNM_PROFILE_NODE && pnm_validate_node_config PNM_PROFILE_NODE || return "$PNM_EXIT_CONFIG"
    [[ "$(stat -c '%a:%u' -- "$PNM_CONFIG_DIR/node.conf")" == "600:$EUID" ]] || return "$PNM_EXIT_NOPERM"
    [[ "${PNM_PROFILE_NODE[PNM_CONFIGURED]}" == yes ]] || { pnm_error 'Install both Cores before selecting a profile.'; return "$PNM_EXIT_CONFIG"; }
    for core in xray hysteria2; do
        pnm_profile_validate_core "$core" || return $?
        pnm_core_lifecycle_snapshot "$core" || return $?
        PNM_PROFILE_ACTIVE[$core]=$PNM_LIFECYCLE_PRE_ACTIVE
        PNM_PROFILE_ENABLED[$core]=$PNM_LIFECYCLE_PRE_ENABLED
        PNM_CORE_PRIOR_CONFIG_HASH='' PNM_CORE_PRIOR_APPLIED_HASH='' PNM_CORE_PRIOR_APPLIED_ATTRIBUTES=''
        pnm_core_capture_applied || return $?
        if [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active && -z "$PNM_CORE_PRIOR_CONFIG_HASH" ]]; then
            pnm_error 'Active Core has no confirmed applied configuration; apply its configuration before switching profiles.'
            return "$PNM_EXIT_CONFIG"
        fi
        PNM_PROFILE_CONFIG_HASH[$core]=$PNM_CORE_PRIOR_CONFIG_HASH
        PNM_PROFILE_APPLIED_HASH[$core]=$PNM_CORE_PRIOR_APPLIED_HASH
        PNM_PROFILE_APPLIED_ATTRIBUTES[$core]=$PNM_CORE_PRIOR_APPLIED_ATTRIBUTES
    done
    pnm_tx_begin core-profile || return $?
    pnm_tx_add_rollback pnm_profile_restore || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    # Keep both service baselines in the existing protected transaction evidence.
    for core in xray hysteria2; do
        printf '%s\t%s\t%s\n' "$core" "${PNM_PROFILE_ACTIVE[$core]}" "${PNM_PROFILE_ENABLED[$core]}"
    done >"$PNM_TX_PATH/profile-state.tsv" || { pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
    PNM_PROFILE_NODE[PNM_PROFILE]=$PNM_PROFILE_TARGET
    for key in "${!PNM_PROFILE_NODE[@]}"; do
        printf '%s=%s\n' "$key" "${PNM_PROFILE_NODE[$key]}"
    done >"$PNM_TX_PATH/profile-node.conf" || { pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
    chmod 0600 -- "$PNM_TX_PATH/profile-state.tsv" "$PNM_TX_PATH/profile-node.conf" || { pnm_tx_close; return "$PNM_EXIT_NOPERM"; }
    if pnm_tx_run profile pnm_profile_apply; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_commit; then :; else rc=$?; pnm_tx_rollback || rc="$PNM_EXIT_SOFTWARE"; pnm_tx_close; return "$rc"; fi
    pnm_tx_close || return $?
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then pnm_profile_show; else pnm_success "Profile set to $PNM_PROFILE_TARGET; Core files and credentials retained."; fi
}
