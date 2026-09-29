#!/usr/bin/env bash

# Internal controlled apply boundary. Public install/deploy apply remains closed.
PNM_APPLY_GATE_ID=''
PNM_APPLY_GATE_PATH=''
PNM_APPLY_GATE_ACTIVE=0
PNM_APPLY_GATE_COMMITTED=0
PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS="${PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS:-300}"
PNM_APPLY_GATE_COMMIT_DEADLINE=''
PNM_APPLY_GATE_STEP="${PNM_APPLY_GATE_STEP:-pnm_deploy_execute}"
PNM_APPLY_GATE_STEP_HEALTH="${PNM_APPLY_GATE_STEP_HEALTH:-pnm_deploy_health_step}"

pnm_apply_gate_new_id() {
    if [[ -n "${PNM_APPLY_GATE_ID_OVERRIDE:-}" ]]; then
        printf '%s\n' "$PNM_APPLY_GATE_ID_OVERRIDE"
    else
        printf 'apply-%s-%s\n' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$"
    fi
}

pnm_apply_gate_journal() {
    local phase="${1:?apply gate phase required}"
    local detail="${2-}"

    ((PNM_APPLY_GATE_ACTIVE == 1)) || return 0
    printf '%s\t%s\t%s\n' "$(pnm_now_utc)" "$phase" "$(pnm_one_line "$detail")" >>"$PNM_APPLY_GATE_PATH/journal.tsv"
}

