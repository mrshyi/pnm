#!/usr/bin/env bash

declare -Ag PNM_ASSET_VERSIONS=()

pnm_assets_load() {
    pnm_load_versions_config PNM_ASSET_VERSIONS || return "$PNM_EXIT_CONFIG"
    pnm_validate_versions_config PNM_ASSET_VERSIONS || return "$PNM_EXIT_CONFIG"
}

pnm_assets_render_text() {
    local xray_url hysteria_url
    xray_url="$(pnm_asset_url xray "${PNM_ASSET_VERSIONS[XRAY_VERSION]}")" || return "$PNM_EXIT_CONFIG"
    hysteria_url="$(pnm_asset_url hysteria2 "${PNM_ASSET_VERSIONS[HY2_VERSION]}")" || return "$PNM_EXIT_CONFIG"
    printf 'Approved PNM Core assets\n\n'
    printf 'Xray      %s\nSource    %s\nSHA-256   %s\n\n' "${PNM_ASSET_VERSIONS[XRAY_VERSION]}" "$xray_url" "${PNM_ASSET_VERSIONS[XRAY_SHA256]}"
    printf 'Hysteria2 %s\nSource    %s\nSHA-256   %s\n' "${PNM_ASSET_VERSIONS[HY2_VERSION]}" "$hysteria_url" "${PNM_ASSET_VERSIONS[HY2_SHA256]}"
}

pnm_assets_render_json() {
    local xray_url hysteria_url
    xray_url="$(pnm_asset_url xray "${PNM_ASSET_VERSIONS[XRAY_VERSION]}")" || return "$PNM_EXIT_CONFIG"
    hysteria_url="$(pnm_asset_url hysteria2 "${PNM_ASSET_VERSIONS[HY2_VERSION]}")" || return "$PNM_EXIT_CONFIG"
    printf '{"schema":"pnm.assets.v1","assets":['
    printf '{"core":"xray","version":%s,"source":%s,"sha256":%s},' \
        "$(pnm_json_string "${PNM_ASSET_VERSIONS[XRAY_VERSION]}")" "$(pnm_json_string "$xray_url")" "$(pnm_json_string "${PNM_ASSET_VERSIONS[XRAY_SHA256]}")"
    printf '{"core":"hysteria2","version":%s,"source":%s,"sha256":%s}' \
        "$(pnm_json_string "${PNM_ASSET_VERSIONS[HY2_VERSION]}")" "$(pnm_json_string "$hysteria_url")" "$(pnm_json_string "${PNM_ASSET_VERSIONS[HY2_SHA256]}")"
    printf ']}\n'
}

pnm_assets() {
    pnm_assets_load || {
        pnm_error "Approved asset manifest is missing or invalid: $PNM_CONFIG_DIR/versions.conf"
        return "$PNM_EXIT_CONFIG"
    }
    if [[ "$PNM_OUTPUT_MODE" == 'json' ]]; then
        pnm_assets_render_json
    else
        pnm_assets_render_text
    fi
}
