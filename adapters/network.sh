#!/usr/bin/env bash

pnm_listener_present() {
    local protocol="${1:?protocol required}"
    local port="${2:?port required}"
    local attempts="${3:-1}" attempt flag
    local -a probe_status=()

    pnm_command_exists ss || return 2
    pnm_validate_port "$port" || return 2
    [[ "$attempts" =~ ^([1-9]|1[0-9]|2[0-6])$ ]] || return 2

    case "$protocol" in
        tcp) flag='-ltnH' ;;
        udp) flag='-lunH' ;;
        *) return 2 ;;
    esac

    # Type=simple can become active before its Core binds. Startup callers may
    # request up to 26 probes (25 x 0.2s waits); ordinary diagnostics stay instant.
    for ((attempt=1; attempt<=attempts; attempt++)); do
        if ss "$flag" 2>/dev/null | awk -v wanted="$port" '
        {
            local_addr = $4
            sub(/^.*:/, "", local_addr)
            gsub(/[^0-9].*$/, "", local_addr)
            if (local_addr == wanted) found = 1
        }
        END { exit(found ? 0 : 1) }
        '; then
            probe_status=("${PIPESTATUS[@]}")
        else
            probe_status=("${PIPESTATUS[@]}")
        fi
        # Tool errors are unknown, never an absent/free port. Inspect both
        # commands even when awk matched data emitted by a failing ss process.
        ((probe_status[0] == 0)) || return 2
        case "${probe_status[1]}" in
            0) return 0 ;;
            1) ;;
            *) return 2 ;;
        esac
        ((attempt < attempts)) || break
        sleep 0.2 || return 2
    done
    return 1
}

# Return success only when the requested listening socket is owned by this PID.
# The caller must independently bind the PID to a verified systemd unit.
pnm_listener_owned_by_pid() {
    local protocol="${1:?protocol required}"
    local port="${2:?port required}"
    local pid="${3:?pid required}"
    local flag

    pnm_command_exists ss || return 2
    pnm_validate_port "$port" && [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 2
    case "$protocol" in
        tcp) flag='-ltnpH' ;;
        udp) flag='-lunpH' ;;
        *) return 2 ;;
    esac

    ss "$flag" "sport = :$port" 2>/dev/null | awk -v wanted="$port" -v pid="$pid" '
        {
            local_addr = $4
            sub(/^.*:/, "", local_addr)
            gsub(/[^0-9].*$/, "", local_addr)
            if (local_addr != wanted) next
            sockets++
            line_has_pid = 0
            while (match($0, /pid=[0-9]+/)) {
                owner = substr($0, RSTART + 4, RLENGTH - 4)
                line_has_pid = 1
                if (owner != pid) foreign = 1
                $0 = substr($0, RSTART + RLENGTH)
            }
            if (!line_has_pid) unattributed = 1
        }
        END { exit(sockets > 0 && !foreign && !unattributed ? 0 : 1) }
    '
}

pnm_binary_version() {
    local binary="${1:?binary required}"
    local style="${2:?version style required}"
    local output version

    if [[ "$binary" == */* ]]; then
        [[ -f "$binary" ]] || return 127
        [[ -x "$binary" ]] || return 126
    elif ! pnm_command_exists "$binary"; then
        return 127
    fi
    case "$style" in
        xray)
            output="$("$binary" version 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
            version="$(head -n 1 <<<"$output")"
            ;;
        hysteria)
            output="$("$binary" version 2>&1)" || return "$PNM_EXIT_UNAVAILABLE"
            if version="$(sed 's/\r$//' <<<"$output" | sed -nE 's/^[[:space:]]*Version:[[:space:]]*(v?[0-9]+(\.[0-9]+){2}([._+-][A-Za-z0-9.-]+)?)([[:space:]].*)?$/\1/p' | head -n 1)"; then :; else version=''; fi
            ;;
        *)
            return "$PNM_EXIT_USAGE"
            ;;
    esac
    [[ -n "$version" ]] || return "$PNM_EXIT_CONFIG"
    pnm_one_line "$version"
    printf '\n'
}

pnm_binary_version_failure_reason() {
    case "${1:?version command exit status required}" in
        126) printf 'binary is not executable\n' ;;
        127) printf 'binary was not found\n' ;;
        "$PNM_EXIT_UNAVAILABLE") printf 'version command failed\n' ;;
        "$PNM_EXIT_CONFIG") printf 'version output could not be parsed\n' ;;
        *) printf 'version could not be determined\n' ;;
    esac
}

pnm_binary_version_number() {
    local binary="${1:?binary required}"
    local style="${2:?version style required}"
    local output version

    output="$(pnm_binary_version "$binary" "$style")" || return $?
    if version="$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?' <<<"$output" | head -n 1)"; then :; else version=''; fi
    [[ -n "$version" ]] || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "${version#v}"
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
