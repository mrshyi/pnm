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

    if ((EUID != 0)); then
        case "$id" in
            configuration | xray | hysteria2 | *_runtime_config)
                if [[ "$status" == OK || "$status" == SKIP ]]; then
                    status=UNKNOWN
                    summary='Deployment consistency requires root privileges'
                    detail='protected deployment records are not visible'
                fi
                ;;
        esac
    fi

    case "$status" in
        OK) ;;
        SKIP) ;;
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

    if ((EUID != 0)) && [[ ! -r "$PNM_CONFIG_DIR/node.conf" ]]; then
        pnm_check_add configuration UNKNOWN 'PNM configuration cannot be inspected' 'root privileges are required'
        return 0
    fi

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
        pnm_check_add platform FAIL 'Unsupported platform' "expected $(pnm_platform_support_policy); got $summary"
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
    local state active enabled version test_output version_rc
    local severity='FAIL'

    ((PNM_CHECK_CONFIGURED == 0)) && severity='WARN'
    if version="$(pnm_binary_version "$PNM_XRAY_BIN" xray 2>/dev/null)"; then
        version_rc=0
    else
        version_rc=$?
        version=''
    fi
    state="$(pnm_service_state_line xray.service)"
    IFS='|' read -r _ active enabled _ <<<"$state"

    if ((version_rc == 127)); then
        pnm_check_add xray "$severity" 'Xray is not installed' 'xray binary not found'
        return 0
    fi
    if ((version_rc != 0)); then
        pnm_check_add xray "$severity" 'Xray version could not be determined' "$(pnm_binary_version_failure_reason "$version_rc")"
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
    local state active enabled version version_rc
    local severity='FAIL'

    ((PNM_CHECK_CONFIGURED == 0)) && severity='WARN'
    if version="$(pnm_binary_version "$PNM_HY2_BIN" hysteria 2>/dev/null)"; then
        version_rc=0
    else
        version_rc=$?
        version=''
    fi
    state="$(pnm_service_state_line hysteria-server.service)"
    IFS='|' read -r _ active enabled _ <<<"$state"

    if ((version_rc == 127)); then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 is not installed' 'hysteria binary not found'
        return 0
    fi
    if ((version_rc != 0)); then
        pnm_check_add hysteria2 "$severity" 'Hysteria2 version could not be determined' "$(pnm_binary_version_failure_reason "$version_rc")"
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

# Strict local deployment gate. This is intentionally limited to local Core
# readiness; a listening socket does not prove public reachability.
pnm_check_deploy_core_health() {
    local core="${1:?Core id required}" index id status

    case "$core" in
        xray) ;;
        hysteria2 | hy2) core=hysteria2 ;;
        *) return "$PNM_EXIT_USAGE" ;;
    esac
    pnm_check_reset
    pnm_load_node_config PNM_NODE_CONFIG && pnm_validate_node_config PNM_NODE_CONFIG || return "$PNM_EXIT_CONFIG"
    # Install runs before node.conf is marked configured; for this gate the
    # managed resources must already meet the strict configured policy.
    PNM_CHECK_CONFIGURED=1
    if [[ "$core" == xray ]]; then
        pnm_check_xray
        pnm_check_file_metadata xray_permissions "$PNM_XRAY_CONFIG" 640 root xray
        local -A reality=()
        if pnm_load_reality_secret reality && pnm_validate_reality_secret_config reality &&
            pnm_xray_config_matches_node PNM_NODE_CONFIG reality; then
            pnm_check_add xray_config_consistency OK 'Runtime Xray configuration matches desired settings' ''
        else
            pnm_check_add xray_config_consistency FAIL 'Runtime Xray configuration differs from desired settings' 'candidate/runtime comparison failed'
        fi
    else
        pnm_check_hysteria
        pnm_check_file_metadata hysteria_permissions "$PNM_HY2_CONFIG" 600 hysteria hysteria
        pnm_check_hysteria_tls
        pnm_check_hysteria_tls_permissions
        local -A hysteria=()
        if pnm_load_hysteria_secret hysteria && pnm_validate_hysteria_secret_config hysteria &&
            pnm_hysteria_config_validate_candidate "$PNM_HY2_CONFIG" PNM_NODE_CONFIG hysteria; then
            pnm_check_add hysteria2_config_syntax OK 'Runtime Hysteria2 configuration is valid and matches desired settings' ''
        else
            pnm_check_add hysteria2_config_syntax FAIL 'Runtime Hysteria2 configuration is invalid or differs from desired settings' "${PNM_HY2_CONFIG_DIAGNOSTIC:-candidate validation failed}"
        fi
    fi
    for index in "${!PNM_CHECK_IDS[@]}"; do
        id="${PNM_CHECK_IDS[$index]}"
        status="${PNM_CHECK_STATUSES[$index]}"
        case "$id" in
            xray | xray_permissions | xray_config_consistency | hysteria2 | hysteria_permissions | hysteria_tls | hysteria_tls_permissions | hysteria2_config_syntax)
                if [[ "$status" != OK ]]; then
                    pnm_error "$core post-health failed at $id ($status); deployment must roll back before commit."
                    return "$PNM_EXIT_CONFIG"
                fi
                ;;
        esac
    done
}

