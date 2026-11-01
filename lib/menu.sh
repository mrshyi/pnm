#!/usr/bin/env bash

pnm_menu_install() {
    local certificate private_key
    local -A node=()

    if pnm_load_node_config node && [[ "${node[HY2_TLS_MODE]-}" == external-ca && "${node[PNM_CONFIGURED]-}" != yes ]]; then
        IFS= read -r -p 'TLS certificate chain file: ' certificate || return "$PNM_EXIT_USAGE"
        IFS= read -r -p 'TLS private key file: ' private_key || return "$PNM_EXIT_USAGE"
        [[ -n "$certificate" && -n "$private_key" ]] || { pnm_error 'Both TLS file paths are required.'; return "$PNM_EXIT_USAGE"; }
        pnm_install --apply --yes --tls-cert "$certificate" --tls-key "$private_key"
    else
        pnm_install --apply --yes
    fi
}

pnm_menu_profile() {
    local desired confirmation
    pnm_profile_command show || return $?
    IFS= read -r -p 'Profile [dual/reality/hy2]: ' desired || return "$PNM_EXIT_USAGE"
    IFS= read -r -p 'Apply this profile? Type yes: ' confirmation || return "$PNM_EXIT_USAGE"
    [[ "$confirmation" == yes ]] || return 0
    pnm_profile_command set "$desired" --yes
}

pnm_menu() {
    local choice

    while true; do
        cat <<'EOF'

Proxy Node Manager

1. Install / Configure Both Cores
2. Core Status
3. Health Check
4. Apply Xray Configuration
5. Apply Hysteria2 Configuration
6. Restart a Core
7. View Core Logs
8. Update a Core
9. Back Up Node
10. Restore Node
11. Uninstall a Core
12. Version
13. Help
14. Switch Profile (keep Core files and credentials)
15. Recovery Diagnostics
0. Exit
EOF
        read -r -p 'Select: ' choice || return "$PNM_EXIT_OK"
        case "$choice" in
            1) pnm_menu_install || true ;;
            2) pnm_status || true ;;
            3) pnm_check || true ;;
            4) pnm_core_command apply xray || true ;;
            5) pnm_core_command apply hy2 || true ;;
            6) pnm_core_menu_select restart || true ;;
            7) pnm_core_menu_select log || true ;;
            8) pnm_core_menu_select update || true ;;
            9) pnm_core_command backup || true ;;
            10) pnm_core_menu_restore || true ;;
            11) pnm_core_menu_uninstall || true ;;
            12) pnm_print_version ;;
            13) pnm_print_help ;;
            14) pnm_menu_profile || true ;;
            15) pnm_recovery_command list || true ;;
            0) return "$PNM_EXIT_OK" ;;
            *) pnm_warn 'Invalid selection.' ;;
        esac
    done
}
