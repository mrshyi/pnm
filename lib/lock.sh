#!/usr/bin/env bash

PNM_LOCK_FD=''
PNM_LOCK_DEPTH=0
PNM_LOCK_MODE=''

pnm_lock_acquire() {
    local mode="${1:-exclusive}"
    local lock_parent

    case "$mode" in
        shared | exclusive) ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac

    if ((PNM_LOCK_DEPTH > 0)); then
        [[ "$mode" == "$PNM_LOCK_MODE" ]] || return "$PNM_EXIT_CANTCREAT"
        ((PNM_LOCK_DEPTH += 1))
        return 0
    fi

    pnm_command_exists flock || {
        pnm_error "Required command is unavailable: flock"
        return "$PNM_EXIT_UNAVAILABLE"
    }

    lock_parent="$(dirname -- "$PNM_LOCK_FILE")"
    [[ -d "$lock_parent" ]] || pnm_mkdir_mode 0755 "$lock_parent"

    exec {PNM_LOCK_FD}>"$PNM_LOCK_FILE" || return "$PNM_EXIT_CANTCREAT"
    if [[ "$mode" == "shared" ]]; then
        if ! flock -n -s "$PNM_LOCK_FD"; then
            exec {PNM_LOCK_FD}>&-
            PNM_LOCK_FD=''
            return "$PNM_EXIT_CANTCREAT"
        fi
    else
        if ! flock -n -x "$PNM_LOCK_FD"; then
            exec {PNM_LOCK_FD}>&-
            PNM_LOCK_FD=''
            return "$PNM_EXIT_CANTCREAT"
        fi
    fi
    PNM_LOCK_DEPTH=1
    PNM_LOCK_MODE="$mode"
}

pnm_lock_release() {
    ((PNM_LOCK_DEPTH > 0)) || return 0
    if ((PNM_LOCK_DEPTH > 1)); then
        ((PNM_LOCK_DEPTH -= 1))
        return 0
    fi
    flock -u "$PNM_LOCK_FD" || true
    exec {PNM_LOCK_FD}>&-
    PNM_LOCK_FD=''
    PNM_LOCK_DEPTH=0
    PNM_LOCK_MODE=''
}
