#!/usr/bin/env bash

pnm_listener_present() {
    local protocol="${1:?protocol required}"
    local port="${2:?port required}"
    local flag

    pnm_command_exists ss || return 2
    pnm_validate_port "$port" || return 2

    case "$protocol" in
        tcp) flag='-ltnH' ;;
        udp) flag='-lunH' ;;
        *) return 2 ;;
    esac

    ss "$flag" 2>/dev/null | awk -v wanted="$port" '
        {
            local_addr = $4
            sub(/^.*:/, "", local_addr)
            gsub(/[^0-9].*$/, "", local_addr)
            if (local_addr == wanted) found = 1
        }
        END { exit(found ? 0 : 1) }
    '
}

pnm_binary_version() {
    local binary="${1:?binary required}"
    local style="${2:?version style required}"
    local output

    pnm_command_exists "$binary" || return 1
    case "$style" in
        xray)
            output="$("$binary" version 2>/dev/null | head -n 1)" || return 1
            ;;
        hysteria)
            output="$("$binary" version 2>/dev/null | head -n 1)" || return 1
            ;;
        *)
            return 1
            ;;
    esac
    pnm_one_line "$output"
    printf '\n'
}

pnm_apt_simulated_upgrades() {
    local output count

    pnm_command_exists apt-get || return 1
    if pnm_command_exists timeout; then
        output="$(LC_ALL=C timeout 20s apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null)" || return 1
    else
        output="$(LC_ALL=C apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null)" || return 1
    fi
    count="$(awk '/^Inst / {count += 1} END {print count + 0}' <<<"$output")"
    printf '%s\n' "$count"
}
