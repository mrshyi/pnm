#!/usr/bin/env bash

PNM_LIFECYCLE_CORE=''
PNM_LIFECYCLE_UNIT=''
PNM_LIFECYCLE_PRE_ACTIVE=''
PNM_LIFECYCLE_PRE_ENABLED=''

pnm_core_lifecycle_reset() {
    PNM_LIFECYCLE_CORE=''
    PNM_LIFECYCLE_UNIT=''
    PNM_LIFECYCLE_PRE_ACTIVE=''
    PNM_LIFECYCLE_PRE_ENABLED=''
}

pnm_core_lifecycle_unit() {
    case "${1:?core id required}" in
        xray) printf '%s\n' 'xray.service' ;;
        hysteria2) printf '%s\n' 'hysteria-server.service' ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
}

pnm_core_lifecycle_snapshot() {
    local core="${1:?core id required}"
    local unit active enabled

    unit="$(pnm_core_lifecycle_unit "$core")" || return $?
    active="$(pnm_systemd_active_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
    enabled="$(pnm_systemd_enabled_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$active" == active || "$active" == inactive ]] || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$enabled" == enabled || "$enabled" == disabled ]] || return "$PNM_EXIT_UNAVAILABLE"
    PNM_LIFECYCLE_CORE="$core"
    PNM_LIFECYCLE_UNIT="$unit"
    PNM_LIFECYCLE_PRE_ACTIVE="$active"
    PNM_LIFECYCLE_PRE_ENABLED="$enabled"
}

pnm_core_lifecycle_restore() {
    local rc=0 current_active current_enabled

    [[ -n "$PNM_LIFECYCLE_UNIT" ]] || return "$PNM_EXIT_SOFTWARE"
    current_active="$(pnm_systemd_active_state "$PNM_LIFECYCLE_UNIT")" || return "$PNM_EXIT_SOFTWARE"
    current_enabled="$(pnm_systemd_enabled_state "$PNM_LIFECYCLE_UNIT")" || return "$PNM_EXIT_SOFTWARE"
    [[ "$current_active" == active || "$current_active" == inactive ]] || return "$PNM_EXIT_SOFTWARE"
    [[ "$current_enabled" == enabled || "$current_enabled" == disabled ]] || return "$PNM_EXIT_SOFTWARE"
    if [[ "$current_active" != "$PNM_LIFECYCLE_PRE_ACTIVE" ]]; then
        if [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]]; then
            pnm_systemd_start "$PNM_LIFECYCLE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
        else
            pnm_systemd_stop "$PNM_LIFECYCLE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
        fi
    fi
    if ((rc == 0)); then
        if [[ "$current_enabled" != "$PNM_LIFECYCLE_PRE_ENABLED" ]]; then
            if [[ "$PNM_LIFECYCLE_PRE_ENABLED" == enabled ]]; then
                pnm_systemd_enable "$PNM_LIFECYCLE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
            else
                pnm_systemd_disable "$PNM_LIFECYCLE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
            fi
        fi
    fi
    if ((rc == 0)); then
        pnm_systemd_daemon_reload || rc="$PNM_EXIT_SOFTWARE"
    fi
    return "$rc"
}

pnm_core_lifecycle_reload_step() {
    pnm_systemd_daemon_reload || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_lifecycle_enable_step() {
    pnm_systemd_enable "$PNM_LIFECYCLE_UNIT" || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_lifecycle_start_step() {
    pnm_systemd_start "$PNM_LIFECYCLE_UNIT" || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_lifecycle_health_step() {
    pnm_systemd_unit_healthy "$PNM_LIFECYCLE_UNIT" || return "$PNM_EXIT_CONFIG"
}

pnm_core_lifecycle_apply() {
    local core="${1:?core id required}"
    local rc

    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_core_lifecycle_snapshot "$core" || return $?
    pnm_tx_begin "core-lifecycle-$core" || return $?
    if ((PNM_DRY_RUN == 0)); then
        if pnm_tx_record_core_state "$core" "$PNM_LIFECYCLE_UNIT" "$PNM_LIFECYCLE_PRE_ACTIVE" "$PNM_LIFECYCLE_PRE_ENABLED"; then
            :
        else
            rc=$?
            pnm_tx_close
            return "$rc"
        fi
    fi
    pnm_tx_add_rollback pnm_core_lifecycle_restore || {
        pnm_tx_close
        return "$PNM_EXIT_SOFTWARE"
    }

    if ((PNM_DRY_RUN == 1)); then
        pnm_tx_journal PLAN "core=$core unit=$PNM_LIFECYCLE_UNIT action=daemon-reload,enable,start,health"
        pnm_tx_commit
        pnm_tx_close
        return 0
    fi

    if pnm_tx_run daemon_reload pnm_core_lifecycle_reload_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run enable pnm_core_lifecycle_enable_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run start pnm_core_lifecycle_start_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run health pnm_core_lifecycle_health_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    pnm_tx_commit || { rc=$?; pnm_tx_close; return "$rc"; }
    pnm_tx_close
}
