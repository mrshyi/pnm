#!/usr/bin/env bash

declare -ag PNM_CHECK_IDS=()
declare -ag PNM_CHECK_STATUSES=()
declare -ag PNM_CHECK_SUMMARIES=()
declare -ag PNM_CHECK_DETAILS=()
declare -Ag PNM_NODE_CONFIG=()

PNM_CHECK_FAIL_COUNT=0
PNM_CHECK_WARN_COUNT=0
PNM_CHECK_UNKNOWN_COUNT=0
PNM_CHECK_CONFIGURED=0

pnm_check_reset() {
    PNM_CHECK_IDS=()
    PNM_CHECK_STATUSES=()
    PNM_CHECK_SUMMARIES=()
    PNM_CHECK_DETAILS=()
    PNM_NODE_CONFIG=()
    PNM_CHECK_FAIL_COUNT=0
    PNM_CHECK_WARN_COUNT=0
    PNM_CHECK_UNKNOWN_COUNT=0
    PNM_CHECK_CONFIGURED=0
}

pnm_check_add() {
    local id="${1:?check id required}"
    local status="${2:?check status required}"
    local summary="${3:?check summary required}"
    local detail="${4-}"

    case "$status" in
        OK) ;;
        WARN) ((PNM_CHECK_WARN_COUNT += 1)) ;;
        FAIL) ((PNM_CHECK_FAIL_COUNT += 1)) ;;
        UNKNOWN) ((PNM_CHECK_UNKNOWN_COUNT += 1)) ;;
        *)
            status='UNKNOWN'
            detail="invalid internal status: $2"
            ((PNM_CHECK_UNKNOWN_COUNT += 1))
            ;;
    esac

    PNM_CHECK_IDS+=("$id")
    PNM_CHECK_STATUSES+=("$status")
    PNM_CHECK_SUMMARIES+=("$(pnm_one_line "$summary")")
    PNM_CHECK_DETAILS+=("$(pnm_one_line "$detail")")
}

pnm_check_configuration() {
    local rc

    if [[ ! -e "$PNM_CONFIG_DIR/node.conf" ]]; then
        pnm_check_add configuration WARN 'PNM is not configured' "$PNM_CONFIG_DIR/node.conf is absent"
        return 0
    fi

    if pnm_load_node_config PNM_NODE_CONFIG; then
        rc=0
    else
        rc=$?
    fi
    if ((rc != 0)); then
        pnm_check_add configuration FAIL 'PNM node configuration is invalid' "parser exit $rc"
        return 0
    fi

    if ! pnm_validate_node_config PNM_NODE_CONFIG; then
        pnm_check_add configuration FAIL 'PNM node configuration values are invalid' 'schema, types, ports, names, target, or TLS mode failed validation'
        return 0
    fi
    if [[ "${PNM_NODE_CONFIG[PNM_CONFIGURED]}" != 'yes' ]]; then
        pnm_check_add configuration WARN 'PNM configuration is not committed' 'PNM_CONFIGURED is not yes'
        return 0
    fi

    if ! pnm_validate_port "${PNM_NODE_CONFIG[XRAY_PORT]-}" || [[ "${PNM_NODE_CONFIG[XRAY_PORT]}" != '443' ]]; then
        pnm_check_add configuration FAIL 'Invalid Xray port in desired state' 'expected TCP/443'
        return 0
    fi
    if ! pnm_validate_port "${PNM_NODE_CONFIG[HY2_PORT]-}" || [[ "${PNM_NODE_CONFIG[HY2_PORT]}" != '8443' ]]; then
        pnm_check_add configuration FAIL 'Invalid Hysteria2 port in desired state' 'expected UDP/8443'
        return 0
    fi

    PNM_CHECK_CONFIGURED=1
    pnm_check_add configuration OK 'PNM desired state is configured' 'schema 1'
}

pnm_check_platform() {
    local summary

    summary="$(pnm_platform_summary)"
    if pnm_platform_supported; then
        pnm_check_add platform OK 'Supported platform' "$summary"
    else
        pnm_check_add platform FAIL 'Unsupported platform' "expected Debian 13 amd64; got $summary"
    fi
}

pnm_check_systemd_runtime() {
    if pnm_systemd_available; then
        pnm_check_add systemd OK 'systemd is available' 'systemctl and runtime detected'
    else
        pnm_check_add systemd FAIL 'systemd is unavailable' 'PNM MVP requires systemd'
    fi
}

pnm_check_time_sync() {
    local state active enabled synced

    state="$(pnm_service_state_line systemd-timesyncd.service)"
    IFS='|' read -r _ active enabled _ <<<"$state"
    synced="$(pnm_timedatectl_synchronized 2>/dev/null || printf 'unknown')"

    if [[ "$active" == 'active' && "$enabled" == 'enabled' && "$synced" == 'yes' ]]; then
        pnm_check_add time_sync OK 'Clock synchronization is healthy' 'timesyncd active/enabled; synchronized yes'
    elif [[ "$active" == 'unknown' || "$enabled" == 'unknown' || "$synced" == 'unknown' ]]; then
        pnm_check_add time_sync UNKNOWN 'Clock synchronization cannot be fully determined' "active=$active enabled=$enabled synchronized=$synced"
    else
        pnm_check_add time_sync FAIL 'Clock synchronization is not healthy' "active=$active enabled=$enabled synchronized=$synced"
    fi
}

