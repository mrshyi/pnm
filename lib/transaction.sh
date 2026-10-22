#!/usr/bin/env bash

# shellcheck source=deployment-state.sh
source "${BASH_SOURCE[0]%/*}/deployment-state.sh"

PNM_TX_ID=''
PNM_TX_PATH=''
PNM_TX_ACTIVE=0
PNM_TX_COMMITTED=0
PNM_TX_ROLLED_BACK=0
PNM_TX_RECOVERY_REQUIRED=0
PNM_TX_STEP_FAILURE_NAME=''
PNM_TX_STEP_FAILURE_RC=0
PNM_TX_ROLLBACK_FAILURE_RC=0
PNM_TX_DEPLOYMENT_ID='none'
PNM_TX_OPERATION=''
PNM_TX_INSPECT_CORE=''
PNM_TX_INSPECT_UNIT=''
PNM_TX_INSPECT_PRE_ACTIVE=''
PNM_TX_INSPECT_PRE_ENABLED=''
declare -ag PNM_TX_ROLLBACKS=()
declare -ag PNM_TX_WRITTEN_PATHS=()
declare -ag PNM_TX_WRITTEN_LABELS=()
declare -ag PNM_TX_WRITTEN_HASHES=()
declare -ag PNM_TX_WRITTEN_ATTRIBUTES=()
declare -ag PNM_TX_ACCOUNT_KEYS=()
declare -ag PNM_TX_ACCOUNT_STATES=()
declare -ag PNM_TX_DIRECTORY_PATHS=()
declare -ag PNM_TX_DIRECTORY_ORIGINAL=()
declare -ag PNM_TX_DIRECTORY_EXPECTED=()
declare -ag PNM_TX_DIRECTORY_IDENTITIES=()

pnm_tx_new_id() {
    if [[ -n "${PNM_TX_ID_OVERRIDE:-}" ]]; then
        printf '%s\n' "$PNM_TX_ID_OVERRIDE"
        return 0
    fi
    local transaction_uuid

    [[ -r /proc/sys/kernel/random/uuid && ! -L /proc/sys/kernel/random/uuid ]] || return "$PNM_EXIT_UNAVAILABLE"
    IFS= read -r transaction_uuid </proc/sys/kernel/random/uuid || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$transaction_uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || return "$PNM_EXIT_UNAVAILABLE"
    printf 'tx-%s\n' "${transaction_uuid//-/}"
}

pnm_tx_journal() {
    local phase="${1:?transaction phase required}"
    local detail="${2-}"

    ((PNM_TX_ACTIVE == 1 && PNM_DRY_RUN == 0)) || return 0
    printf '%s\t%s\t%s\n' "$(pnm_now_utc)" "$phase" "$(pnm_one_line "$detail")" >>"$PNM_TX_PATH/journal.tsv" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_manifest_init() {
    local manifest="$PNM_TX_PATH/changes.tsv"

    : >"$manifest" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$manifest" || return "$PNM_EXIT_NOPERM"
}

pnm_tx_record_core_state() {
    local core="${1:?core id required}" unit="${2:?systemd unit required}"
    local active="${3:?prior active state required}" enabled="${4:?prior enabled state required}"
    local expected_unit temporary

    ((PNM_TX_ACTIVE == 1 && PNM_DRY_RUN == 0)) || return "$PNM_EXIT_SOFTWARE"
    case "$core" in
        xray) expected_unit=xray.service ;;
        hysteria2) expected_unit=hysteria-server.service ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
    [[ "$unit" == "$expected_unit" && "$PNM_TX_OPERATION" == "core-lifecycle-$core" ]] || return "$PNM_EXIT_CONFIG"
    [[ "$active" == active || "$active" == inactive ]] || return "$PNM_EXIT_CONFIG"
    [[ "$enabled" == enabled || "$enabled" == disabled ]] || return "$PNM_EXIT_CONFIG"
    temporary="$PNM_TX_PATH/.core-state.tmp"
    printf 'SCHEMA_VERSION=1\nCORE=%s\nUNIT=%s\nPRE_ACTIVE=%s\nPRE_ENABLED=%s\n' \
        "$core" "$unit" "$active" "$enabled" >"$temporary" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$temporary" || { rm -f -- "$temporary"; return "$PNM_EXIT_NOPERM"; }
    mv -f -- "$temporary" "$PNM_TX_PATH/core-state.env" || { rm -f -- "$temporary"; return "$PNM_EXIT_CANTCREAT"; }
    pnm_tx_journal BASELINE "core=$core unit=$unit active=$active enabled=$enabled" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_record_account() {
    local state="${1:?account receipt state required}" kind="${2:?account object kind required}"
    local name="${3:?account object name required}" receipt="$PNM_TX_PATH/accounts.tsv" owner_mode

    ((PNM_TX_ACTIVE == 1 && PNM_DRY_RUN == 0)) || return "$PNM_EXIT_SOFTWARE"
    [[ ( "$PNM_TX_OPERATION" == sandbox-install || "$PNM_TX_OPERATION" == deployment ) && "$state" =~ ^(INTENT|APPLIED|RESTORED)$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "$kind" == group || "$kind" == user ]] || return "$PNM_EXIT_CONFIG"
    [[ "$name" == xray || "$name" == hysteria ]] || return "$PNM_EXIT_CONFIG"
    if [[ -e "$receipt" || -L "$receipt" ]]; then
        [[ -f "$receipt" && ! -L "$receipt" ]] || return "$PNM_EXIT_CONFIG"
        owner_mode="$(stat -c '%a|%u' -- "$receipt" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_NOPERM"
    else
        [[ "$state" == INTENT ]] || return "$PNM_EXIT_CONFIG"
        : >"$receipt" || return "$PNM_EXIT_CANTCREAT"
        chmod 0600 -- "$receipt" || return "$PNM_EXIT_NOPERM"
    fi
    printf '%s\t%s\t%s\n' "$state" "$kind" "$name" >>"$receipt" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_account_receipt_validate() {
    local receipt="${1:?account receipt path required}" state kind name extra key index
    local -A seen=() index_by_key=()

    PNM_TX_ACCOUNT_KEYS=()
    PNM_TX_ACCOUNT_STATES=()
    [[ -f "$receipt" && ! -L "$receipt" ]] || return "$PNM_EXIT_CONFIG"
    while IFS=$'\t' read -r state kind name extra || [[ -n "$state$kind$name$extra" ]]; do
        [[ -z "$extra" ]] || return "$PNM_EXIT_CONFIG"
        [[ "$state" =~ ^(INTENT|APPLIED|RESTORED)$ && ( "$kind" == group || "$kind" == user ) && ( "$name" == xray || "$name" == hysteria ) ]] || return "$PNM_EXIT_CONFIG"
        key="$kind:$name"
        case "$state" in
            INTENT)
                [[ -z "${seen[$key]-}" ]] || return "$PNM_EXIT_CONFIG"
                seen[$key]=INTENT
                index_by_key[$key]="${#PNM_TX_ACCOUNT_KEYS[@]}"
                PNM_TX_ACCOUNT_KEYS+=("$key")
                PNM_TX_ACCOUNT_STATES+=(INTENT)
                ;;
            APPLIED)
                [[ "${seen[$key]-}" == INTENT ]] || return "$PNM_EXIT_CONFIG"
                seen[$key]=APPLIED
                index="${index_by_key[$key]}"
                PNM_TX_ACCOUNT_STATES[index]=APPLIED
                ;;
            RESTORED)
                [[ "${seen[$key]-}" == INTENT || "${seen[$key]-}" == APPLIED ]] || return "$PNM_EXIT_CONFIG"
                seen[$key]=RESTORED
                index="${index_by_key[$key]}"
                PNM_TX_ACCOUNT_STATES[index]=RESTORED
                ;;
        esac
    done <"$receipt"
}

