#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture=${1:?private fixture required}
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/output.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/render.sh"
source "$PROJECT_ROOT/lib/tls.sh"
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
