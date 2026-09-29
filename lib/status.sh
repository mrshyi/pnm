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
    pnm_status_reset

    pnm_status_collect_service 'Xray' 'xray.service'
    pnm_status_collect_service 'Hysteria2' 'hysteria-server.service'

    PNM_STATUS_XRAY_VERSION="$(pnm_binary_version xray xray 2>/dev/null || printf 'not-installed')"
    PNM_STATUS_HY2_VERSION="$(pnm_binary_version hysteria hysteria 2>/dev/null || printf 'not-installed')"

    if pnm_listener_present tcp 443; then
        PNM_STATUS_XRAY_LISTENER='listening'
    else
        case $? in
            1) PNM_STATUS_XRAY_LISTENER='not-listening' ;;
            *) PNM_STATUS_XRAY_LISTENER='unknown' ;;
        esac
    fi

    if pnm_listener_present udp 8443; then
        PNM_STATUS_HY2_LISTENER='listening'
    else
        case $? in
            1) PNM_STATUS_HY2_LISTENER='not-listening' ;;
            *) PNM_STATUS_HY2_LISTENER='unknown' ;;
        esac
    fi
}

pnm_status_render_text() {
    local index

    ((PNM_QUIET == 1)) && return 0
    printf 'Proxy Node Manager %s\n' "$(pnm_read_version)"
    printf 'Platform: %s\n' "$(pnm_platform_summary)"
    printf 'Configured: %s\n\n' "$(pnm_is_configured && printf 'yes' || printf 'no')"
    printf '%-14s %-12s %-12s %-12s %s\n' 'Service' 'Load' 'Active' 'Enabled' 'SubState'

    for index in "${!PNM_STATUS_SERVICE_LABELS[@]}"; do
        printf '%-14s %-12s %-12s %-12s %s\n' \
            "${PNM_STATUS_SERVICE_LABELS[$index]}" \
            "${PNM_STATUS_SERVICE_LOAD[$index]}" \
            "${PNM_STATUS_SERVICE_ACTIVE[$index]}" \
            "${PNM_STATUS_SERVICE_ENABLED[$index]}" \
            "${PNM_STATUS_SERVICE_SUB[$index]}"
    done

    printf '\nXray:       %s; TCP/443 %s\n' "$PNM_STATUS_XRAY_VERSION" "$PNM_STATUS_XRAY_LISTENER"
    printf 'Hysteria2:  %s; UDP/8443 %s\n' "$PNM_STATUS_HY2_VERSION" "$PNM_STATUS_HY2_LISTENER"
}

pnm_status_render_json() {
    local index comma=''

    printf '{'
    printf '"schema":"pnm.status.v1",'
    printf '"generated_at":%s,' "$(pnm_json_string "$(pnm_now_utc)")"
    printf '"version":%s,' "$(pnm_json_string "$(pnm_read_version)")"
    printf '"platform":%s,' "$(pnm_json_string "$(pnm_platform_summary)")"
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
    printf '{"id":"xray","version":%s,"listener":%s},' \
        "$(pnm_json_string "$PNM_STATUS_XRAY_VERSION")" \
        "$(pnm_json_string "$PNM_STATUS_XRAY_LISTENER")"
    printf '{"id":"hysteria2","version":%s,"listener":%s}' \
        "$(pnm_json_string "$PNM_STATUS_HY2_VERSION")" \
        "$(pnm_json_string "$PNM_STATUS_HY2_LISTENER")"
    printf ']}'
    printf '\n'
}

pnm_status() {
    pnm_init_colors
    pnm_status_collect

    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_status_render_json
    else
        pnm_status_render_text
    fi
}