pnm_check_hysteria_tls() {
    local result status detail
    local -A hysteria_secret=()

    if ((PNM_CHECK_CONFIGURED == 0)); then
        pnm_check_add hysteria_tls SKIP 'TLS certificate check skipped' 'PNM node is not configured'
        return 0
    fi
    if ! pnm_load_hysteria_secret hysteria_secret || ! pnm_validate_hysteria_secret_config hysteria_secret; then
        pnm_check_add hysteria_tls WARN 'TLS certificate validity cannot be determined' 'Hysteria2 credentials or certificate path are unavailable'
        return 0
    fi

    result="$(pnm_tls_certificate_check "${PNM_NODE_CONFIG[HY2_TLS_MODE]}" "${hysteria_secret[HY2_TLS_CERT_PATH]}")" || result='WARN|TLS certificate validity cannot be determined'
    IFS='|' read -r status detail <<<"$result"
    if [[ "$status" == OK ]] && ! pnm_hysteria_tls_server_name PNM_NODE_CONFIG hysteria_secret >/dev/null 2>&1; then
        pnm_check_add hysteria_tls FAIL 'HY2 TLS server name does not match its certificate' 'HY2_TLS_SERVER_NAME must match a DNS SAN in the configured certificate'
        return 0
    fi
    case "$status" in
        OK) pnm_check_add hysteria_tls OK 'TLS certificate is within its validity period' "$detail" ;;
        FAIL) pnm_check_add hysteria_tls FAIL 'TLS certificate is outside its validity period' "$detail" ;;
        SKIP) pnm_check_add hysteria_tls SKIP 'TLS certificate check skipped' "$detail" ;;
        *) pnm_check_add hysteria_tls WARN 'TLS certificate validity cannot be determined' "$detail" ;;
    esac
}

pnm_check_hysteria_tls_permissions() {
    local cert key cert_meta key_meta
    local -A secret=()

    if ((PNM_CHECK_CONFIGURED == 0)); then
        pnm_check_add hysteria_tls_permissions SKIP 'HY2 TLS file permission check skipped' 'PNM node is not configured'
        return 0
    fi
    case "${PNM_NODE_CONFIG[HY2_TLS_MODE]-}" in
        selfsigned-pin | external-ca) ;;
        *) pnm_check_add hysteria_tls_permissions SKIP 'HY2 TLS file permission check skipped' 'TLS mode is not backed by static certificate files'; return 0 ;;
    esac
    if ! pnm_load_hysteria_secret secret || ! pnm_validate_hysteria_secret_config secret; then
        pnm_check_add hysteria_tls_permissions UNKNOWN 'HY2 TLS file access cannot be determined' 'certificate path metadata is unavailable'
        return 0
    fi
    cert="${secret[HY2_TLS_CERT_PATH]}"
    key="${secret[HY2_TLS_KEY_PATH]}"
    if [[ ! -f "$cert" || -L "$cert" || ! -f "$key" || -L "$key" ]]; then
        pnm_check_add hysteria_tls_permissions FAIL 'HY2 TLS certificate or private key is missing or unsafe' 'expected regular non-symlink certificate and private key files'
        return 0
    fi
    if ! cert_meta="$(stat -c '%a|%U|%G' -- "$cert" 2>/dev/null)" ||
        ! key_meta="$(stat -c '%a|%U|%G' -- "$key" 2>/dev/null)"; then
        pnm_check_add hysteria_tls_permissions UNKNOWN 'HY2 TLS file ownership cannot be determined' 'stat metadata unavailable'
        return 0
    fi
    if [[ "$cert_meta" != '644|root|hysteria' || "$key_meta" != '600|hysteria|hysteria' ]]; then
        pnm_check_add hysteria_tls_permissions FAIL 'HY2 TLS file permissions do not match service access policy' \
            "certificate=$cert_meta; private_key=$key_meta; expected certificate=644 root:hysteria and private_key=600 hysteria:hysteria"
        return 0
    fi
    if declare -F pnm_service_account_existing_valid >/dev/null 2>&1 && ! pnm_service_account_existing_valid hysteria; then
        pnm_check_add hysteria_tls_permissions FAIL 'HY2 service account cannot be verified for TLS access' 'hysteria account does not match the PNM service policy'
        return 0
    fi
    if ((EUID == 0)); then
        if ! pnm_command_exists runuser; then
            pnm_check_add hysteria_tls_permissions UNKNOWN 'HY2 service-account file access cannot be probed' 'runuser is unavailable; ownership and mode policy matched'
            return 0
        fi
        if ! runuser -u hysteria -- test -r "$cert" || ! runuser -u hysteria -- test -r "$key"; then
            pnm_check_add hysteria_tls_permissions FAIL 'Hysteria2 service account cannot read its TLS files' 'effective read probe failed; no permissions were changed'
            return 0
        fi
    elif [[ ! -r "$cert" || ! -r "$key" ]]; then
        pnm_check_add hysteria_tls_permissions WARN 'HY2 TLS file access cannot be fully verified without root' 'permissions prevent the current user from reading the certificate or private key'
        return 0
    fi
    pnm_check_add hysteria_tls_permissions OK 'HY2 TLS files are readable under the service account policy' 'certificate and private key ownership and modes match policy'
}

