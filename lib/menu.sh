#!/usr/bin/env bash

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
0. Exit
EOF
        read -r -p 'Select: ' choice || return "$PNM_EXIT_OK"
        case "$choice" in
            1) pnm_install --apply --yes || true ;;
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
            0) return "$PNM_EXIT_OK" ;;
            *) pnm_warn 'Invalid selection.' ;;
        esac
    done
}