pnm_apply_gate_validate_timeout() {
    [[ "${PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS:-}" =~ ^[0-9]+$ ]] || return "$PNM_EXIT_CONFIG"
    ((10#$PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS >= 30 && 10#$PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS <= 600)) || return "$PNM_EXIT_CONFIG"
}

pnm_apply_gate_precheck() {
    ((PNM_DRY_RUN == 0)) || return "$PNM_EXIT_USAGE"
    ((PNM_ASSUME_YES == 1)) || return "$PNM_EXIT_USAGE"
    pnm_require_root || return $?
    pnm_apply_gate_validate_timeout || return $?
}

pnm_apply_gate_begin() {
    local apply_dir now metadata

    ((PNM_APPLY_GATE_ACTIVE == 0)) || return "$PNM_EXIT_SOFTWARE"
    pnm_apply_gate_precheck || return $?
    pnm_lock_acquire exclusive || return $?
    PNM_APPLY_GATE_ID="$(pnm_apply_gate_new_id)" || { pnm_lock_release; return "$PNM_EXIT_SOFTWARE"; }
    [[ "$PNM_APPLY_GATE_ID" =~ ^[A-Za-z0-9._-]{8,80}$ ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    apply_dir="$PNM_STATE_DIR/apply"
    [[ "$PNM_STATE_DIR" == /* && "$PNM_STATE_DIR" != / && ! -L "$PNM_STATE_DIR" ]] || { pnm_lock_release; return "$PNM_EXIT_CONFIG"; }
    pnm_mkdir_mode 0700 "$apply_dir" || { pnm_lock_release; return "$PNM_EXIT_CANTCREAT"; }
    PNM_APPLY_GATE_PATH="$apply_dir/$PNM_APPLY_GATE_ID"
    mkdir -m 0700 -- "$PNM_APPLY_GATE_PATH" || { pnm_lock_release; return "$PNM_EXIT_CANTCREAT"; }
    now="$(date +%s)" || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_UNAVAILABLE"; }
    [[ "$now" =~ ^[0-9]+$ ]] || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_UNAVAILABLE"; }
    [[ -r /proc/sys/kernel/random/boot_id && ! -L /proc/sys/kernel/random/boot_id ]] || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_UNAVAILABLE"; }
    local boot_id
    IFS= read -r boot_id </proc/sys/kernel/random/boot_id || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_UNAVAILABLE"; }
    [[ "$boot_id" =~ ^[a-fA-F0-9-]{16,64}$ ]] || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_UNAVAILABLE"; }
    PNM_APPLY_GATE_COMMIT_DEADLINE=$((now + 10#$PNM_APPLY_GATE_COMMIT_WINDOW_SECONDS))
    metadata="$PNM_APPLY_GATE_PATH/metadata.env"
    if ! printf 'SCHEMA_VERSION=1\nAPPLY_ID=%s\nCREATED_EPOCH=%s\nCOMMIT_DEADLINE_EPOCH=%s\nAPPLY_BOOT_ID=%s\n' "$PNM_APPLY_GATE_ID" "$now" "$PNM_APPLY_GATE_COMMIT_DEADLINE" "$boot_id" >"$metadata"; then
        rm -rf -- "$PNM_APPLY_GATE_PATH"
        pnm_lock_release
        return "$PNM_EXIT_CANTCREAT"
    fi
    chmod 0600 -- "$metadata" || { rm -rf -- "$PNM_APPLY_GATE_PATH"; pnm_lock_release; return "$PNM_EXIT_NOPERM"; }
    PNM_APPLY_GATE_ACTIVE=1
    PNM_APPLY_GATE_COMMITTED=0
    pnm_apply_gate_journal BEGIN 'controlled apply gate'
    pnm_apply_gate_journal PRECHECK 'root=yes assume_yes=yes'
    pnm_apply_gate_journal LOCK 'exclusive lock acquired'
    pnm_apply_gate_journal SNAPSHOT 'delegated to independent transactions'
}

pnm_apply_gate_deadline_check() {
    local now

    now="$(date +%s)" || return "$PNM_EXIT_UNAVAILABLE"
    [[ "$now" =~ ^[0-9]+$ ]] || return "$PNM_EXIT_UNAVAILABLE"
    ((10#$now <= 10#$PNM_APPLY_GATE_COMMIT_DEADLINE)) || return "$PNM_EXIT_NOPERM"
}

pnm_apply_gate_close() {
    ((PNM_APPLY_GATE_ACTIVE == 1)) || return 0
    if ((PNM_APPLY_GATE_COMMITTED == 0)); then
        pnm_apply_gate_journal ABANDONED 'controlled apply gate closed without commit'
    fi
    pnm_apply_gate_journal UNLOCK ''
    PNM_APPLY_GATE_ACTIVE=0
    PNM_APPLY_GATE_ID=''
    PNM_APPLY_GATE_PATH=''
    PNM_APPLY_GATE_COMMITTED=0
    PNM_APPLY_GATE_COMMIT_DEADLINE=''
    pnm_lock_release
}

pnm_apply_gate_fail() {
    local rc="${1:?apply gate failure code required}"

    pnm_apply_gate_journal APPLY_FAILED "rc=$rc independent_transactions=rollback-on-failure"
    pnm_apply_gate_journal COMPENSATION_BOUNDARY 'failed transaction compensates itself; committed earlier phases may remain; no cross-core rollback'
    pnm_apply_gate_close
    return "$rc"
}

pnm_apply_gate_execute() {
    local rc

    pnm_apply_gate_begin || return $?
    pnm_apply_gate_journal STAGE 'delegated to ordered deployment'
    if "${PNM_APPLY_GATE_STEP}"; then
        pnm_apply_gate_journal APPLY_DONE ''
    else
        rc=$?
        pnm_apply_gate_fail "$rc"
        return "$rc"
    fi
    pnm_apply_gate_journal ACTIVATE 'delegated to Core lifecycle transactions'
    pnm_apply_gate_journal HEALTH_CHECK 'dual-Core post-health validation'
    if pnm_apply_gate_deadline_check; then :; else
        rc=$?
        pnm_apply_gate_fail "$rc"
        return "$rc"
    fi
    if "${PNM_APPLY_GATE_STEP_HEALTH}"; then :; else
        rc=$?
        pnm_apply_gate_fail "$rc"
        return "$rc"
    fi

    local committed_epoch
    committed_epoch="$(date +%s)" || { pnm_apply_gate_fail "$PNM_EXIT_UNAVAILABLE"; return $?; }
    if ! printf 'SCHEMA_VERSION=1\nAPPLY_ID=%s\nCOMMITTED_EPOCH=%s\n' "$PNM_APPLY_GATE_ID" "$committed_epoch" >"$PNM_APPLY_GATE_PATH/commit.env"; then
        pnm_apply_gate_fail "$PNM_EXIT_CANTCREAT"
        return "$PNM_EXIT_CANTCREAT"
    fi
    chmod 0600 -- "$PNM_APPLY_GATE_PATH/commit.env" || { pnm_apply_gate_fail "$PNM_EXIT_NOPERM"; return "$PNM_EXIT_NOPERM"; }
    pnm_apply_gate_journal COMMIT ''
    PNM_APPLY_GATE_COMMITTED=1
    pnm_apply_gate_close
    return 0
}