pnm_tx_manifest_append() {
    local state="${1:?manifest state required}" label="${2:?snapshot label required}"
    local destination="${3:?destination path required}" original_state="${4:?original state required}"
    local original_mode="${5:?original mode required}" expected_hash="${6:?expected hash required}"
    local encoded_path manifest

    ((PNM_TX_ACTIVE == 1 && PNM_DRY_RUN == 0)) || return 0
    [[ "$state" =~ ^(INTENT|APPLIED|RESTORED)$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "$destination" == /* && "$destination" != *$'\n'* && "$destination" != *$'\t'* ]] || return "$PNM_EXIT_CONFIG"
    [[ "$original_state" =~ ^(PRESENT|MISSING)$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "$original_mode" == MISSING || "$original_mode" =~ ^[0-7]{1,4}$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "$expected_hash" =~ ^[a-f0-9]{64}$ ]] || return "$PNM_EXIT_CONFIG"
    encoded_path="$(printf '%s' "$destination" | base64 -w0)" || return "$PNM_EXIT_SOFTWARE"
    manifest="$PNM_TX_PATH/changes.tsv"
    [[ -f "$manifest" && ! -L "$manifest" ]] || return "$PNM_EXIT_CONFIG"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "$label" "$encoded_path" \
        "$original_state" "$original_mode" "$expected_hash" >>"$manifest" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_load_for_inspect() {
    local transaction_id="${1:?transaction id required}" transaction_dir owner_mode
    local metadata journal manifest timestamp event detail line_count=0 begin_count=0 terminal=''
    local state label encoded_path original_state original_mode expected_hash decoded_path
    local current_label='' current_path='' current_state='' current_mode='' current_hash='' current_stage=''
    local -A metadata_values=() core_values=()
    local -a change_labels=() change_states=() change_paths=() change_original_states=() change_modes=() change_hashes=()
    local index snapshot_root snapshot_owner directory_changes=0 marker_committed=0 commit_uncertain=0
    local -A seen_labels=() change_records=() change_indexes=()

    PNM_TX_ACCOUNT_KEYS=()
    PNM_TX_ACCOUNT_STATES=()
    [[ "$transaction_id" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || return "$PNM_EXIT_USAGE"
    transaction_dir="$PNM_STATE_DIR/transactions/$transaction_id"
    [[ -e "$PNM_STATE_DIR" || -L "$PNM_STATE_DIR" ]] || return "$PNM_EXIT_WARN"
    [[ ! -L "$PNM_STATE_DIR" && -d "$PNM_STATE_DIR" ]] || return "$PNM_EXIT_CONFIG"
    owner_mode="$(stat -c '%a|%u' -- "$PNM_STATE_DIR" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    [[ -d "$transaction_dir" && ! -L "$transaction_dir" ]] || return "$PNM_EXIT_WARN"
    owner_mode="$(stat -c '%a|%u' -- "$transaction_dir" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    metadata="$transaction_dir/metadata.env"
    journal="$transaction_dir/journal.tsv"
    manifest="$transaction_dir/changes.tsv"
    for decoded_path in "$metadata" "$manifest"; do
        [[ -f "$decoded_path" && ! -L "$decoded_path" ]] || return "$PNM_EXIT_CONFIG"
        owner_mode="$(stat -c '%a|%u' -- "$decoded_path" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    done
    pnm_config_load "$metadata" metadata_values SCHEMA_VERSION TRANSACTION_ID OPERATION DEPLOYMENT_ID || return "$PNM_EXIT_CONFIG"
    [[ "${metadata_values[SCHEMA_VERSION]-}" =~ ^[12]$ && "${metadata_values[TRANSACTION_ID]-}" == "$transaction_id" ]] || return "$PNM_EXIT_CONFIG"
    pnm_tx_inspect_directories "$transaction_dir" "${metadata_values[SCHEMA_VERSION]}" directory_changes || return $?
    [[ "${metadata_values[OPERATION]-}" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return "$PNM_EXIT_CONFIG"
    [[ "${metadata_values[DEPLOYMENT_ID]-}" == none || "${metadata_values[DEPLOYMENT_ID]-}" =~ ^deploy-[A-Za-z0-9._-]{1,80}$ ]] || return "$PNM_EXIT_CONFIG"
    if [[ "${metadata_values[OPERATION]}" == deployment ]]; then
        [[ "${metadata_values[SCHEMA_VERSION]}" == 2 ]] || return "$PNM_EXIT_CONFIG"
        if [[ -e "$transaction_dir/commit.env" || -L "$transaction_dir/commit.env" ]]; then
            pnm_tx_validate_deployment_record "$transaction_dir/deployment.env" || return $?
            pnm_tx_deployment_marker verify "$transaction_dir" "$transaction_id" "${metadata_values[DEPLOYMENT_ID]}" || return "$PNM_EXIT_CONFIG"
            marker_committed=1
            if [[ -e "$transaction_dir/commit-uncertain.env" || -L "$transaction_dir/commit-uncertain.env" ]]; then
                local -A uncertain=()
                [[ ! -L "$transaction_dir/commit-uncertain.env" && "$(stat -c '%a|%u' -- "$transaction_dir/commit-uncertain.env")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
                pnm_config_load "$transaction_dir/commit-uncertain.env" uncertain SCHEMA_VERSION ORIGINAL_RC || return "$PNM_EXIT_CONFIG"
                [[ "${uncertain[SCHEMA_VERSION]-}" == 1 && "${uncertain[ORIGINAL_RC]-}" =~ ^[0-9]+$ ]] || return "$PNM_EXIT_CONFIG"
                commit_uncertain=1
            fi
        fi
    fi
    PNM_TX_INSPECT_CORE=''
    PNM_TX_INSPECT_UNIT=''
    PNM_TX_INSPECT_PRE_ACTIVE=''
    PNM_TX_INSPECT_PRE_ENABLED=''
    if [[ "${metadata_values[OPERATION]}" == core-lifecycle-xray || "${metadata_values[OPERATION]}" == core-lifecycle-hysteria2 ]]; then
        local core_state_file="$transaction_dir/core-state.env" expected_core expected_unit
        [[ -f "$core_state_file" && ! -L "$core_state_file" ]] || return "$PNM_EXIT_CONFIG"
        owner_mode="$(stat -c '%a|%u' -- "$core_state_file" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
        pnm_config_load "$core_state_file" core_values SCHEMA_VERSION CORE UNIT PRE_ACTIVE PRE_ENABLED || return "$PNM_EXIT_CONFIG"
        [[ "${core_values[SCHEMA_VERSION]-}" == 1 ]] || return "$PNM_EXIT_CONFIG"
        expected_core="${metadata_values[OPERATION]#core-lifecycle-}"
        case "$expected_core" in
            xray) expected_unit=xray.service ;;
            hysteria2) expected_unit=hysteria-server.service ;;
            *) return "$PNM_EXIT_CONFIG" ;;
        esac
        [[ "${core_values[CORE]-}" == "$expected_core" && "${core_values[UNIT]-}" == "$expected_unit" ]] || return "$PNM_EXIT_CONFIG"
        [[ "${core_values[PRE_ACTIVE]-}" == active || "${core_values[PRE_ACTIVE]-}" == inactive ]] || return "$PNM_EXIT_CONFIG"
        [[ "${core_values[PRE_ENABLED]-}" == enabled || "${core_values[PRE_ENABLED]-}" == disabled ]] || return "$PNM_EXIT_CONFIG"
        PNM_TX_INSPECT_CORE="${core_values[CORE]}"
        PNM_TX_INSPECT_UNIT="${core_values[UNIT]}"
        PNM_TX_INSPECT_PRE_ACTIVE="${core_values[PRE_ACTIVE]}"
        PNM_TX_INSPECT_PRE_ENABLED="${core_values[PRE_ENABLED]}"
    elif [[ -e "$transaction_dir/core-state.env" || -L "$transaction_dir/core-state.env" ]]; then
        return "$PNM_EXIT_CONFIG"
    fi
    [[ ! -e "$transaction_dir/ufw-rules.tsv" && ! -L "$transaction_dir/ufw-rules.tsv" ]] || return "$PNM_EXIT_CONFIG"
    if [[ "${metadata_values[OPERATION]}" == sandbox-install || "${metadata_values[OPERATION]}" == deployment ]]; then
        local account_receipt="$transaction_dir/accounts.tsv"
        if [[ -e "$account_receipt" || -L "$account_receipt" ]]; then
            owner_mode="$(stat -c '%a|%u' -- "$account_receipt" 2>/dev/null || printf '000|x')"
            [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
            pnm_tx_account_receipt_validate "$account_receipt" || return "$PNM_EXIT_CONFIG"
        else
            PNM_TX_ACCOUNT_KEYS=()
            PNM_TX_ACCOUNT_STATES=()
        fi
    elif [[ -e "$transaction_dir/accounts.tsv" || -L "$transaction_dir/accounts.tsv" ]]; then
        return "$PNM_EXIT_CONFIG"
    fi
    if ((marker_committed == 0)); then
    [[ -f "$journal" && ! -L "$journal" && "$(stat -c '%a|%u' -- "$journal")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    while IFS=$'\t' read -r timestamp event detail || [[ -n "$timestamp$event$detail" ]]; do
        [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$event" =~ ^[A-Z_]+$ ]] || return "$PNM_EXIT_CONFIG"
        [[ "$terminal" != COMMIT && "$terminal" != ROLLED_BACK ]] || return "$PNM_EXIT_CONFIG"
        if [[ "$terminal" == ABANDONED || "$terminal" == RECOVERY_REQUIRED ]]; then
            case "$event" in
                RECOVERY_REQUIRED | ROLLED_BACK) ;;
                *) return "$PNM_EXIT_CONFIG" ;;
            esac
        fi
        case "$event" in
            BEGIN)
                ((begin_count == 0)) || return "$PNM_EXIT_CONFIG"
                [[ "$detail" == "operation=${metadata_values[OPERATION]} deployment_id=${metadata_values[DEPLOYMENT_ID]}" ]] || return "$PNM_EXIT_CONFIG"
                begin_count=1
                ;;
            COMMIT)
                ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
                [[ -z "$terminal" ]] || return "$PNM_EXIT_CONFIG"
                terminal=COMMIT
                ;;
            ROLLED_BACK)
                ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
                [[ "$terminal" == ROLLBACK_COMPLETE || "$terminal" == RECOVERY_ROLLBACK_COMPLETE || "$terminal" == RECOVERY_REQUIRED || "$terminal" == ABANDONED ]] || return "$PNM_EXIT_CONFIG"
                terminal=ROLLED_BACK
                ;;
            ROLLBACK_COMPLETE)
                ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
                [[ -z "$terminal" || "$terminal" == RECOVERY_REQUIRED || "$terminal" == ABANDONED ]] || return "$PNM_EXIT_CONFIG"
                terminal="$event"
                ;;
            RECOVERY_REQUIRED)
                ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
                [[ "$terminal" != COMMIT && "$terminal" != ROLLED_BACK && "$terminal" != ROLLBACK_COMPLETE ]] || return "$PNM_EXIT_CONFIG"
                terminal=RECOVERY_REQUIRED
                ;;
            ABANDONED)
                ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
                [[ -z "$terminal" ]] || return "$PNM_EXIT_CONFIG"
                terminal=ABANDONED
                ;;
            *) ((begin_count == 1)) || return "$PNM_EXIT_CONFIG" ;;
        esac
        ((line_count += 1))
    done <"$journal"
    ((begin_count == 1)) || return "$PNM_EXIT_CONFIG"
    if [[ "${metadata_values[OPERATION]}" == deployment && "$terminal" == COMMIT ]]; then
        return "$PNM_EXIT_CONFIG"
    fi
    else
        terminal=COMMIT
    fi
    while IFS=$'\t' read -r state label encoded_path original_state original_mode expected_hash || [[ -n "$state$label$encoded_path$original_state$original_mode$expected_hash" ]]; do
        [[ "$state" =~ ^(INTENT|APPLIED|RESTORED)$ && "$label" =~ ^[A-Za-z0-9._-]+$ ]] || return "$PNM_EXIT_CONFIG"
        [[ "$original_state" =~ ^(PRESENT|MISSING)$ && ( "$original_mode" == MISSING || "$original_mode" =~ ^[0-7]{1,4}$ ) ]] || return "$PNM_EXIT_CONFIG"
        [[ "$expected_hash" =~ ^[a-f0-9]{64}$ ]] || return "$PNM_EXIT_CONFIG"
        decoded_path="$(printf '%s' "$encoded_path" | base64 -d 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
        [[ "$decoded_path" == /* && "$decoded_path" != *$'\n'* && "$decoded_path" != *$'\t'* ]] || return "$PNM_EXIT_CONFIG"
        [[ "$(printf '%s' "$decoded_path" | base64 -w0)" == "$encoded_path" ]] || return "$PNM_EXIT_CONFIG"
        case "$state" in
            INTENT)
                [[ -z "${seen_labels[$label]-}" ]] || return "$PNM_EXIT_CONFIG"
                seen_labels[$label]=intent
                change_records[$label]="$encoded_path|$original_state|$original_mode|$expected_hash"
                change_indexes[$label]="${#change_labels[@]}"
                current_label="$label" current_path="$decoded_path" current_state="$original_state" current_mode="$original_mode" current_hash="$expected_hash" current_stage=INTENT
                change_labels+=("$label") change_states+=(intent) change_paths+=("$decoded_path") change_original_states+=("$original_state") change_modes+=("$original_mode") change_hashes+=("$expected_hash")
                ;;
            APPLIED)
                [[ "${seen_labels[$label]-}" == intent && "$current_label" == "$label" && "$current_path" == "$decoded_path" && "$current_state" == "$original_state" && "$current_mode" == "$original_mode" && "$current_hash" == "$expected_hash" && "$current_stage" == INTENT ]] || return "$PNM_EXIT_CONFIG"
                seen_labels[$label]=applied
                current_stage=APPLIED
                change_states[${change_indexes[$label]}]=applied
                ;;
            RESTORED)
                # Recovery runs in reverse order, independently of the last write.
                [[ ( "${seen_labels[$label]-}" == applied || "${seen_labels[$label]-}" == intent ) &&
                    "${change_records[$label]-}" == "$encoded_path|$original_state|$original_mode|$expected_hash" ]] || return "$PNM_EXIT_CONFIG"
                seen_labels[$label]=restored
                current_stage=RESTORED
                change_states[${change_indexes[$label]}]=restored
                ;;
        esac
        if [[ "$original_state" == PRESENT ]]; then
            [[ -f "$transaction_dir/snapshots/$label" && ! -L "$transaction_dir/snapshots/$label" && -f "$transaction_dir/snapshots/$label.state" && ! -L "$transaction_dir/snapshots/$label.state" ]] || return "$PNM_EXIT_CONFIG"
            local snapshot_info
            snapshot_info="$(pnm_tx_read_snapshot_metadata "$transaction_dir/snapshots/$label.state" "${metadata_values[SCHEMA_VERSION]}")" || return $?
            [[ "$snapshot_info" == "PRESENT|$original_mode|"* ]] || return "$PNM_EXIT_CONFIG"
            [[ "$(stat -c '%a' -- "$transaction_dir/snapshots/$label")" == 600 ]] || return "$PNM_EXIT_CONFIG"
        else
            [[ "$(pnm_tx_read_snapshot_metadata "$transaction_dir/snapshots/$label.state" "${metadata_values[SCHEMA_VERSION]}")" == 'MISSING|MISSING|MISSING|MISSING' ]] || return "$PNM_EXIT_CONFIG"
        fi
    done <"$manifest"
    snapshot_root="$transaction_dir/snapshots"
    if ((${#change_labels[@]} > 0)); then
        [[ -d "$snapshot_root" && ! -L "$snapshot_root" ]] || return "$PNM_EXIT_CONFIG"
        snapshot_owner="$(stat -c '%a|%u' -- "$snapshot_root" 2>/dev/null || printf '000|x')"
        [[ "$snapshot_owner" == "700|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    fi
    for index in "${!change_labels[@]}"; do
        if [[ "${change_original_states[index]}" == PRESENT ]]; then
            owner_mode="$(stat -c '%a|%u' -- "$snapshot_root/${change_labels[index]}" 2>/dev/null || printf '000|x')"
            [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
            [[ "$(pnm_tx_file_sha256 "$snapshot_root/${change_labels[index]}")" != UNSAFE ]] || return "$PNM_EXIT_CONFIG"
        fi
        owner_mode="$(stat -c '%a|%u' -- "$snapshot_root/${change_labels[index]}.state" 2>/dev/null || printf '000|x')"
        [[ "$owner_mode" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    done
    case "$terminal" in
        COMMIT) PNM_TX_INSPECT_STATE=COMMITTED ;;
        ROLLED_BACK | ROLLBACK_COMPLETE) PNM_TX_INSPECT_STATE=ROLLED_BACK ;;
        RECOVERY_REQUIRED) PNM_TX_INSPECT_STATE=RECOVERY_REQUIRED ;;
        ABANDONED) PNM_TX_INSPECT_STATE=ABANDONED ;;
        '') PNM_TX_INSPECT_STATE=INTERRUPTED ;;
    esac
    ((commit_uncertain == 0)) || PNM_TX_INSPECT_STATE=RECOVERY_REQUIRED
    if [[ "${metadata_values[OPERATION]}" == deployment ]] && ((marker_committed == 0)); then
        if pnm_tx_validate_deployment_record "$transaction_dir/deployment.env"; then :; else
            # Baseline publication may fail before the first managed mutation.
            # A verified empty terminal rollback needs no recovery baseline.
            [[ "$PNM_TX_INSPECT_STATE" == ROLLED_BACK && ! -s "$manifest" &&
                ! -s "$transaction_dir/directories.tsv" && ! -s "$transaction_dir/accounts.tsv" ]] || return "$PNM_EXIT_CONFIG"
        fi
    fi
    PNM_TX_INSPECT_ID="$transaction_id"
    PNM_TX_INSPECT_OPERATION="${metadata_values[OPERATION]}"
    PNM_TX_INSPECT_DEPLOYMENT_ID="${metadata_values[DEPLOYMENT_ID]}"
    PNM_TX_INSPECT_CHANGES="$directory_changes"
    for label in "${!seen_labels[@]}"; do [[ "${seen_labels[$label]}" == restored ]] || ((PNM_TX_INSPECT_CHANGES += 1)); done
}

pnm_tx_begin() {
    local operation="${1:?transaction operation required}"
    local transactions_dir metadata rc owner_mode

    ((PNM_TX_ACTIVE == 0)) || return "$PNM_EXIT_SOFTWARE"
    pnm_lock_acquire exclusive || return $?
    if pnm_tx_assert_no_pending_deployment; then :; else
        rc=$?; pnm_lock_release; return "$rc"
    fi
    if PNM_TX_ID="$(pnm_tx_new_id)"; then :; else
        rc=$?
        pnm_lock_release
        return "$rc"
    fi
    PNM_TX_COMMITTED=0
    PNM_TX_ROLLED_BACK=0
    PNM_TX_RECOVERY_REQUIRED=0
    PNM_TX_STEP_FAILURE_NAME=''
    PNM_TX_STEP_FAILURE_RC=0
    PNM_TX_ROLLBACK_FAILURE_RC=0
    PNM_TX_DEPLOYMENT_ID='none'
    PNM_TX_OPERATION=''
    PNM_TX_OPERATION="$operation"
    PNM_TX_ROLLBACKS=()
    PNM_TX_WRITTEN_PATHS=()
    PNM_TX_WRITTEN_LABELS=()
    PNM_TX_WRITTEN_HASHES=()
    PNM_TX_WRITTEN_ATTRIBUTES=()
    PNM_TX_ACCOUNT_KEYS=()
    PNM_TX_ACCOUNT_STATES=()
    PNM_TX_DIRECTORY_PATHS=()
    PNM_TX_DIRECTORY_ORIGINAL=()
    PNM_TX_DIRECTORY_EXPECTED=()
    PNM_TX_DIRECTORY_IDENTITIES=()

    if ((PNM_DRY_RUN == 1)); then
        PNM_TX_PATH="dry-run:$PNM_TX_ID"
        PNM_TX_ACTIVE=1
        return 0
    fi

    transactions_dir="$PNM_STATE_DIR/transactions"
    [[ "$operation" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    [[ "$PNM_TX_ID" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    [[ "$PNM_STATE_DIR" == /* && "$PNM_STATE_DIR" != / ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    pnm_mkdir_mode 0700 "$PNM_STATE_DIR" || { pnm_lock_release; return "$PNM_EXIT_CANTCREAT"; }
    [[ -d "$PNM_STATE_DIR" && ! -L "$PNM_STATE_DIR" ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    owner_mode="$(stat -c '%a|%u' -- "$PNM_STATE_DIR" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || { pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    pnm_mkdir_mode 0700 "$transactions_dir" || {
        pnm_lock_release
        return "$PNM_EXIT_CANTCREAT"
    }
    [[ -d "$transactions_dir" && ! -L "$transactions_dir" ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    owner_mode="$(stat -c '%a|%u' -- "$transactions_dir" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || { pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    PNM_TX_PATH="$transactions_dir/$PNM_TX_ID"
    mkdir -m 0700 -- "$PNM_TX_PATH" || {
        pnm_lock_release
        return "$PNM_EXIT_CANTCREAT"
    }
    owner_mode="$(stat -c '%a|%u' -- "$PNM_TX_PATH" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || { rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    PNM_TX_DEPLOYMENT_ID='none'
    if (( ${PNM_DEPLOY_ACTIVE:-0} == 1 )) && [[ "${PNM_DEPLOY_ID:-}" =~ ^deploy-[A-Za-z0-9._-]{1,80}$ ]]; then
        PNM_TX_DEPLOYMENT_ID="$PNM_DEPLOY_ID"
    fi
    metadata="$PNM_TX_PATH/metadata.env"
    if ! printf 'SCHEMA_VERSION=2\nTRANSACTION_ID=%s\nOPERATION=%s\nDEPLOYMENT_ID=%s\n' \
        "$PNM_TX_ID" "$operation" "$PNM_TX_DEPLOYMENT_ID" >"$metadata"; then
        rm -rf -- "$PNM_TX_PATH"
        pnm_lock_release
        return "$PNM_EXIT_CANTCREAT"
    fi
    chmod 0600 -- "$metadata" || { rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    : >"$PNM_TX_PATH/journal.tsv" || { rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_CANTCREAT"; }
    chmod 0600 -- "$PNM_TX_PATH/journal.tsv" || { rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    PNM_TX_ACTIVE=1
    pnm_tx_manifest_init || { PNM_TX_ACTIVE=0; rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_CANTCREAT"; }
    (umask 077; : >"$PNM_TX_PATH/directories.tsv") || {
        PNM_TX_ACTIVE=0; rm -rf -- "$PNM_TX_PATH"; pnm_lock_release; return "$PNM_EXIT_CANTCREAT";
    }
    if ! pnm_tx_journal BEGIN "operation=$operation deployment_id=$PNM_TX_DEPLOYMENT_ID"; then
        PNM_TX_ACTIVE=0
        rm -rf -- "$PNM_TX_PATH"
        PNM_TX_PATH=''
        PNM_TX_ID=''
        pnm_lock_release
        return "$PNM_EXIT_CANTCREAT"
    fi
}

pnm_tx_add_rollback() {
    local rollback_function="${1:?rollback function required}"

    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    PNM_TX_ROLLBACKS+=("$rollback_function")
}

pnm_tx_file_sha256() {
    local path="${1:?transaction file required}"
    local digest

    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'MISSING\n'
        return 0
    fi
    [[ -f "$path" && ! -L "$path" ]] || {
        printf 'UNSAFE\n'
        return "$PNM_EXIT_CONFIG"
    }
    digest="$(sha256sum -- "$path" 2>/dev/null | awk '{print $1}')" || return "$PNM_EXIT_SOFTWARE"
    printf '%s\n' "$digest"
}

pnm_tx_require_filesystem_schema() {
    local -A filesystem_metadata=()
    pnm_validate_managed_path "$PNM_TX_PATH/metadata.env" || return $?
    [[ "$(stat -c '%a|%u' -- "$PNM_TX_PATH/metadata.env")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    pnm_config_load "$PNM_TX_PATH/metadata.env" filesystem_metadata SCHEMA_VERSION TRANSACTION_ID OPERATION DEPLOYMENT_ID || return "$PNM_EXIT_CONFIG"
    [[ "${filesystem_metadata[SCHEMA_VERSION]-}" == 2 && "${filesystem_metadata[TRANSACTION_ID]-}" == "$PNM_TX_ID" &&
        "${filesystem_metadata[OPERATION]-}" == "$PNM_TX_OPERATION" ]] || return "$PNM_EXIT_CONFIG"
}

# Schema 1 remains inspectable; it has no ownership evidence and is read-only.
pnm_tx_read_snapshot_metadata() {
    local metadata="$1" schema="$2" value
    [[ -f "$metadata" && ! -L "$metadata" && "$(stat -c '%a|%u' -- "$metadata")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    [[ "$(wc -l <"$metadata")" == 1 ]] || return "$PNM_EXIT_CONFIG"
    value="$(<"$metadata")"
    case "$schema:$value" in
        1:MISSING\|MISSING | 2:MISSING\|MISSING\|MISSING\|MISSING)
            printf 'MISSING|MISSING|MISSING|MISSING\n' ;;
        *)
            if [[ "$schema" == 1 && "$value" =~ ^PRESENT\|[0-7]{1,4}$ ]]; then
                printf '%s|UNKNOWN|UNKNOWN\n' "$value"
            elif [[ "$schema" == 2 && "$value" =~ ^PRESENT\|[0-7]{1,4}\|[0-9]+\|[0-9]+$ ]]; then
                printf '%s\n' "$value"
            else
                return "$PNM_EXIT_CONFIG"
            fi ;;
    esac
}

pnm_tx_directory_receipt() {
    local event="$1" path="$2" original="$3" expected="$4" identity="$5" encoded receipt
    receipt="$PNM_TX_PATH/directories.tsv"
    [[ -f "$receipt" && ! -L "$receipt" && "$(stat -c '%a|%u' -- "$receipt")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    encoded="$(printf '%s' "$path" | base64 -w0)" || return "$PNM_EXIT_SOFTWARE"
    printf '%s\t%s\t%s\t%s\t%s\n' "$event" "$encoded" "$original" "$expected" "$identity" >>"$receipt" || return "$PNM_EXIT_CANTCREAT"
}

# Persist creation intent before mkdir/chmod, including missing intermediate dirs.
pnm_tx_prepare_directory() {
    local path="${1:?directory required}" mode="${2:--}" parent original expected identity index rc=0 create_mode
    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    ((PNM_DRY_RUN == 0)) || return 0
    pnm_tx_require_filesystem_schema || return $?
    pnm_validate_managed_path "$path" || return $?
    [[ "$mode" == - || "$mode" =~ ^[0-7]{3,4}$ ]] || return "$PNM_EXIT_CONFIG"
    [[ ! "$path" -ef / ]] || return "$PNM_EXIT_CONFIG"
    while [[ "$path" == */ ]]; do path="${path%/}"; done
    for index in "${!PNM_TX_DIRECTORY_PATHS[@]}"; do
        if [[ "${PNM_TX_DIRECTORY_PATHS[index]}" == "$path" ]]; then
            # Never take a second baseline after this operation has changed a path.
            [[ "$mode" == - || "${PNM_TX_DIRECTORY_EXPECTED[index]%%|*}" == "${mode#0}" ]] || return "$PNM_EXIT_CONFIG"
            return 0
        fi
    done
    if [[ -e "$path" ]]; then
        [[ -d "$path" ]] || return "$PNM_EXIT_CONFIG"
        [[ "$mode" != - ]] || return 0
        original="$(stat -c '%a|%u|%g' -- "$path")" || return "$PNM_EXIT_CONFIG"
        identity="$(stat -c '%d:%i' -- "$path")" || return "$PNM_EXIT_CONFIG"
    else
        parent="$(dirname -- "$path")"
        if [[ ! -d "$parent" ]]; then
            pnm_tx_prepare_directory "$parent" - || return $?
        fi
        original=MISSING identity=MISSING
    fi
    pnm_tx_directory_receipt INTENT "$path" "$original" PENDING "$identity" || return $?
    index="${#PNM_TX_DIRECTORY_PATHS[@]}"
    PNM_TX_DIRECTORY_PATHS+=("$path")
    PNM_TX_DIRECTORY_ORIGINAL+=("$original")
    PNM_TX_DIRECTORY_EXPECTED+=("$original")
    PNM_TX_DIRECTORY_IDENTITIES+=("$identity")
    if [[ "$original" == MISSING ]]; then
        create_mode="$mode"
        [[ "$create_mode" != - ]] || create_mode=0755
        (umask 022; mkdir -m "$create_mode" -- "$path") || rc="$PNM_EXIT_CANTCREAT"
    elif ! chmod "$mode" -- "$path"; then
        rc="$PNM_EXIT_NOPERM"
    fi
    # Capture the actual result even if chmod or a later receipt write fails.
    if [[ -d "$path" && ! -L "$path" ]]; then
        expected="$(stat -c '%a|%u|%g' -- "$path")" || return "$PNM_EXIT_CONFIG"
        identity="$(stat -c '%d:%i' -- "$path")" || return "$PNM_EXIT_CONFIG"
        PNM_TX_DIRECTORY_EXPECTED[index]="$expected"
        PNM_TX_DIRECTORY_IDENTITIES[index]="$identity"
        pnm_tx_directory_receipt APPLIED "$path" "$original" "$expected" "$identity" || return $?
    fi
    return "$rc"
}

