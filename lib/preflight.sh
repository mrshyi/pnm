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
declare -ag PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS=()

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
    PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS=()
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
    local -a missing=() asset_missing=() tls_missing=() unit_missing=() account_missing=() access_missing=()
    local command_name

    if pnm_systemd_available; then
        pnm_preflight_add systemd OK 'systemd is available' 'systemctl and runtime detected'
    else
        pnm_preflight_add systemd FAIL 'systemd is unavailable' 'PNM installation requires systemd'
    fi

    for command_name in apt-get awk curl flock install python3 sha256sum ss; do
        pnm_command_exists "$command_name" || missing+=("$command_name")
    done
    if ((${#missing[@]} == 0)); then
        pnm_preflight_add tools OK 'Base install tools are available' 'apt-get, awk, curl, flock, install, python3, sha256sum, ss'
    else
        pnm_preflight_add tools FAIL 'Base install tools are unavailable' "missing during preflight/transaction: ${missing[*]}"
    fi
    pnm_command_exists unzip || asset_missing+=(unzip)
    if ((${#asset_missing[@]} == 0)); then
        pnm_preflight_add xray_assets OK 'Xray asset tools are available' 'Xray ZIP staging requires unzip'
    else
        pnm_preflight_add xray_assets FAIL 'Xray asset tools are unavailable' "missing during Xray asset staging: ${asset_missing[*]}"
    fi
    pnm_command_exists openssl || tls_missing+=(openssl)
    if ((${#tls_missing[@]} == 0)); then
        pnm_preflight_add tls_tools OK 'TLS tools are available' 'openssl is required for TLS and secure credential generation'
    else
        pnm_preflight_add tls_tools FAIL 'TLS tools are unavailable' "missing during TLS/secret generation: ${tls_missing[*]}"
    fi
    pnm_command_exists systemd-analyze || unit_missing+=(systemd-analyze)
    if ((${#unit_missing[@]} == 0)); then
        pnm_preflight_add unit_tools OK 'systemd unit validation tool is available' 'systemd-analyze verify'
    else
        pnm_preflight_add unit_tools FAIL 'systemd unit validation tool is unavailable' "missing during service-unit staging: ${unit_missing[*]}"
    fi
    for command_name in getent groupadd useradd userdel groupdel id; do
        pnm_command_exists "$command_name" || account_missing+=("$command_name")
    done
    if ((${#account_missing[@]} == 0)); then
        pnm_preflight_add service_account_tools OK 'Service-account transaction tools are available' 'getent and account create/rollback tools'
    else
        pnm_preflight_add service_account_tools FAIL 'Service-account transaction tools are unavailable' "missing during account provisioning/rollback: ${account_missing[*]}"
    fi
    pnm_command_exists runuser || access_missing+=(runuser)
    if ((${#access_missing[@]} == 0)); then
        pnm_preflight_add service_access_tools OK 'Service-account access probe is available' 'runuser is required for the post-install TLS read check'
    else
        pnm_preflight_add service_access_tools FAIL 'Service-account access probe is unavailable' "missing during post-health TLS access validation: ${access_missing[*]}"
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

pnm_recovery_has_failed_deployment_record() {
    local deployments_dir="$PNM_STATE_DIR/deployments" directory journal owner_mode
    local timestamp event detail
    local saw_begin saw_resources saw_xray saw_hysteria saw_stopped saw_abandoned saw_commit

    PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS=()
    [[ "${PNM_PREFLIGHT_NODE_CONFIG[PNM_CONFIGURED]-yes}" == no ]] || return 1
    [[ -d "$PNM_STATE_DIR" && ! -L "$PNM_STATE_DIR" && -d "$deployments_dir" && ! -L "$deployments_dir" ]] || return 1
    owner_mode="$(stat -c '%a|%u' -- "$PNM_STATE_DIR" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return 1
    owner_mode="$(stat -c '%a|%u' -- "$deployments_dir" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return 1

    for directory in "$deployments_dir"/deploy-*; do
        [[ -d "$directory" && ! -L "$directory" ]] || continue
        owner_mode="$(stat -c '%a|%u' -- "$directory" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "700|$EUID" ]] || continue
        journal="$directory/journal.tsv"
        [[ -f "$journal" && ! -L "$journal" ]] || continue
        owner_mode="$(stat -c '%a|%u' -- "$journal" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "600|$EUID" ]] || continue
        saw_begin=0 saw_resources=0 saw_xray=0 saw_hysteria=0 saw_stopped=0 saw_abandoned=0 saw_commit=0
        while IFS=$'\t' read -r timestamp event detail || [[ -n "$timestamp$event$detail" ]]; do
            [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || continue 2
            case "$event:$detail" in
                BEGIN:deployment\ orchestration)
                    ((saw_begin == 0)) || continue 2
                    saw_begin=1
                    ;;
                PHASE_DONE:core-resources) ((saw_begin == 1)) && saw_resources=1 ;;
                PHASE_DONE:xray-lifecycle) ((saw_begin == 1)) && saw_xray=1 ;;
                PHASE_DONE:hysteria-lifecycle) ((saw_begin == 1)) && saw_hysteria=1 ;;
                STOPPED:after=post-health\ rc=*) ((saw_begin == 1)) && saw_stopped=1 ;;
                ABANDONED:deployment\ closed\ without\ commit) ((saw_stopped == 1)) && saw_abandoned=1 ;;
                COMMIT:*) saw_commit=1 ;;
            esac
        done <"$journal"
        if ((saw_begin && saw_resources && saw_xray && saw_hysteria && saw_stopped && saw_abandoned && !saw_commit)); then
            PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS+=("${directory##*/}")
        fi
    done
    ((${#PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS[@]} > 0))
}

pnm_recovery_unit_has_committed_pnm_receipt() {
    [[ -f "$1" && ! -L "$1" && "$(stat -c '%a|%u' -- "$1")" == '644|0' ]] || return 1
    pnm_recovery_resource_has_committed_pnm_receipt "$@"
}

pnm_recovery_resource_has_committed_pnm_receipt() {
    local unit_file="${1:?unit file required}" unit_label="${2:?unit label required}"
    local transaction_root="$PNM_STATE_DIR/transactions" transaction_dir transaction_id owner_mode encoded_target
    local state label encoded_path original_state original_mode record_hash expected_hash
    local last_state receipt_found deployment_id matched_deployment failed_deployment
    local -a failed_deployments=("${PNM_PREFLIGHT_RECOVERY_DEPLOYMENT_IDS[@]}")

    [[ -f "$unit_file" && ! -L "$unit_file" ]] || return 1
    [[ -d "$transaction_root" && ! -L "$transaction_root" ]] || return 1
    owner_mode="$(stat -c '%a|%u' -- "$transaction_root" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return 1
    encoded_target="$(printf '%s' "$unit_file" | base64 -w0)" || return 1

    for transaction_dir in "$transaction_root"/tx-*; do
        [[ -d "$transaction_dir" && ! -L "$transaction_dir" ]] || continue
        transaction_id="${transaction_dir##*/}"
        pnm_tx_load_for_inspect "$transaction_id" || continue
        [[ "$PNM_TX_INSPECT_STATE" == COMMITTED && "$PNM_TX_INSPECT_OPERATION" == sandbox-install ]] || continue
        deployment_id="$PNM_TX_INSPECT_DEPLOYMENT_ID"
        matched_deployment=0
        for failed_deployment in "${failed_deployments[@]}"; do
            [[ "$deployment_id" == "$failed_deployment" ]] && matched_deployment=1
        done
        ((matched_deployment == 1)) || continue

        last_state=''
        receipt_found=0
        expected_hash=''
        while IFS=$'\t' read -r state label encoded_path original_state original_mode record_hash ||
            [[ -n "$state$label$encoded_path$original_state$original_mode$record_hash" ]]; do
            [[ "$label" == "$unit_label" && "$encoded_path" == "$encoded_target" ]] || continue
            case "$state" in
                INTENT) last_state=INTENT ;;
                APPLIED) last_state=APPLIED; receipt_found=1; expected_hash="$record_hash" ;;
                RESTORED) last_state=RESTORED; receipt_found=0; expected_hash='' ;;
            esac
        done <"$transaction_dir/changes.tsv"
        if ((receipt_found == 1)) && [[ "$last_state" == APPLIED ]] &&
            [[ "$(pnm_tx_file_sha256 "$unit_file")" == "$expected_hash" ]]; then
            return 0
        fi
    done
    return 1
}

pnm_recovery_unit_has_no_dropins() {
    local unit="${1:?unit required}" dropins

    dropins="$(pnm_systemctl show "$unit" --property DropInPaths --value 2>/dev/null)" || return 1
    [[ -z "$dropins" ]]
}

pnm_recovery_listener_owned() {
    local protocol="${1:?protocol required}" port="${2:?port required}"
    local unit expected_user expected_binary unit_label expected_uid fragment user active enabled pid cgroup proc_uid executable unit_text
    pnm_validate_port "$port" || return 1
    case "$protocol" in
        tcp)
            [[ "$port" == "${PNM_PREFLIGHT_NODE_CONFIG[XRAY_PORT]-}" ]] || return 1
            unit=xray.service unit_label=xray_unit expected_user=xray expected_binary=/usr/local/bin/xray
            ;;
        udp)
            [[ "$port" == "${PNM_PREFLIGHT_NODE_CONFIG[HY2_PORT]-}" ]] || return 1
            unit=hysteria-server.service unit_label=hysteria_unit expected_user=hysteria expected_binary=/usr/local/bin/hysteria
            ;;
        *) return 1 ;;
    esac
    pnm_recovery_has_failed_deployment_record || return 1
    pnm_recovery_unit_has_committed_pnm_receipt "/etc/systemd/system/$unit" "$unit_label" || return 1
    unit_text="$(</etc/systemd/system/$unit)"
    pnm_unit_validate_text "$unit_text" "$expected_user" "$expected_binary" || return 1
    [[ "$unit_text" == *$'\nGroup='"$expected_user"$'\n'* ]] || return 1
    fragment="$(pnm_systemd_show_value "$unit" FragmentPath 2>/dev/null)" || return 1
    pnm_recovery_unit_has_no_dropins "$unit" || return 1
    user="$(pnm_systemd_show_value "$unit" User 2>/dev/null)" || return 1
    active="$(pnm_systemd_active_state "$unit" 2>/dev/null)" || return 1
    enabled="$(pnm_systemd_enabled_state "$unit" 2>/dev/null)" || return 1
    pid="$(pnm_systemd_show_value "$unit" MainPID 2>/dev/null)" || return 1
    [[ "$fragment" == "/etc/systemd/system/$unit" && "$user" == "$expected_user" && "$active" == active && "$enabled" == enabled ]] || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/cgroup" && -r "/proc/$pid/status" ]] || return 1
    expected_uid="$(id -u "$expected_user" 2>/dev/null)" || return 1
    proc_uid="$(awk '/^Uid:/ { print $2; exit }' "/proc/$pid/status")"
    [[ "$proc_uid" == "$expected_uid" ]] || return 1
    executable="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
    [[ "$executable" == "$expected_binary" ]] || return 1
    cgroup="$(<"/proc/$pid/cgroup")"
    [[ "$cgroup" == *"/system.slice/$unit"* ]] || return 1
    pnm_listener_owned_by_pid "$protocol" "$port" "$pid" || return 1
    # Also ensure the effective command agrees with the recorded PNM unit.
    [[ "$(pnm_systemd_show_value "$unit" ExecStart 2>/dev/null)" == *"$expected_binary"* ]]
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
        0)
            if pnm_recovery_listener_owned "$protocol" "$port"; then
                pnm_preflight_add "port_${protocol}_${port}" OK "Required ${protocol^^}/${port} is held by a verified PNM service" 'retrying an uncommitted deployment'
            else
                pnm_preflight_add "port_${protocol}_${port}" FAIL "Required ${protocol^^}/${port} is already in use" 'PNM will not replace an unknown listener'
            fi
            ;;
        1) pnm_preflight_add "port_${protocol}_${port}" OK "Required ${protocol^^}/${port} is free" 'no listener detected' ;;
        *) pnm_preflight_add "port_${protocol}_${port}" UNKNOWN "Required ${protocol^^}/${port} cannot be verified" 'ss is unavailable or returned an unexpected result' ;;
    esac
}

pnm_preflight_collect() {
    pnm_preflight_reset
    pnm_preflight_platform
    pnm_preflight_runtime
    pnm_preflight_configuration
    if pnm_validate_node_config PNM_PREFLIGHT_NODE_CONFIG; then
        pnm_preflight_port tcp "${PNM_PREFLIGHT_NODE_CONFIG[XRAY_PORT]}"
        pnm_preflight_port udp "${PNM_PREFLIGHT_NODE_CONFIG[HY2_PORT]}"
    else
        pnm_preflight_add ports UNKNOWN 'Required ports cannot be checked' 'node desired state is missing or invalid'
    fi
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