pnm_check_core_runtime_consistency() {
    local core="${1:?Core id required}"
    local status_line status service config_state applied reason severity='FAIL'
    local secret_name=PNM_CHECK_CORE_SECRET
    local -A PNM_CHECK_CORE_SECRET=()

    if ((PNM_CHECK_CONFIGURED == 0)); then
        pnm_check_add "${core}_runtime_config" SKIP 'Applied configuration check skipped' 'PNM node is not configured'
        return 0
    fi
    if [[ "$core" == xray ]]; then
        if ! pnm_load_reality_secret "$secret_name" || ! pnm_validate_reality_secret_config "$secret_name"; then
            pnm_check_add xray_runtime_config UNKNOWN 'Applied Xray configuration cannot be confirmed' 'REALITY credential metadata is unavailable or invalid'
            return 0
        fi
    elif ! pnm_load_hysteria_secret "$secret_name" || ! pnm_validate_hysteria_secret_config "$secret_name"; then
        pnm_check_add hysteria2_runtime_config UNKNOWN 'Applied Hysteria2 configuration cannot be confirmed' 'Hysteria2 credential metadata is unavailable or invalid'
        return 0
    fi

    status_line="$(pnm_node_core_link_status "$core" PNM_NODE_CONFIG "$secret_name" 2>/dev/null)" || {
        pnm_check_add "${core}_runtime_config" UNKNOWN 'Applied configuration cannot be confirmed' 'runtime state query failed'
        return 0
    }
    IFS='|' read -r status service config_state applied reason <<<"$status_line"
    [[ "$status" == ready ]] && severity=OK
    case "$status" in
        ready) pnm_check_add "${core}_runtime_config" OK 'Runtime configuration matches the last successful PNM apply' "service=$service config=$config_state applied=$applied" ;;
        drift) pnm_check_add "${core}_runtime_config" FAIL 'Runtime configuration drift detected' "service=$service config=$config_state applied=$applied${reason:+; $reason}" ;;
        inactive) pnm_check_add "${core}_runtime_config" FAIL 'Core service is not active' "service=$service config=$config_state applied=$applied" ;;
        damaged) pnm_check_add "${core}_runtime_config" FAIL 'Runtime configuration or apply evidence is damaged' "service=$service config=$config_state applied=$applied" ;;
        *) pnm_check_add "${core}_runtime_config" UNKNOWN 'Applied Core configuration cannot be confirmed' "service=$service config=$config_state applied=$applied${reason:+; $reason}" ;;
    esac
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
    if ((EUID != 0)); then
        pnm_check_add deployment_state UNKNOWN 'Deployment transaction state cannot be inspected' 'run sudo pnm check for committed-state verification'
    fi
    pnm_check_configuration
    pnm_check_platform
    pnm_check_systemd_runtime
    pnm_check_xray
    pnm_check_hysteria
    pnm_check_core_runtime_consistency xray
    pnm_check_core_runtime_consistency hysteria2
    pnm_check_hysteria_tls
    pnm_check_hysteria_tls_permissions
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
    if ((EUID != 0)); then
        pnm_check_unlocked "$@"
        return $?
    fi
    pnm_with_deployment_read_lock pnm_check_unlocked "$@"
}

pnm_check_unlocked() {
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
