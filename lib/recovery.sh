#!/usr/bin/env bash

pnm_recovery_command() {
    local action="${1:-list}" id='' rc=0
    (($# == 0)) || shift
    case "$action" in
        -h | --help) pnm_print_help recovery; return $? ;;
        list) (($# == 0)) || return "$PNM_EXIT_USAGE" ;;
        inspect)
            (($# == 1)) || return "$PNM_EXIT_USAGE"
            id=$1
            [[ "$id" =~ ^[A-Za-z0-9._-]{1,80}$ && "$id" != . && "$id" != .. ]] || return "$PNM_EXIT_USAGE"
            ;;
        *) pnm_error 'Usage: pnm recovery list | inspect TRANSACTION_ID'; return "$PNM_EXIT_USAGE" ;;
    esac
    pnm_require_root || return $?
    pnm_lock_acquire shared || return $?
    # Diagnostic exception: a pending transaction is what this reader reports.
    # It must not use the ordinary read guard that refuses that very evidence.
    if pnm_recovery_report "$id"; then :; else rc=$?; fi
    pnm_lock_release || rc="$PNM_EXIT_SOFTWARE"
    return "$rc"
}

pnm_recovery_validate_store() {
    local directory
    for directory in "$PNM_STATE_DIR" "$PNM_STATE_DIR/transactions"; do
        [[ -e "$directory" || -L "$directory" ]] || continue
        pnm_validate_managed_path "$directory" || return "$PNM_EXIT_CONFIG"
        [[ -d "$directory" && ! -L "$directory" &&
            "$(stat -c '%a:%u' -- "$directory")" == "700:$EUID" ]] || {
            pnm_error 'Transaction store ownership or permissions are unsafe.'
            return "$PNM_EXIT_NOPERM"
        }
    done
}

pnm_recovery_render_entry() {
    local id=$1 state=INVALID operation=unknown changes=null valid=false
    local directory="$PNM_STATE_DIR/transactions/$id"
    if [[ "$id" =~ ^[A-Za-z0-9._-]{1,80}$ && "$id" != . && "$id" != .. ]]; then
        if [[ -d "$directory" && ! -L "$directory" ]] &&
            pnm_tx_load_for_inspect "$id" >/dev/null 2>&1; then
            state=$PNM_TX_INSPECT_STATE operation=$PNM_TX_INSPECT_OPERATION
            changes=$PNM_TX_INSPECT_CHANGES valid=true
        fi
    else
        # Untrusted directory names are not safe diagnostic content.
        id=''
    fi
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"id":%s,"operation":%s,"state":%s,"file_directory_changes":%s,"valid":%s}' \
            "$(if [[ -n "$id" ]]; then pnm_json_string "$id"; else printf null; fi)" \
            "$(pnm_json_string "$operation")" "$(pnm_json_string "$state")" "$changes" "$valid"
    else
        printf '%-36s %-24s %-18s %s\n' "${id:-unrecognized-entry}" "$operation" "$state" "$changes"
    fi
    [[ "$valid" == true ]]
}

pnm_recovery_report() {
    local selected=$1 directory id blocked=false invalid=0 comma='' count=0
    local -a directories=()
    pnm_recovery_validate_store || return $?
    if [[ -n "$selected" && ! -e "$PNM_STATE_DIR/transactions/$selected" && ! -L "$PNM_STATE_DIR/transactions/$selected" ]]; then
        pnm_error 'Transaction not found.'
        return "$PNM_EXIT_UNAVAILABLE"
    fi
    if ! pnm_tx_assert_no_pending_deployment >/dev/null 2>&1; then blocked=true; fi
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.recovery.v1","writes_blocked":%s,"transactions":[' "$blocked"
    else
        printf 'Writes blocked by transaction evidence: %s\n' "$blocked"
        printf '%-36s %-24s %-18s %s\n' 'Transaction' 'Operation' 'State' 'File/dir changes'
    fi
    if [[ -n "$selected" ]]; then
        directories=("$PNM_STATE_DIR/transactions/$selected")
    else
        directories=("$PNM_STATE_DIR"/transactions/*)
    fi
    for directory in "${directories[@]}"; do
        if [[ -z "$selected" ]]; then [[ -d "$directory" || -L "$directory" ]] || continue; fi
        id=${directory##*/}
        [[ -z "$selected" || "$id" == "$selected" ]] || continue
        [[ "$PNM_OUTPUT_MODE" != json ]] || printf '%s' "$comma"
        if pnm_recovery_render_entry "$id"; then :; else invalid=1; fi
        comma=','
        ((count+=1))
    done
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf ']}\n'
    elif ((count == 0)); then
        printf 'No transaction records.\n'
    fi
    ((invalid == 0)) || return "$PNM_EXIT_CONFIG"
    [[ "$blocked" == false ]] || return "$PNM_EXIT_WARN"
}
