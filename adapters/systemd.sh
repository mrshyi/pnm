#!/usr/bin/env bash

pnm_systemctl_bin() {
    printf '%s\n' "${PNM_SYSTEMCTL_BIN:-systemctl}"
}

pnm_systemctl_exists() {
    local binary

    binary="$(pnm_systemctl_bin)"
    if [[ "$binary" == */* ]]; then
        [[ -x "$binary" && ! -L "$binary" ]]
    else
        pnm_command_exists "$binary"
    fi
}

pnm_systemctl() {
    local binary

    binary="$(pnm_systemctl_bin)"
    pnm_systemctl_exists || return "$PNM_EXIT_UNAVAILABLE"
    "$binary" "$@"
}

pnm_systemd_available() {
    pnm_systemctl_exists && [[ -d /run/systemd/system || "${PNM_TEST_SYSTEMD:-0}" == "1" ]]
}

pnm_systemd_show_value() {
    local unit="${1:?unit required}"
    local property="${2:?property required}"
    local output

    pnm_systemd_available || return 1
    if output="$(pnm_systemctl show "$unit" --property "$property" --value 2>/dev/null)"; then
        printf '%s\n' "${output:-unknown}"
        return 0
    fi
    return 1
}

pnm_systemd_load_state() {
    pnm_systemd_show_value "$1" LoadState
}

pnm_systemd_active_state() {
    pnm_systemd_show_value "$1" ActiveState
}

pnm_systemd_sub_state() {
    pnm_systemd_show_value "$1" SubState
}

pnm_systemd_enabled_state() {
    local unit="${1:?unit required}"
    local output

    pnm_systemd_available || return 1
    if output="$(pnm_systemctl is-enabled "$unit" 2>/dev/null)"; then
        printf '%s\n' "${output:-unknown}"
        return 0
    fi

    case "$output" in
        disabled | static | indirect | masked | generated | transient | not-found)
            printf '%s\n' "$output"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

pnm_systemd_failed_units() {
    local output

    pnm_systemd_available || return 1
    if output="$(pnm_systemctl list-units --state=failed --no-legend --plain 2>/dev/null)"; then
        printf '%s\n' "$output"
        return 0
    fi
    return 1
}

pnm_service_state_line() {
    local unit="${1:?unit required}"
    local load active enabled sub

    load="$(pnm_systemd_load_state "$unit" 2>/dev/null || printf 'unknown')"
    active="$(pnm_systemd_active_state "$unit" 2>/dev/null || printf 'unknown')"
    enabled="$(pnm_systemd_enabled_state "$unit" 2>/dev/null || printf 'unknown')"
    sub="$(pnm_systemd_sub_state "$unit" 2>/dev/null || printf 'unknown')"
    printf '%s|%s|%s|%s\n' "$load" "$active" "$enabled" "$sub"
}

pnm_systemd_daemon_reload() {
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl daemon-reload
}

pnm_systemd_enable() {
    local unit="${1:?unit required}"

    [[ "$unit" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl enable "$unit"
}

pnm_systemd_disable() {
    local unit="${1:?unit required}"

    [[ "$unit" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl disable "$unit"
}

pnm_systemd_start() {
    local unit="${1:?unit required}"

    [[ "$unit" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl start "$unit"
}

pnm_systemd_stop() {
    local unit="${1:?unit required}"

    [[ "$unit" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl stop "$unit"
}

pnm_systemd_reload() {
    local unit="${1:?unit required}"

    [[ "$unit" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    pnm_systemctl reload "$unit"
}

pnm_systemd_unit_healthy() {
    local unit="${1:?unit required}"
    local active enabled

    active="$(pnm_systemd_active_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
    enabled="$(pnm_systemd_enabled_state "$unit")" || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$active" == active && "$enabled" == enabled ]]
}

pnm_timedatectl_synchronized() {
    local output

    pnm_command_exists timedatectl || return 1
    if output="$(timedatectl show --property NTPSynchronized --value 2>/dev/null)"; then
        printf '%s\n' "$output"
        return 0
    fi
    return 1
}