pnm_tx_restore_directories() {
    local index path original expected identity mode uid gid
    for ((index=${#PNM_TX_DIRECTORY_PATHS[@]} - 1; index >= 0; index -= 1)); do
        pnm_tx_require_filesystem_schema || return $?
        path="${PNM_TX_DIRECTORY_PATHS[index]}"
        original="${PNM_TX_DIRECTORY_ORIGINAL[index]}"
        expected="${PNM_TX_DIRECTORY_EXPECTED[index]}"
        identity="${PNM_TX_DIRECTORY_IDENTITIES[index]}"
        pnm_validate_managed_path "$path" || return $?
        if [[ "$original" == MISSING && ! -e "$path" ]]; then
            : # mkdir failed before creating this directory.
        else
            [[ -d "$path" && "$(stat -c '%d:%i' -- "$path")" == "$identity" &&
                "$(stat -c '%a|%u|%g' -- "$path")" == "$expected" ]] || return "$PNM_EXIT_SOFTWARE"
            if [[ "$original" == MISSING ]]; then
                # rmdir refuses foreign contents; never recursively remove resources.
                rmdir -- "$path" || return "$PNM_EXIT_SOFTWARE"
            else
                IFS='|' read -r mode uid gid <<<"$original"
                chown -- "+$uid:+$gid" "$path" || return "$PNM_EXIT_NOPERM"
                chmod "$mode" -- "$path" || return "$PNM_EXIT_NOPERM"
                [[ "$(stat -c '%a|%u|%g' -- "$path")" == "$original" ]] || return "$PNM_EXIT_SOFTWARE"
            fi
        fi
        pnm_tx_directory_receipt RESTORED "$path" "$original" "$expected" "$identity" || return $?
    done
}

pnm_tx_inspect_directories() {
    local directory="$1" schema="$2" result_name="$3" receipt="$1/directories.tsv"
    local event encoded original expected identity extra path key
    local attributes_pattern='^[0-7]{1,4}\|[0-9]+\|[0-9]+$'
    local -A stages=() originals=() expectations=() identities=()
    local -n result="$result_name"
    result=0
    if [[ "$schema" == 1 ]]; then
        [[ ! -e "$receipt" && ! -L "$receipt" ]] || return "$PNM_EXIT_CONFIG"
        return 0
    fi
    [[ -d "$directory" && -f "$receipt" && ! -L "$receipt" &&
        "$(stat -c '%a|%u' -- "$receipt")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    while IFS=$'\t' read -r event encoded original expected identity extra || [[ -n "$event$encoded$original$expected$identity$extra" ]]; do
        [[ -z "$extra" && ( "$original" == MISSING || "$original" =~ $attributes_pattern ) ]] || return "$PNM_EXIT_CONFIG"
        path="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
        [[ "$path" == /* && "$path" != / && "$path" != *$'\n'* && "$path" != *$'\t'* && "$path" != *$'\r'* &&
            "$(printf '%s' "$path" | base64 -w0)" == "$encoded" ]] || return "$PNM_EXIT_CONFIG"
        # Inspect historical paths as data; do not require them to still exist.
        [[ "/${path#/}/" != *'/../'* ]] || return "$PNM_EXIT_CONFIG"
        [[ "$identity" =~ ^[0-9]+:[0-9]+$ || ( "$original" == MISSING && "$identity" == MISSING ) ]] || return "$PNM_EXIT_CONFIG"
        key="$encoded"
        case "$event" in
            INTENT)
                [[ -z "${stages[$key]-}" && "$expected" == PENDING ]] || return "$PNM_EXIT_CONFIG"
                originals[$key]="$original" identities[$key]="$identity" ;;
            APPLIED)
                [[ "${stages[$key]-}" == INTENT && "${originals[$key]}" == "$original" &&
                    "$expected" =~ $attributes_pattern && "$identity" =~ ^[0-9]+:[0-9]+$ ]] || return "$PNM_EXIT_CONFIG"
                [[ "${identities[$key]}" == MISSING || "${identities[$key]}" == "$identity" ]] || return "$PNM_EXIT_CONFIG"
                expectations[$key]="$expected" identities[$key]="$identity" ;;
            RESTORED)
                [[ "${originals[$key]-}" == "$original" ]] || return "$PNM_EXIT_CONFIG"
                if [[ "${stages[$key]-}" == APPLIED ]]; then
                    [[ "${expectations[$key]}" == "$expected" && "${identities[$key]}" == "$identity" ]] || return "$PNM_EXIT_CONFIG"
                else
                    # Mutation may succeed while its APPLIED append fails. The
                    # verified compensation then legitimately follows INTENT.
                    [[ "${stages[$key]-}" == INTENT ]] || return "$PNM_EXIT_CONFIG"
                    if [[ "$expected" == MISSING ]]; then
                        [[ "$original" == MISSING && "$identity" == MISSING ]] || return "$PNM_EXIT_CONFIG"
                    else
                        [[ "$expected" =~ $attributes_pattern && "$identity" =~ ^[0-9]+:[0-9]+$ &&
                            ( "${identities[$key]}" == MISSING || "${identities[$key]}" == "$identity" ) ]] || return "$PNM_EXIT_CONFIG"
                    fi
                fi ;;
            *) return "$PNM_EXIT_CONFIG" ;;
        esac
        stages[$key]="$event"
    done <"$receipt"
    for key in "${!stages[@]}"; do
        [[ "${stages[$key]}" == RESTORED ]] || ((result += 1))
    done
    return 0
}

pnm_tx_snapshot_file() {
    local source="${1:?source file required}"
    local label="${2:?snapshot label required}"
    local snapshot_root snapshot metadata attributes owner_mode

    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    ((PNM_DRY_RUN == 0)) || return 0
    pnm_tx_require_filesystem_schema || return $?
    pnm_validate_managed_path "$source" || return $?
    [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || return "$PNM_EXIT_CONFIG"
    snapshot_root="$PNM_TX_PATH/snapshots"
    pnm_mkdir_mode 0700 "$snapshot_root" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$snapshot_root" && ! -L "$snapshot_root" ]] || return "$PNM_EXIT_CONFIG"
    owner_mode="$(stat -c '%a|%u' -- "$snapshot_root" 2>/dev/null || printf '000|x')"
    [[ "$owner_mode" == "700|$EUID" ]] || return "$PNM_EXIT_NOPERM"
    snapshot="$snapshot_root/$label"
    metadata="$snapshot_root/$label.state"
    # A repeated label must never replace the operation's original baseline.
    [[ ! -e "$metadata" && ! -L "$metadata" && ! -e "$snapshot" && ! -L "$snapshot" ]] || return "$PNM_EXIT_CONFIG"
    if [[ ! -e "$source" && ! -L "$source" ]]; then
        printf 'MISSING|MISSING|MISSING|MISSING\n' >"$metadata" || return "$PNM_EXIT_CANTCREAT"
        chmod 0600 -- "$metadata" || return "$PNM_EXIT_NOPERM"
        pnm_tx_journal SNAPSHOT "label=$label state=MISSING" || return "$PNM_EXIT_CANTCREAT"
        return 0
    fi
    [[ -f "$source" && ! -L "$source" ]] || return "$PNM_EXIT_CONFIG"
    attributes="$(stat -c '%a|%u|%g' -- "$source" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    install -m 0600 -- "$source" "$snapshot" || return "$PNM_EXIT_CANTCREAT"
    printf 'PRESENT|%s\n' "$attributes" >"$metadata" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$metadata" || return "$PNM_EXIT_NOPERM"
    pnm_tx_journal SNAPSHOT "label=$label state=PRESENT" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_snapshot_state() {
    local label="${1:?snapshot label required}" metadata value state mode uid gid

    [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || return "$PNM_EXIT_CONFIG"
    metadata="$PNM_TX_PATH/snapshots/$label.state"
    value="$(pnm_tx_read_snapshot_metadata "$metadata" 2)" || return $?
    IFS='|' read -r state mode uid gid <<<"$value"
    case "$state" in
        MISSING) printf '%s\n' "$value" ;;
        PRESENT)
            [[ "$mode" =~ ^[0-7]{1,4}$ ]] || return "$PNM_EXIT_CONFIG"
            [[ -f "$PNM_TX_PATH/snapshots/$label" && ! -L "$PNM_TX_PATH/snapshots/$label" && "$(stat -c '%a' -- "$PNM_TX_PATH/snapshots/$label")" == 600 ]] || return "$PNM_EXIT_CONFIG"
            printf '%s\n' "$value"
            ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
}

pnm_tx_restore_file() {
    local source="${1:?source file required}"
    local label="${2:?snapshot label required}"
    local expected_sha256="${3:?expected written sha256 required}"
    local snapshot_root snapshot state current original_state original_mode expected_hash
    local snapshot_info original_uid original_gid staged restored_hash index

    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    ((PNM_DRY_RUN == 0)) || return 0
    pnm_tx_require_filesystem_schema || return $?
    pnm_validate_managed_path "$source" || return $?
    [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || return "$PNM_EXIT_CONFIG"
    snapshot_root="$PNM_TX_PATH/snapshots"
    snapshot="$snapshot_root/$label"
    snapshot_info="$(pnm_tx_snapshot_state "$label")" || return $?
    IFS='|' read -r state original_mode original_uid original_gid <<<"$snapshot_info"
    current="$(pnm_tx_file_sha256 "$source")" || return $?
    for index in "${!PNM_TX_WRITTEN_PATHS[@]}"; do
        [[ "${PNM_TX_WRITTEN_PATHS[index]}" == "$source" ]] || continue
        # Standalone callers can explicitly enroll metadata for a resource;
        # legacy callers that normalize ownership later keep their convention.
        [[ "$PNM_TX_OPERATION" == deployment || -n "${PNM_TX_WRITTEN_ATTRIBUTES[index]}" ]] || continue
        if [[ "$(stat -c '%a|%u|%g' -- "$source")" != "${PNM_TX_WRITTEN_ATTRIBUTES[index]}" ]]; then
            PNM_TX_RECOVERY_REQUIRED=1
            pnm_tx_journal RECOVERY_REQUIRED "label=$label metadata_drift" || true
            return "$PNM_EXIT_SOFTWARE"
        fi
    done
    if [[ "$current" != "$expected_sha256" ]]; then
        PNM_TX_RECOVERY_REQUIRED=1
        pnm_tx_journal RECOVERY_REQUIRED "label=$label current_hash_mismatch" || true
        return "$PNM_EXIT_SOFTWARE"
    fi
    expected_hash="$expected_sha256"
    original_state="$state"
    if [[ "$state" == PRESENT ]]; then
        [[ -f "$snapshot" && ! -L "$snapshot" ]] || return "$PNM_EXIT_CONFIG"
        [[ "$original_mode" =~ ^[0-7]{1,4}$ ]] || return "$PNM_EXIT_CONFIG"
    else
        [[ "$original_mode" == MISSING ]] || return "$PNM_EXIT_CONFIG"
    fi
    case "$state" in
        MISSING)
            if [[ -e "$source" || -L "$source" ]]; then rm -f -- "$source" || return "$PNM_EXIT_CANTCREAT"; fi
            ;;
        PRESENT)
            [[ -f "$snapshot" && ! -L "$snapshot" ]] || return "$PNM_EXIT_CONFIG"
            staged="$(mktemp -- "$(dirname -- "$source")/.pnm-restore.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
            # Ownership must precede the final mode: chown can clear set-id bits.
            if ! install -m 0600 -- "$snapshot" "$staged" ||
                ! chown -- "+$original_uid:+$original_gid" "$staged" ||
                ! chmod "$original_mode" -- "$staged" || ! mv -f -- "$staged" "$source"; then
                rm -f -- "$staged"
                return "$PNM_EXIT_CANTCREAT"
            fi
            restored_hash="$(pnm_tx_file_sha256 "$snapshot")" || return $?
            [[ "$(pnm_tx_file_sha256 "$source")" == "$restored_hash" &&
                "$(stat -c '%a|%u|%g' -- "$source")" == "$original_mode|$original_uid|$original_gid" ]] || return "$PNM_EXIT_SOFTWARE"
            ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
    pnm_tx_manifest_append RESTORED "$label" "$source" "$original_state" "$original_mode" "$expected_hash" || return $?
    pnm_tx_journal RESTORED "label=$label" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_record_written_metadata() {
    local path="$1" index attributes encoded receipt="$PNM_TX_PATH/file-attributes.tsv"
    local expected_attributes="${3-}"
    [[ "$PNM_TX_OPERATION" == deployment || "${2-}" == required ]] || return 0
    pnm_validate_managed_path "$path" || return $?
    if [[ -e "$receipt" || -L "$receipt" ]]; then
        [[ -f "$receipt" && ! -L "$receipt" && "$(stat -c '%a|%u' -- "$receipt")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    fi
    for index in "${!PNM_TX_WRITTEN_PATHS[@]}"; do
        [[ "${PNM_TX_WRITTEN_PATHS[index]}" == "$path" ]] || continue
        [[ "$(pnm_tx_file_sha256 "$path")" == "${PNM_TX_WRITTEN_HASHES[index]}" ]] || return "$PNM_EXIT_SOFTWARE"
        attributes="$(stat -c '%a|%u|%g' -- "$path")" || return "$PNM_EXIT_CONFIG"
        # A caller normalizing ownership may supply its fixed target. Validate
        # the sample we actually record instead of adopting intervening edits.
        [[ -z "$expected_attributes" || "$attributes" == "$expected_attributes" ]] || return "$PNM_EXIT_SOFTWARE"
        PNM_TX_WRITTEN_ATTRIBUTES[index]="$attributes"
        encoded="$(printf '%s' "$path" | base64 -w0)" || return "$PNM_EXIT_SOFTWARE"
        (umask 077; printf '%s\t%s\t%s\t%s\n' "${PNM_TX_WRITTEN_LABELS[index]}" "$encoded" "$attributes" \
            "${PNM_TX_WRITTEN_HASHES[index]}" >>"$receipt") || return "$PNM_EXIT_CANTCREAT"
        return 0
    done
    return "$PNM_EXIT_CONFIG"
}

pnm_tx_verify_written_resources() {
    local index path
    for index in "${!PNM_TX_WRITTEN_PATHS[@]}"; do
        path="${PNM_TX_WRITTEN_PATHS[index]}"
        pnm_validate_managed_path "$path" || return $?
        [[ "$(pnm_tx_file_sha256 "$path")" == "${PNM_TX_WRITTEN_HASHES[index]}" &&
            "$(stat -c '%a|%u|%g' -- "$path")" == "${PNM_TX_WRITTEN_ATTRIBUTES[index]}" ]] || return "$PNM_EXIT_SOFTWARE"
    done
    for index in "${!PNM_TX_DIRECTORY_PATHS[@]}"; do
        path="${PNM_TX_DIRECTORY_PATHS[index]}"
        pnm_validate_managed_path "$path" || return $?
        [[ -d "$path" && "$(stat -c '%a|%u|%g' -- "$path")" == "${PNM_TX_DIRECTORY_EXPECTED[index]}" &&
            "$(stat -c '%d:%i' -- "$path")" == "${PNM_TX_DIRECTORY_IDENTITIES[index]}" ]] || return "$PNM_EXIT_SOFTWARE"
    done
}

pnm_tx_write_file() {
    local source="${1:?source file required}"
    local destination="${2:?destination file required}"
    local label="${3:?snapshot label required}"
    local mode="${4:?destination mode required}"
    local metadata_policy="${5-}"
    local destination_parent digest snapshot_info original_state original_mode original_uid original_gid
    local staged_destination

    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    ((PNM_DRY_RUN == 0)) || return 0
    pnm_validate_managed_path "$destination" || return $?
    [[ -f "$source" && ! -L "$source" ]] || return "$PNM_EXIT_CONFIG"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return "$PNM_EXIT_CONFIG"
    destination_parent="$(dirname -- "$destination")"
    [[ -d "$destination_parent" && ! -L "$destination_parent" ]] || return "$PNM_EXIT_CANTCREAT"
    pnm_tx_snapshot_file "$destination" "$label" || return $?
    snapshot_info="$(pnm_tx_snapshot_state "$label")" || return $?
    IFS='|' read -r original_state original_mode original_uid original_gid <<<"$snapshot_info"
    staged_destination="$(mktemp -- "$destination_parent/.pnm-write.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    if ! install -m "$mode" -- "$source" "$staged_destination"; then
        rm -f -- "$staged_destination"
        return "$PNM_EXIT_CANTCREAT"
    fi
    digest="$(pnm_tx_file_sha256 "$staged_destination")" || { rm -f -- "$staged_destination"; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_manifest_append INTENT "$label" "$destination" "$original_state" "$original_mode" "$digest" || {
        rm -f -- "$staged_destination"
        return "$PNM_EXIT_CANTCREAT"
    }
    if ! mv -f -- "$staged_destination" "$destination"; then
        rm -f -- "$staged_destination"
        return "$PNM_EXIT_CANTCREAT"
    fi
    PNM_TX_WRITTEN_PATHS+=("$destination")
    PNM_TX_WRITTEN_LABELS+=("$label")
    PNM_TX_WRITTEN_HASHES+=("$digest")
    # Required enrollment must precede every post-publication receipt. If the
    # metadata read itself fails, PENDING makes compensation retain the file.
    if [[ "$metadata_policy" == required ]]; then
        PNM_TX_WRITTEN_ATTRIBUTES+=(PENDING)
    else
        PNM_TX_WRITTEN_ATTRIBUTES+=('')
    fi
    pnm_tx_record_written_metadata "$destination" "$metadata_policy" || return $?
    pnm_tx_manifest_append APPLIED "$label" "$destination" "$original_state" "$original_mode" "$digest" || return "$PNM_EXIT_CANTCREAT"
    pnm_tx_journal WRITE "label=$label" || return "$PNM_EXIT_CANTCREAT"
}

pnm_tx_restore_written_files() {
    local index
    local rc=0

    for ((index=${#PNM_TX_WRITTEN_PATHS[@]} - 1; index >= 0; index -= 1)); do
        if pnm_tx_restore_file \
            "${PNM_TX_WRITTEN_PATHS[$index]}" \
            "${PNM_TX_WRITTEN_LABELS[$index]}" \
            "${PNM_TX_WRITTEN_HASHES[$index]}"; then
            :
        else
            rc=$?
            return "$rc"
        fi
    done
    return 0
}

pnm_tx_run() {
    local step="${1:?step required}"
    local apply_function="${2:?apply function required}"
    local rollback_function=''
    local rc

    if (($# > 2)) && declare -F "${3-}" >/dev/null 2>&1; then
        rollback_function="$3"
        shift 3
    else
        shift 2
    fi

    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    pnm_tx_journal STEP_BEGIN "$step" || return "$PNM_EXIT_CANTCREAT"
    if "$apply_function" "$@"; then
        rc=0
    else
        rc=$?
    fi
    if ((rc != 0)); then
        PNM_TX_STEP_FAILURE_NAME="$step"
        PNM_TX_STEP_FAILURE_RC="$rc"
        pnm_tx_journal STEP_FAILED "$step rc=$rc" || PNM_TX_RECOVERY_REQUIRED=1
        [[ "$PNM_TX_OPERATION" != deployment ]] || return "$rc"
        if ! pnm_tx_rollback; then
            ((PNM_TX_ROLLBACK_FAILURE_RC != 0)) || PNM_TX_ROLLBACK_FAILURE_RC="$PNM_EXIT_SOFTWARE"
            return "$rc"
        fi
        return "$rc"
    fi
    [[ -z "$rollback_function" ]] || pnm_tx_add_rollback "$rollback_function"
    if ! pnm_tx_journal STEP_DONE "$step"; then
        PNM_TX_RECOVERY_REQUIRED=1
        [[ "$PNM_TX_OPERATION" != deployment ]] || return "$PNM_EXIT_CANTCREAT"
        pnm_tx_rollback || return "$PNM_EXIT_SOFTWARE"
        return "$PNM_EXIT_CANTCREAT"
    fi
}

pnm_tx_rollback() {
    local index rollback_function rc=0

    ((PNM_TX_ACTIVE == 1)) || return 0
    ((PNM_TX_COMMITTED == 0)) || return "$PNM_EXIT_SOFTWARE"
    ((PNM_TX_ROLLED_BACK == 0)) || return 0
    pnm_tx_journal ROLLBACK_BEGIN '' || PNM_TX_RECOVERY_REQUIRED=1
    for ((index=${#PNM_TX_ROLLBACKS[@]} - 1; index >= 0; index -= 1)); do
        rollback_function="${PNM_TX_ROLLBACKS[$index]}"
        if "$rollback_function"; then
            pnm_tx_journal ROLLBACK_DONE "$rollback_function" || rc="$PNM_EXIT_SOFTWARE"
        else
            rc=$?
            PNM_TX_ROLLBACK_FAILURE_RC="$rc"
            pnm_tx_journal RECOVERY_REQUIRED "$rollback_function rollback_rc=$rc original_rc=$PNM_TX_STEP_FAILURE_RC"
            PNM_TX_RECOVERY_REQUIRED=1
            return "$PNM_EXIT_SOFTWARE"
        fi
    done
    if ((rc == 0)); then
        PNM_TX_ROLLED_BACK=1
        pnm_tx_journal ROLLBACK_COMPLETE '' || { PNM_TX_RECOVERY_REQUIRED=1; return "$PNM_EXIT_SOFTWARE"; }
    else
        PNM_TX_ROLLBACK_FAILURE_RC="$rc"
        PNM_TX_RECOVERY_REQUIRED=1
        pnm_tx_journal RECOVERY_REQUIRED 'rollback journal write failed' || true
        return "$PNM_EXIT_SOFTWARE"
    fi
}

pnm_tx_commit() {
    local rc
    ((PNM_TX_ACTIVE == 1)) || return "$PNM_EXIT_SOFTWARE"
    if [[ "$PNM_TX_OPERATION" == deployment ]]; then
        pnm_tx_journal COMMIT_INTENT '' || return "$PNM_EXIT_CANTCREAT"
        if pnm_tx_publish_deployment_commit; then :; else
            rc=$?
            if [[ -e "$PNM_TX_PATH/commit.env" || -L "$PNM_TX_PATH/commit.env" ]]; then
                PNM_TX_RECOVERY_REQUIRED=1
                pnm_tx_journal RECOVERY_REQUIRED 'commit publication durability uncertain' || true
                return "$PNM_EXIT_SOFTWARE"
            fi
            return "$rc"
        fi
        PNM_TX_COMMITTED=1
        pnm_tx_journal COMMIT '' || pnm_warn 'Deployment committed; transaction progress journal could not be completed.'
        return 0
    fi
    if ! pnm_tx_journal COMMIT ''; then
        PNM_TX_RECOVERY_REQUIRED=1
        return "$PNM_EXIT_CANTCREAT"
    fi
    PNM_TX_COMMITTED=1
}

pnm_tx_close() {
    local journal_rc=0 lock_rc=0

    ((PNM_TX_ACTIVE == 1)) || return 0
    if ((PNM_TX_COMMITTED == 0)); then
        if ((PNM_TX_RECOVERY_REQUIRED == 1)); then
            pnm_tx_journal RECOVERY_REQUIRED 'transaction closed with uncertain state' || journal_rc="$PNM_EXIT_CANTCREAT"
        elif ((PNM_TX_ROLLED_BACK == 1)); then
            pnm_tx_journal ROLLED_BACK '' || journal_rc="$PNM_EXIT_CANTCREAT"
        else
            pnm_tx_journal ABANDONED 'transaction closed without commit' || journal_rc="$PNM_EXIT_CANTCREAT"
        fi
    fi
    PNM_TX_ACTIVE=0
    PNM_TX_ID=''
    PNM_TX_PATH=''
    PNM_TX_ROLLBACKS=()
    PNM_TX_WRITTEN_PATHS=()
    PNM_TX_WRITTEN_LABELS=()
    PNM_TX_WRITTEN_HASHES=()
    PNM_TX_WRITTEN_ATTRIBUTES=()
    PNM_TX_DIRECTORY_PATHS=()
    PNM_TX_DIRECTORY_ORIGINAL=()
    PNM_TX_DIRECTORY_EXPECTED=()
    PNM_TX_DIRECTORY_IDENTITIES=()
    PNM_TX_DEPLOYMENT_ID='none'
    PNM_TX_OPERATION=''
    pnm_lock_release || lock_rc=$?
    ((journal_rc == 0)) || return "$journal_rc"
    return "$lock_rc"
}
