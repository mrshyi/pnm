#!/usr/bin/env bash

# Host resource application is reachable only from the controlled apply gate.
# A direct call, a missing approval flag, an unverified asset, or a non-root
# process fails before any host path is opened for writing.
PNM_HOST_APPLY_CONFIRMED="${PNM_HOST_APPLY_CONFIRMED:-no}"
PNM_HOST_XRAY_ARCHIVE="${PNM_HOST_XRAY_ARCHIVE:-}"
PNM_HOST_HY2_BINARY="${PNM_HOST_HY2_BINARY:-}"
PNM_HOST_ASSET_DIR="${PNM_HOST_ASSET_DIR:-$PNM_STATE_DIR/assets}"

pnm_host_apply_require_gate() {
    (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 )) || return "$PNM_EXIT_NOPERM"
    [[ "${PNM_HOST_APPLY_CONFIRMED:-no}" == yes ]] || return "$PNM_EXIT_NOPERM"
    pnm_require_root || return $?
}

pnm_host_apply_asset_cache_dir() {
    [[ "$PNM_HOST_ASSET_DIR" == /* && "$PNM_HOST_ASSET_DIR" != / && "$PNM_HOST_ASSET_DIR" != *'..'* ]] || return "$PNM_EXIT_CONFIG"
    pnm_mkdir_mode 0700 "$PNM_HOST_ASSET_DIR" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$PNM_HOST_ASSET_DIR" && ! -L "$PNM_HOST_ASSET_DIR" ]] || return "$PNM_EXIT_CONFIG"
    [[ "$(stat -c '%a|%u' -- "$PNM_HOST_ASSET_DIR" 2>/dev/null || printf '000|x')" == "700|$EUID" ]] || return "$PNM_EXIT_NOPERM"
}

pnm_host_apply_prepare_asset() {
    local core="${1:?core required}" version="${2:?version required}" expected_sha256="${3:?asset hash required}"
    local target_name="${4:?target variable required}" extension="${5:?asset extension required}"
    local destination
    local -n target="$target_name"

    if [[ -n "$target" ]]; then
        pnm_asset_verify_file "$target" "$expected_sha256" || return "$PNM_EXIT_CONFIG"
        return 0
    fi
    pnm_host_apply_asset_cache_dir || return $?
    destination="$PNM_HOST_ASSET_DIR/${core}-${version}-${expected_sha256}.${extension}"
    if [[ -e "$destination" || -L "$destination" ]]; then
        pnm_asset_verify_file "$destination" "$expected_sha256" || return "$PNM_EXIT_CONFIG"
    else
        pnm_asset_download_verified "$core" "$version" "$expected_sha256" "$destination" || return $?
    fi
    target="$destination"
}

pnm_host_apply_asset_precheck() {
    local -A versions=()

    pnm_load_versions_config versions || return "$PNM_EXIT_CONFIG"
    pnm_validate_versions_config versions || return "$PNM_EXIT_CONFIG"
    pnm_host_apply_prepare_asset xray "${versions[XRAY_VERSION]}" "${versions[XRAY_SHA256]}" PNM_HOST_XRAY_ARCHIVE zip || return $?
    pnm_host_apply_prepare_asset hysteria2 "${versions[HY2_VERSION]}" "${versions[HY2_SHA256]}" PNM_HOST_HY2_BINARY bin || return $?
    PNM_SANDBOX_XRAY_ARCHIVE="$PNM_HOST_XRAY_ARCHIVE"
    PNM_SANDBOX_HY2_BINARY="$PNM_HOST_HY2_BINARY"
}

pnm_host_apply_resources_step() {
    pnm_host_apply_require_gate || return $?
    pnm_host_apply_asset_precheck || return $?
    PNM_SANDBOX_ROOT=/
    pnm_sandbox_install /
}