pnm_check_file_metadata() {
    local id="${1:?check id required}"
    local path="${2:?path required}"
    local expected_mode="${3:?mode required}"
    local expected_user="${4:?user required}"
    local expected_group="${5:?group required}"
    local metadata mode user group

    if [[ ! -e "$path" ]]; then
        if ((PNM_CHECK_CONFIGURED == 1)); then
            pnm_check_add "$id" FAIL 'Required file is missing' "$path"
        else
            pnm_check_add "$id" WARN 'Managed file is not present' "$path; node not configured"
        fi
        return 0
    fi

    if ! metadata="$(stat -c '%a|%U|%G' -- "$path" 2>/dev/null)"; then
        pnm_check_add "$id" UNKNOWN 'File metadata cannot be read' "$path"
        return 0
    fi
    IFS='|' read -r mode user group <<<"$metadata"
    if [[ "$mode" == "$expected_mode" && "$user" == "$expected_user" && "$group" == "$expected_group" ]]; then
        pnm_check_add "$id" OK 'File permissions match policy' "$path $mode $user:$group"
    else
        pnm_check_add "$id" FAIL 'File permissions do not match policy' "$path got $mode $user:$group; expected $expected_mode $expected_user:$expected_group"
    fi
}

pnm_check_xray() {
    local state active enabled version test_output
    local severity='FAIL'

    ((PNM_CHECK_CONFIGURED == 0)) && severity='WARN'
    version="$(pnm_binary_version xray xray 2>/dev/null || true)"
    state="$(pnm_service_state_line xray.service)"
    IFS='|' read -r _ active enabled _ <<<"$state"

    if [[ -z "$version" ]]; then
        pnm_check_add xray "$severity" 'Xray is not installed' 'xray binary not found'
        return 0
    fi
    if [[ ! -r "$PNM_XRAY_CONFIG" ]]; then
        pnm_check_add xray "$severity" 'Xray configuration is missing or unreadable' "$PNM_XRAY_CONFIG"
        return 0
    fi
    if ! pnm_capture test_output xray run -test -config "$PNM_XRAY_CONFIG"; then
        pnm_check_add xray FAIL 'Xray configuration test failed' 'xray run -test returned non-zero'
        return 0
    fi
    if [[ "$active" != 'active' || "$enabled" != 'enabled' ]]; then
        pnm_check_add xray "$severity" 'Xray service is not active and enabled' "active=$active enabled=$enabled"
        return 0
    fi
    if ! pnm_listener_present tcp 443; then
        pnm_check_add xray "$severity" 'Xray TCP listener is absent' 'expected TCP/443'
        return 0
    fi
    pnm_check_add xray OK 'Xray local checks passed' "$version; config valid; TCP/443 listening"
}

pnm_check_hysteria() {
    local state active enabled version
    local severity='FAIL'

    ((PNM_CHECK_CONFIGURED == 0)) && severity='WARN'
    version="$(pnm_binary_version hysteria hysteria 2>/dev/null || true)"
    state="$(pnm_service_state_line hysteria-server.service)"
    IFS='|' read -r _ active enabled _ <<<"$state"

    if [[ -z "$version" ]]; then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 is not installed' 'hysteria binary not found'
        return 0
    fi
    if [[ ! -r "$PNM_HY2_CONFIG" ]]; then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 configuration is missing or unreadable' "$PNM_HY2_CONFIG"
        return 0
    fi
    if [[ "$active" != 'active' || "$enabled" != 'enabled' ]]; then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 service is not active and enabled' "active=$active enabled=$enabled"
        return 0
    fi
    if ! pnm_listener_present udp 8443; then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 UDP listener is absent' 'expected UDP/8443'
        return 0
    fi
    pnm_check_add hysteria2 OK 'Hysteria2 local checks passed' "$version; UDP/8443 listening; external QUIC test still required"
}

