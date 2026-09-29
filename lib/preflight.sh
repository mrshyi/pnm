#!/usr/bin/env bash

declare -ag PNM_PREFLIGHT_IDS=()
declare -ag PNM_PREFLIGHT_STATUSES=()
declare -ag PNM_PREFLIGHT_SUMMARIES=()
declare -ag PNM_PREFLIGHT_DETAILS=()
declare -Ag PNM_PREFLIGHT_NODE_CONFIG=()
declare -Ag PNM_PREFLIGHT_VERSIONS_CONFIG=()

PNM_PREFLIGHT_FAIL_COUNT=0
PNM_PREFLIGHT_WARN_COUNT=0
PNM_PREFLIGHT_UNKNOWN_COUNT=0

pnm_preflight_reset() {
    PNM_PREFLIGHT_IDS=()
    PNM_PREFLIGHT_STATUSES=()
    PNM_PREFLIGHT_SUMMARIES=()
    PNM_PREFLIGHT_DETAILS=()
    PNM_PREFLIGHT_NODE_CONFIG=()
    PNM_PREFLIGHT_VERSIONS_CONFIG=()
    PNM_PREFLIGHT_FAIL_COUNT=0
    PNM_PREFLIGHT_WARN_COUNT=0
    PNM_PREFLIGHT_UNKNOWN_COUNT=0
}

pnm_preflight_add() {
    local id="${1:?preflight id required}"
    local status="${2:?preflight status required}"
    local summary="${3:?preflight summary required}"
    local detail="${4-}"

    case "$status" in
        OK) ;;
        WARN) ((PNM_PREFLIGHT_WARN_COUNT += 1)) ;;
        FAIL) ((PNM_PREFLIGHT_FAIL_COUNT += 1)) ;;
        UNKNOWN) ((PNM_PREFLIGHT_UNKNOWN_COUNT += 1)) ;;
        *)
            status='UNKNOWN'
            detail='invalid internal preflight status'
            ((PNM_PREFLIGHT_UNKNOWN_COUNT += 1))
            ;;
    esac
    PNM_PREFLIGHT_IDS+=("$id")
    PNM_PREFLIGHT_STATUSES+=("$status")
    PNM_PREFLIGHT_SUMMARIES+=("$(pnm_one_line "$summary")")
    PNM_PREFLIGHT_DETAILS+=("$(pnm_one_line "$detail")")
}

pnm_preflight_platform() {
    if pnm_platform_supported; then
        pnm_preflight_add platform OK 'Supported installation platform' "$(pnm_platform_summary)"
    else
        pnm_preflight_add platform FAIL 'Unsupported installation platform' "expected $(pnm_platform_support_policy); got $(pnm_platform_summary)"
    fi
}

pnm_preflight_runtime() {
    local -a missing=()
    local command_name

    if pnm_systemd_available; then
        pnm_preflight_add systemd OK 'systemd is available' 'systemctl and runtime detected'
    else
        pnm_preflight_add systemd FAIL 'systemd is unavailable' 'PNM installation requires systemd'
    fi

    for command_name in apt-get curl flock install sha256sum ss; do
        pnm_command_exists "$command_name" || missing+=("$command_name")
    done
    if ((${#missing[@]} == 0)); then
        pnm_preflight_add tools OK 'Required local tools are available' 'apt-get, curl, flock, install, sha256sum, ss'
    else
        pnm_preflight_add tools FAIL 'Required local tools are unavailable' "missing: ${missing[*]}"
    fi
}

pnm_preflight_configuration() {
    local rc

    if pnm_load_node_config PNM_PREFLIGHT_NODE_CONFIG; then
        rc=0
    else
        rc=$?
    fi
    if ((rc != 0)) || ! pnm_validate_node_config PNM_PREFLIGHT_NODE_CONFIG; then
        pnm_preflight_add node_config FAIL 'Node desired state is missing or invalid' "$PNM_CONFIG_DIR/node.conf"
    elif [[ "${PNM_PREFLIGHT_NODE_CONFIG[PNM_CONFIGURED]}" == 'yes' ]]; then
        pnm_preflight_add node_config FAIL 'Node is already marked configured' 'install refuses to overwrite an existing managed node'
    else
        pnm_preflight_add node_config OK 'Node desired state is valid and uncommitted' "$PNM_CONFIG_DIR/node.conf"
    fi

    if pnm_load_versions_config PNM_PREFLIGHT_VERSIONS_CONFIG; then
        rc=0
    else
        rc=$?
    fi
    if ((rc != 0)) || ! pnm_validate_versions_config PNM_PREFLIGHT_VERSIONS_CONFIG; then
        pnm_preflight_add versions_config FAIL 'Approved core version manifest is missing or invalid' "$PNM_CONFIG_DIR/versions.conf"
    else
        pnm_preflight_add versions_config OK 'Approved core version manifest is valid' "Xray ${PNM_PREFLIGHT_VERSIONS_CONFIG[XRAY_VERSION]}; Hysteria2 ${PNM_PREFLIGHT_VERSIONS_CONFIG[HY2_VERSION]}"
    fi
}

pnm_preflight_port() {
    local protocol="${1:?protocol required}"
    local port="${2:?port required}"
    local rc

    if pnm_listener_present "$protocol" "$port"; then
        rc=0
    else
        rc=$?
    fi
    case "$rc" in
        0) pnm_preflight_add "port_${protocol}_${port}" FAIL "Required ${protocol^^}/${port} is already in use" 'PNM will not replace an unknown listener' ;;
        1) pnm_preflight_add "port_${protocol}_${port}" OK "Required ${protocol^^}/${port} is free" 'no listener detected' ;;
        *) pnm_preflight_add "port_${protocol}_${port}" UNKNOWN "Required ${protocol^^}/${port} cannot be verified" 'ss is unavailable or returned an unexpected result' ;;
    esac
}

