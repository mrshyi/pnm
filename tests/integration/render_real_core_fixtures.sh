#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture=${1:?private fixture required}
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/tls.sh"
source "$PROJECT_ROOT/lib/node.sh"
PNM_CONFIG_DIR="$fixture/config"
declare -A node=() reality=() hysteria=()
pnm_load_node_config node
pnm_load_reality_secret reality
pnm_load_hysteria_secret hysteria
hysteria[HY2_TLS_PIN_SHA256]="$(pnm_tls_spki_pin "${hysteria[HY2_TLS_CERT_PATH]}")"
pnm_render_validate_inputs node reality hysteria
pnm_tls_validate_pair "${hysteria[HY2_TLS_CERT_PATH]}" "${hysteria[HY2_TLS_KEY_PATH]}"
pnm_hysteria_tls_server_name node hysteria >/dev/null
pnm_render_xray_config node reality >"$fixture/xray-server.json"
pnm_render_hysteria_config node hysteria >"$fixture/hy2-server.yaml"
pnm_render_hysteria_secret_config hysteria >"$fixture/config/secrets/hysteria.env"
# This fixture tests URI encoding, not managed-service readiness. Actual startup
# and client traffic are verified independently by the private systemd harness.
pnm_node_core_link_status() {
    if [[ "$1" == hysteria2 ]]; then
        printf 'ready|active|consistent|applied|fixture\n'
    else
        printf 'unavailable|unknown|unknown|unknown|fixture\n'
    fi
}
PNM_OUTPUT_MODE=json
pnm_node_links_unlocked --address 127.0.0.1 >"$fixture/hy2-link.json" 2>"$fixture/logs/link.stderr"