pnm_check_core_failed_units() {
    local output line unit
    local -a failed=()

    if ! output="$(pnm_systemd_failed_units 2>/dev/null)"; then
        pnm_check_add failed_core_units UNKNOWN 'Core unit failures cannot be queried' ''
        return 0
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        unit="${line%% *}"
        case "$unit" in
            xray.service | hysteria-server.service) failed+=("$unit") ;;
        esac
    done <<<"$output"
    if ((${#failed[@]} > 0)); then
        pnm_check_add failed_core_units FAIL 'A proxy Core unit is failed' "${failed[*]}"
    else
        pnm_check_add failed_core_units OK 'No failed proxy Core units' ''
    fi
}

pnm_check_updates() {
    local count

    if ! count="$(pnm_apt_simulated_upgrades 2>/dev/null)"; then
        pnm_check_add updates UNKNOWN 'Available package updates cannot be determined' 'apt simulation unavailable'
    elif ((count > 0)); then
        pnm_check_add updates WARN 'Package updates are available' "$count package(s)"
    else
        pnm_check_add updates OK 'No package upgrades are currently pending' ''
    fi
}

pnm_check_reboot_required() {
    if [[ -e /run/reboot-required || -e /var/run/reboot-required ]]; then
        pnm_check_add reboot WARN 'A reboot is required' 'reboot-required marker present'
    else
        pnm_check_add reboot OK 'No reboot-required marker is present' ''
    fi
}

pnm_check_collect() {
    pnm_check_reset
    pnm_check_configuration
    pnm_check_platform
    pnm_check_systemd_runtime
    pnm_check_xray
    pnm_check_hysteria
    pnm_check_file_metadata xray_permissions "$PNM_XRAY_CONFIG" 640 root xray
    pnm_check_file_metadata hysteria_permissions "$PNM_HY2_CONFIG" 600 hysteria hysteria
    pnm_check_file_metadata secret_directory "$PNM_CONFIG_DIR/secrets" 700 root root
    pnm_check_core_failed_units
}

pnm_check_overall() {
    if ((PNM_CHECK_FAIL_COUNT > 0)); then
        printf 'FAIL\n'
    elif ((PNM_CHECK_WARN_COUNT > 0 || PNM_CHECK_UNKNOWN_COUNT > 0)); then
        printf 'WARN\n'
    else
        printf 'OK\n'
    fi
}

pnm_check_exit_code() {
    if ((PNM_CHECK_FAIL_COUNT > 0)); then
        return "$PNM_EXIT_FAIL"
    elif ((PNM_CHECK_WARN_COUNT > 0 || PNM_CHECK_UNKNOWN_COUNT > 0)); then
        return "$PNM_EXIT_WARN"
    fi
    return "$PNM_EXIT_OK"
}

pnm_check_render_text() {
    local index status color reset

    ((PNM_QUIET == 1)) && return 0
    printf 'Proxy Node Manager check\n\n'
    for index in "${!PNM_CHECK_IDS[@]}"; do
        status="${PNM_CHECK_STATUSES[$index]}"
        color=''
        reset=''
        case "$status" in
            OK) color="$PNM_COLOR_GREEN" ;;
            WARN | UNKNOWN) color="$PNM_COLOR_YELLOW" ;;
            FAIL) color="$PNM_COLOR_RED" ;;
        esac
        [[ -n "$color" ]] && reset="$PNM_COLOR_RESET"
        printf '%s[%s]%s %-22s %s' "$color" "$status" "$reset" "${PNM_CHECK_IDS[$index]}" "${PNM_CHECK_SUMMARIES[$index]}"
        [[ -n "${PNM_CHECK_DETAILS[$index]}" ]] && printf ' — %s' "${PNM_CHECK_DETAILS[$index]}"
        printf '\n'
    done
    printf '\nOverall: %s (fail=%d warn=%d unknown=%d)\n' \
        "$(pnm_check_overall)" "$PNM_CHECK_FAIL_COUNT" "$PNM_CHECK_WARN_COUNT" "$PNM_CHECK_UNKNOWN_COUNT"
}

pnm_check_render_json() {
    local index comma=''

    printf '{'
    printf '"schema":"pnm.check.v1",'
    printf '"generated_at":%s,' "$(pnm_json_string "$(pnm_now_utc)")"
    printf '"overall":%s,' "$(pnm_json_string "$(pnm_check_overall)")"
    printf '"counts":{"fail":%d,"warn":%d,"unknown":%d},' \
        "$PNM_CHECK_FAIL_COUNT" "$PNM_CHECK_WARN_COUNT" "$PNM_CHECK_UNKNOWN_COUNT"
    printf '"checks":['
    for index in "${!PNM_CHECK_IDS[@]}"; do
        printf '%s{' "$comma"
        printf '"id":%s,' "$(pnm_json_string "${PNM_CHECK_IDS[$index]}")"
        printf '"status":%s,' "$(pnm_json_string "${PNM_CHECK_STATUSES[$index]}")"
        printf '"summary":%s,' "$(pnm_json_string "${PNM_CHECK_SUMMARIES[$index]}")"
        printf '"detail":%s' "$(pnm_json_string "${PNM_CHECK_DETAILS[$index]}")"
        printf '}'
        comma=','
    done
    printf ']}'
    printf '\n'
}

pnm_check() {
    local rc

    pnm_init_colors
    pnm_check_collect
    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_check_render_json
    else
        pnm_check_render_text
    fi

    if pnm_check_exit_code; then
        rc=0
    else
        rc=$?
    fi
    return "$rc"
}
