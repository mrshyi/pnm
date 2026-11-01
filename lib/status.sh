#!/usr/bin/env bash

declare -ag PNM_STATUS_SERVICE_LABELS=()
declare -ag PNM_STATUS_SERVICE_UNITS=()
declare -ag PNM_STATUS_SERVICE_LOAD=()
declare -ag PNM_STATUS_SERVICE_ACTIVE=()
declare -ag PNM_STATUS_SERVICE_ENABLED=()
declare -ag PNM_STATUS_SERVICE_SUB=()

PNM_STATUS_XRAY_VERSION='not-installed'
PNM_STATUS_HY2_VERSION='not-installed'
PNM_STATUS_XRAY_LISTENER='unknown'
PNM_STATUS_HY2_LISTENER='unknown'
PNM_STATUS_PROFILE=unknown
PNM_STATUS_XRAY_PORT=''
PNM_STATUS_HY2_PORT=''
PNM_STATUS_XRAY_DESIRED=null
PNM_STATUS_HY2_DESIRED=null

pnm_status_reset() {
    PNM_STATUS_SERVICE_LABELS=()
    PNM_STATUS_SERVICE_UNITS=()
    PNM_STATUS_SERVICE_LOAD=()
    PNM_STATUS_SERVICE_ACTIVE=()
    PNM_STATUS_SERVICE_ENABLED=()
    PNM_STATUS_SERVICE_SUB=()
    PNM_STATUS_XRAY_VERSION='not-installed'
    PNM_STATUS_HY2_VERSION='not-installed'
    PNM_STATUS_XRAY_LISTENER='unknown'
    PNM_STATUS_HY2_LISTENER='unknown'
    PNM_STATUS_PROFILE=unknown
    PNM_STATUS_XRAY_PORT=''
    PNM_STATUS_HY2_PORT=''
    PNM_STATUS_XRAY_DESIRED=null
    PNM_STATUS_HY2_DESIRED=null
}

pnm_status_collect_service() {
    local label="${1:?service label required}"
    local unit="${2:?service unit required}"
    local state load active enabled sub

    state="$(pnm_service_state_line "$unit")"
    IFS='|' read -r load active enabled sub <<<"$state"

    PNM_STATUS_SERVICE_LABELS+=("$label")
    PNM_STATUS_SERVICE_UNITS+=("$unit")
    PNM_STATUS_SERVICE_LOAD+=("$load")
    PNM_STATUS_SERVICE_ACTIVE+=("$active")
    PNM_STATUS_SERVICE_ENABLED+=("$enabled")
    PNM_STATUS_SERVICE_SUB+=("$sub")
}

pnm_status_collect() {
    local version_rc
    local -A status_node=()
    pnm_status_reset
    if pnm_load_node_config status_node && pnm_validate_node_config status_node; then
        PNM_STATUS_PROFILE=${status_node[PNM_PROFILE]-dual}
        PNM_STATUS_XRAY_PORT=$((10#${status_node[XRAY_PORT]}))
        PNM_STATUS_HY2_PORT=$((10#${status_node[HY2_PORT]}))
        PNM_STATUS_XRAY_DESIRED=false PNM_STATUS_HY2_DESIRED=false
        if pnm_profile_includes "$PNM_STATUS_PROFILE" xray; then PNM_STATUS_XRAY_DESIRED=true; fi
        if pnm_profile_includes "$PNM_STATUS_PROFILE" hysteria2; then PNM_STATUS_HY2_DESIRED=true; fi
    fi

    pnm_status_collect_service 'Xray' 'xray.service'
    pnm_status_collect_service 'Hysteria2' 'hysteria-server.service'

    if PNM_STATUS_XRAY_VERSION="$(pnm_binary_version "$PNM_XRAY_BIN" xray 2>/dev/null)"; then :; else
        version_rc=$?
        case "$version_rc" in
            127) PNM_STATUS_XRAY_VERSION='not-installed' ;;
            126) PNM_STATUS_XRAY_VERSION='not-executable' ;;
            69) PNM_STATUS_XRAY_VERSION='version-command-failed' ;;
            78) PNM_STATUS_XRAY_VERSION='version-parse-failed' ;;
            *) PNM_STATUS_XRAY_VERSION='unknown' ;;
        esac
    fi
    if PNM_STATUS_HY2_VERSION="$(pnm_binary_version "$PNM_HY2_BIN" hysteria 2>/dev/null)"; then :; else
        version_rc=$?
        case "$version_rc" in
            127) PNM_STATUS_HY2_VERSION='not-installed' ;;
            126) PNM_STATUS_HY2_VERSION='not-executable' ;;
            69) PNM_STATUS_HY2_VERSION='version-command-failed' ;;
            78) PNM_STATUS_HY2_VERSION='version-parse-failed' ;;
            *) PNM_STATUS_HY2_VERSION='unknown' ;;
        esac
    fi

    if [[ -n "$PNM_STATUS_XRAY_PORT" ]]; then
        if pnm_listener_present tcp "$PNM_STATUS_XRAY_PORT"; then
            PNM_STATUS_XRAY_LISTENER='listening'
        else
            case $? in
                1) PNM_STATUS_XRAY_LISTENER='not-listening' ;;
                *) PNM_STATUS_XRAY_LISTENER='unknown' ;;
            esac
        fi
    fi

    if [[ -n "$PNM_STATUS_HY2_PORT" ]]; then
        if pnm_listener_present udp "$PNM_STATUS_HY2_PORT"; then
            PNM_STATUS_HY2_LISTENER='listening'
        else
            case $? in
                1) PNM_STATUS_HY2_LISTENER='not-listening' ;;
                *) PNM_STATUS_HY2_LISTENER='unknown' ;;
            esac
        fi
    fi
}