pnm_preflight_collect() {
    pnm_preflight_reset
    pnm_preflight_platform
    pnm_preflight_runtime
    pnm_preflight_configuration
    pnm_preflight_port tcp 443
    pnm_preflight_port udp 8443
}

pnm_preflight_overall() {
    if ((PNM_PREFLIGHT_FAIL_COUNT > 0)); then
        printf 'FAIL\n'
    elif ((PNM_PREFLIGHT_WARN_COUNT > 0 || PNM_PREFLIGHT_UNKNOWN_COUNT > 0)); then
        printf 'WARN\n'
    else
        printf 'OK\n'
    fi
}

pnm_preflight_exit_code() {
    if ((PNM_PREFLIGHT_FAIL_COUNT > 0)); then
        return "$PNM_EXIT_FAIL"
    elif ((PNM_PREFLIGHT_WARN_COUNT > 0 || PNM_PREFLIGHT_UNKNOWN_COUNT > 0)); then
        return "$PNM_EXIT_WARN"
    fi
    return "$PNM_EXIT_OK"
}

pnm_preflight_render_text() {
    local index status color='' reset=''

    ((PNM_QUIET == 1)) && return 0
    printf 'Proxy Node Manager installation preflight\n\n'
    for index in "${!PNM_PREFLIGHT_IDS[@]}"; do
        status="${PNM_PREFLIGHT_STATUSES[$index]}"
        case "$status" in
            OK) color="$PNM_COLOR_GREEN" ;;
            WARN | UNKNOWN) color="$PNM_COLOR_YELLOW" ;;
            FAIL) color="$PNM_COLOR_RED" ;;
        esac
        [[ -n "$color" ]] && reset="$PNM_COLOR_RESET"
        printf '%s[%s]%s %-22s %s' "$color" "$status" "$reset" "${PNM_PREFLIGHT_IDS[$index]}" "${PNM_PREFLIGHT_SUMMARIES[$index]}"
        [[ -n "${PNM_PREFLIGHT_DETAILS[$index]}" ]] && printf ' — %s' "${PNM_PREFLIGHT_DETAILS[$index]}"
        printf '\n'
        color=''
        reset=''
    done
    printf '\nOverall: %s (fail=%d warn=%d unknown=%d)\n' \
        "$(pnm_preflight_overall)" "$PNM_PREFLIGHT_FAIL_COUNT" "$PNM_PREFLIGHT_WARN_COUNT" "$PNM_PREFLIGHT_UNKNOWN_COUNT"
}

pnm_preflight_render_json_object() {
    local index comma=''

    printf '{'
    printf '"overall":%s,' "$(pnm_json_string "$(pnm_preflight_overall)")"
    printf '"counts":{"fail":%d,"warn":%d,"unknown":%d},' \
        "$PNM_PREFLIGHT_FAIL_COUNT" "$PNM_PREFLIGHT_WARN_COUNT" "$PNM_PREFLIGHT_UNKNOWN_COUNT"
    printf '"checks":['
    for index in "${!PNM_PREFLIGHT_IDS[@]}"; do
        printf '%s{' "$comma"
        printf '"id":%s,' "$(pnm_json_string "${PNM_PREFLIGHT_IDS[$index]}")"
        printf '"status":%s,' "$(pnm_json_string "${PNM_PREFLIGHT_STATUSES[$index]}")"
        printf '"summary":%s,' "$(pnm_json_string "${PNM_PREFLIGHT_SUMMARIES[$index]}")"
        printf '"detail":%s' "$(pnm_json_string "${PNM_PREFLIGHT_DETAILS[$index]}")"
        printf '}'
        comma=','
    done
    printf ']}'
}

pnm_preflight_render_json() {
    printf '{"schema":"pnm.preflight.v1","generated_at":%s,"preflight":' "$(pnm_json_string "$(pnm_now_utc)")"
    pnm_preflight_render_json_object
    printf '}\n'
}

pnm_preflight() {
    local rc

    pnm_init_colors
    pnm_preflight_collect
    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_preflight_render_json
    else
        pnm_preflight_render_text
    fi
    if pnm_preflight_exit_code; then rc=0; else rc=$?; fi
    return "$rc"
}
