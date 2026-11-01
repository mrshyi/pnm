#!/usr/bin/env bash

declare -Ag PNM_ASSET_VERSIONS=()

pnm_assets_load() {
    pnm_load_versions_config PNM_ASSET_VERSIONS || return "$PNM_EXIT_CONFIG"
    pnm_validate_versions_config PNM_ASSET_VERSIONS || return "$PNM_EXIT_CONFIG"
}