pnm_status_render_text() {
    local index

    ((PNM_QUIET == 1)) && return 0
    printf 'Proxy Node Manager %s\n' "$(pnm_read_version)"
    printf 'Platform: %s\n' "$(pnm_platform_summary)"
    printf 'Configured: %s\n\n' "$(pnm_is_configured && printf 'yes' || printf 'no')"
    printf 'Desired profile: %s\n' "$PNM_STATUS_PROFILE"
    printf '%-14s %-12s %-12s %-12s %s\n' 'Service' 'Load' 'Active' 'Enabled' 'SubState'

    for index in "${!PNM_STATUS_SERVICE_LABELS[@]}"; do
        printf '%-14s %-12s %-12s %-12s %s\n' \
            "${PNM_STATUS_SERVICE_LABELS[$index]}" \
            "${PNM_STATUS_SERVICE_LOAD[$index]}" \
            "${PNM_STATUS_SERVICE_ACTIVE[$index]}" \
            "${PNM_STATUS_SERVICE_ENABLED[$index]}" \
            "${PNM_STATUS_SERVICE_SUB[$index]}"
    done

    printf '\nXray:       %s; TCP/%s %s\n' "$PNM_STATUS_XRAY_VERSION" "${PNM_STATUS_XRAY_PORT:-unknown}" "$PNM_STATUS_XRAY_LISTENER"
    printf 'Hysteria2:  %s; UDP/%s %s\n' "$PNM_STATUS_HY2_VERSION" "${PNM_STATUS_HY2_PORT:-unknown}" "$PNM_STATUS_HY2_LISTENER"
}

pnm_status_render_json() {
    local index comma=''

    printf '{'
    printf '"schema":"pnm.status.v1",'
    printf '"generated_at":%s,' "$(pnm_json_string "$(pnm_now_utc)")"
    printf '"version":%s,' "$(pnm_json_string "$(pnm_read_version)")"
    printf '"platform":%s,' "$(pnm_json_string "$(pnm_platform_summary)")"
    printf '"desired_profile":%s,' "$(pnm_json_string "$PNM_STATUS_PROFILE")"
    if pnm_is_configured; then
        printf '"configured":true,'
    else
        printf '"configured":false,'
    fi
    printf '"services":['
    for index in "${!PNM_STATUS_SERVICE_LABELS[@]}"; do
        printf '%s{' "$comma"
        printf '"label":%s,' "$(pnm_json_string "${PNM_STATUS_SERVICE_LABELS[$index]}")"
        printf '"unit":%s,' "$(pnm_json_string "${PNM_STATUS_SERVICE_UNITS[$index]}")"
        printf '"load":%s,' "$(pnm_json_string "${PNM_STATUS_SERVICE_LOAD[$index]}")"
        printf '"active":%s,' "$(pnm_json_string "${PNM_STATUS_SERVICE_ACTIVE[$index]}")"
        printf '"enabled":%s,' "$(pnm_json_string "${PNM_STATUS_SERVICE_ENABLED[$index]}")"
        printf '"substate":%s' "$(pnm_json_string "${PNM_STATUS_SERVICE_SUB[$index]}")"
        printf '}'
        comma=','
    done
    printf '],'
    printf '"cores":['
    printf '{"id":"xray","version":%s,"listener":%s,"port":%s,"desired_enabled":%s},' \
        "$(pnm_json_string "$PNM_STATUS_XRAY_VERSION")" \
        "$(pnm_json_string "$PNM_STATUS_XRAY_LISTENER")" "${PNM_STATUS_XRAY_PORT:-null}" "$PNM_STATUS_XRAY_DESIRED"
    printf '{"id":"hysteria2","version":%s,"listener":%s,"port":%s,"desired_enabled":%s}' \
        "$(pnm_json_string "$PNM_STATUS_HY2_VERSION")" \
        "$(pnm_json_string "$PNM_STATUS_HY2_LISTENER")" "${PNM_STATUS_HY2_PORT:-null}" "$PNM_STATUS_HY2_DESIRED"
    printf ']}'
    printf '\n'
}

pnm_status() {
    if ((EUID != 0)); then
        pnm_status_unlocked
        return $?
    fi
    pnm_with_deployment_read_lock pnm_status_unlocked
}

pnm_status_unlocked() {
    pnm_init_colors
    pnm_status_collect

    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_status_render_json
    else
        pnm_status_render_text
    fi
}
