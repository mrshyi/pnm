#!/usr/bin/env bash

pnm_install_render_plan_text() {
    ((PNM_QUIET == 1)) && return 0
    cat <<'EOF'

Installation plan:
  1. Acquire the global PNM write lock and create a persistent transaction journal.
  2. Create isolated xray and hysteria service identities.
  3. Fetch only frozen, checksum-verified Xray and Hysteria2 assets.
  4. Generate authority-owned secrets and render the two runtime configurations.
  5. Install PNM-owned systemd units and validate each Core independently.
  6. Commit the generation after local Core health checks; otherwise perform compensating rollback.

Apply requires root, `--yes`, a clean preflight, and checksum-verified fixed Core assets. SSH and UFW are not modified by one-click installation. Any failed phase stops subsequent work; committed earlier phases remain auditable for manual recovery.
EOF
}

pnm_install_render_plan_json() {
    local comma=''
    local -a steps=(
        'Acquire exclusive PNM lock and create transaction journal'
        'Create isolated xray and hysteria service identities'
        'Fetch frozen checksum-verified Core assets'
        'Generate authority-owned secrets and render configurations'
        'Install and validate independent systemd Core services'
        'Commit after local Core health checks or compensate with rollback'
    )
    local step

    printf '{"schema":"pnm.install-plan.v1","generated_at":%s,"write_mode":"preview","preflight":' "$(pnm_json_string "$(pnm_now_utc)")"
    pnm_preflight_render_json_object
    printf ',"steps":['
    for step in "${steps[@]}"; do
        printf '%s%s' "$comma" "$(pnm_json_string "$step")"
        comma=','
    done
    printf ']}\n'
}

pnm_install() {
    local apply_requested=0
    local argument rc

    for argument in "$@"; do
        case "$argument" in
            --dry-run) PNM_DRY_RUN=1 ;;
            --apply) apply_requested=1 ;;
            --yes) PNM_ASSUME_YES=1 ;;
            *)
                pnm_error "Usage: pnm [--json] install [--dry-run]"
                return "$PNM_EXIT_USAGE"
                ;;
        esac
    done
    ((PNM_ASSUME_YES == 1)) && apply_requested=1
    if ((apply_requested == 1 && PNM_DRY_RUN == 1)); then
        pnm_error '--apply and --dry-run are mutually exclusive.'
        return "$PNM_EXIT_USAGE"
    fi
    if ((apply_requested == 1 && PNM_ASSUME_YES == 0)); then
        pnm_error 'Installation requires --yes.'
        return "$PNM_EXIT_USAGE"
    fi

    pnm_init_colors
    pnm_preflight_collect
    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_install_render_plan_json
    else
        pnm_preflight_render_text
        pnm_install_render_plan_text
    fi
    if pnm_preflight_exit_code; then rc=0; else rc=$?; fi
    ((rc == 0)) || return "$rc"

    if ((apply_requested == 1)); then
        pnm_deploy_apply
        rc=$?
        if ((rc == 0)); then
            pnm_info 'Next: sudo pnm node links'
        fi
        return "$rc"
    fi
    return 0
}
