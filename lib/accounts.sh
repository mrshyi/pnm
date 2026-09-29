#!/usr/bin/env bash

declare -ag PNM_ACCOUNTS_CREATED_USERS=()
declare -ag PNM_ACCOUNTS_CREATED_GROUPS=()

pnm_service_account_existing_valid() {
    local account="${1:?service account required}"
    local policy group expected_home expected_shell record username _ uid gid home shell group_record group_gid

    policy="$(pnm_service_account_policy "$account")" || return "$PNM_EXIT_CONFIG"
    IFS='|' read -r group expected_home expected_shell <<<"$policy"
    record="$(getent passwd "$account" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    IFS=: read -r username _ uid gid home shell <<<"$record"
    [[ "$home" == "$expected_home" && "$shell" == "$expected_shell" ]] || return "$PNM_EXIT_CONFIG"
    group_record="$(getent group "$group" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    IFS=: read -r _ _ group_gid _ <<<"$group_record"
    [[ "$gid" == "$group_gid" ]]
}

pnm_service_account_policy() {
    local account="${1:?service account required}"

    case "$account" in
        xray | hysteria) printf '%s|%s|%s\n' "$account" '/nonexistent' '/usr/sbin/nologin' ;;
        *) return 1 ;;
    esac
}

pnm_service_account_state() {
    local account="${1:?service account required}"
    local record username _ uid gid home shell

    pnm_service_account_policy "$account" >/dev/null || return 2
    pnm_command_exists getent || return 2
    record="$(getent passwd "$account" 2>/dev/null)" || return 1
    IFS=: read -r username _ uid gid home shell <<<"$record"
    printf '%s|%s|%s|%s|%s\n' "$username" "$uid" "$gid" "$home" "$shell"
}

pnm_ensure_service_account() {
    local account="${1:?service account required}"
    local policy group expected_home expected_shell record username _ uid gid home shell

    pnm_require_root || return $?
    policy="$(pnm_service_account_policy "$account")" || return "$PNM_EXIT_CONFIG"
    IFS='|' read -r group expected_home expected_shell <<<"$policy"
    pnm_command_exists getent && pnm_command_exists groupadd && pnm_command_exists useradd || return "$PNM_EXIT_UNAVAILABLE"

    if ! getent group "$group" >/dev/null 2>&1; then
        groupadd --system "$group" || return "$PNM_EXIT_SOFTWARE"
    fi
    if record="$(getent passwd "$account" 2>/dev/null)"; then
        pnm_service_account_existing_valid "$account" || {
            pnm_error "Existing service account '$account' does not match PNM policy; refusing to modify it."
            return "$PNM_EXIT_CONFIG"
        }
        return 0
    fi
    useradd --system --gid "$group" --home-dir "$expected_home" --shell "$expected_shell" --no-create-home "$account"
}

pnm_service_accounts_reset() {
    PNM_ACCOUNTS_CREATED_USERS=()
    PNM_ACCOUNTS_CREATED_GROUPS=()
}

pnm_service_accounts_step() {
    local account policy group expected_home expected_shell

    pnm_require_root || return $?
    pnm_command_exists getent && pnm_command_exists groupadd && pnm_command_exists useradd || return "$PNM_EXIT_UNAVAILABLE"
    pnm_service_accounts_reset
    for account in xray hysteria; do
        policy="$(pnm_service_account_policy "$account")" || return "$PNM_EXIT_CONFIG"
        IFS='|' read -r group expected_home expected_shell <<<"$policy"
        if getent passwd "$account" >/dev/null 2>&1; then
            pnm_service_account_existing_valid "$account" || return "$PNM_EXIT_CONFIG"
            continue
        fi
        if ! getent group "$group" >/dev/null 2>&1; then
            pnm_tx_record_account INTENT group "$group" || return $?
            if groupadd --system "$group"; then
                PNM_ACCOUNTS_CREATED_GROUPS+=("$group")
                pnm_tx_record_account APPLIED group "$group" || return $?
            else
                return "$PNM_EXIT_SOFTWARE"
            fi
        fi
        pnm_tx_record_account INTENT user "$account" || return $?
        if useradd --system --gid "$group" --home-dir "$expected_home" --shell "$expected_shell" --no-create-home "$account"; then
            PNM_ACCOUNTS_CREATED_USERS+=("$account")
            pnm_tx_record_account APPLIED user "$account" || return $?
        else
            return "$PNM_EXIT_SOFTWARE"
        fi
    done
}

pnm_service_accounts_rollback() {
    local index account group record members rc=0

    for ((index=${#PNM_ACCOUNTS_CREATED_USERS[@]} - 1; index >= 0; index -= 1)); do
        account="${PNM_ACCOUNTS_CREATED_USERS[$index]}"
        if getent passwd "$account" >/dev/null 2>&1; then
            pnm_service_account_existing_valid "$account" || { rc="$PNM_EXIT_SOFTWARE"; continue; }
            if ps -u "$account" -o pid= 2>/dev/null | awk 'NF {found=1} END {exit(found ? 0 : 1)}'; then
                rc="$PNM_EXIT_SOFTWARE"
                continue
            fi
            if userdel -- "$account"; then
                ((PNM_TX_ACTIVE == 0)) || pnm_tx_record_account RESTORED user "$account" || rc="$PNM_EXIT_SOFTWARE"
            else
                rc="$PNM_EXIT_SOFTWARE"
            fi
        elif ((PNM_TX_ACTIVE == 1)); then
            pnm_tx_record_account RESTORED user "$account" || rc="$PNM_EXIT_SOFTWARE"
        fi
    done
    for ((index=${#PNM_ACCOUNTS_CREATED_GROUPS[@]} - 1; index >= 0; index -= 1)); do
        group="${PNM_ACCOUNTS_CREATED_GROUPS[$index]}"
        if record="$(getent group "$group" 2>/dev/null)"; then
            IFS=: read -r _ _ _ members <<<"$record"
            [[ -z "$members" ]] || { rc="$PNM_EXIT_SOFTWARE"; continue; }
            if groupdel -- "$group"; then
                ((PNM_TX_ACTIVE == 0)) || pnm_tx_record_account RESTORED group "$group" || rc="$PNM_EXIT_SOFTWARE"
            else
                rc="$PNM_EXIT_SOFTWARE"
            fi
        elif ((PNM_TX_ACTIVE == 1)); then
            pnm_tx_record_account RESTORED group "$group" || rc="$PNM_EXIT_SOFTWARE"
        fi
    done
    pnm_service_accounts_reset
    return "$rc"
}
