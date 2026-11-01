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

pnm_install_preflight_tls() {
    local -A tls_identity=()
    if [[ "${PNM_PREFLIGHT_NODE_CONFIG[HY2_TLS_MODE]-}" == external-ca ]]; then
        if [[ -n "$PNM_SANDBOX_EXTERNAL_CERT" && -n "$PNM_SANDBOX_EXTERNAL_KEY" ]] &&
            pnm_tls_validate_pair "$PNM_SANDBOX_EXTERNAL_CERT" "$PNM_SANDBOX_EXTERNAL_KEY" &&
            pnm_hysteria_tls_server_name PNM_PREFLIGHT_NODE_CONFIG tls_identity "$PNM_SANDBOX_EXTERNAL_CERT" >/dev/null 2>&1; then
            pnm_preflight_add external_tls OK 'External TLS pair matches the configured or inferred DNS SAN' ''
        else
            pnm_preflight_add external_tls FAIL 'External TLS inputs are missing, invalid or do not match the configured DNS SAN' \
                'Use --tls-cert FILE --tls-key FILE with a matching certificate and private key.'
        fi
    elif (( $1 == 1 )); then
        pnm_preflight_add external_tls FAIL 'External TLS files require node TLS mode external-ca' ''
    fi
}

pnm_install() {
    local apply_requested=0
    local argument rc
    local tls_cert_given=0 tls_key_given=0
    local PNM_SANDBOX_EXTERNAL_CERT="${PNM_SANDBOX_EXTERNAL_CERT:-}"
    local PNM_SANDBOX_EXTERNAL_KEY="${PNM_SANDBOX_EXTERNAL_KEY:-}"

    while (($# > 0)); do
        argument="$1"
        shift
        case "$argument" in
            --dry-run) PNM_DRY_RUN=1 ;;
            --apply) apply_requested=1 ;;
            --yes) PNM_ASSUME_YES=1 ;;
            --tls-cert)
                (($# > 0)) || { pnm_error '--tls-cert requires a file.'; return "$PNM_EXIT_USAGE"; }
                PNM_SANDBOX_EXTERNAL_CERT="$1"; tls_cert_given=1; shift ;;
            --tls-key)
                (($# > 0)) || { pnm_error '--tls-key requires a file.'; return "$PNM_EXIT_USAGE"; }
                PNM_SANDBOX_EXTERNAL_KEY="$1"; tls_key_given=1; shift ;;
            *)
                pnm_error 'Usage: pnm [--json] install [--dry-run | --apply --yes] [--tls-cert FILE --tls-key FILE]'
                return "$PNM_EXIT_USAGE"
                ;;
        esac
    done
    if ((tls_cert_given != tls_key_given)); then
        pnm_error '--tls-cert and --tls-key must be supplied together.'
        return "$PNM_EXIT_USAGE"
    fi
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
    if pnm_preflight_exit_code; then
        pnm_install_preflight_tls "$tls_cert_given"
    fi
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
