#!/usr/bin/env bash

pnm_asset_url() {
    local core="${1:?core required}"
    local version="${2:?version required}"

    case "$core" in
        xray)
            [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || return 1
            printf 'https://github.com/XTLS/Xray-core/releases/download/%s/Xray-linux-64.zip\n' "$version"
            ;;
        hysteria2)
            [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || return 1
            printf 'https://github.com/apernet/hysteria/releases/download/app%%2F%s/hysteria-linux-amd64\n' "$version"
            ;;
        *) return 1 ;;
    esac
}

pnm_asset_verify_file() {
    local path="${1:?asset path required}"
    local expected_sha256="${2:?expected sha256 required}"
    local actual

    [[ -f "$path" && ! -L "$path" ]] || return 1
    pnm_validate_sha256 "$expected_sha256" || return 2
    pnm_command_exists sha256sum || return 2
    actual="$(sha256sum -- "$path" 2>/dev/null | awk '{print $1}')" || return 1
    [[ "$actual" == "${expected_sha256,,}" ]]
}

pnm_asset_download_verified() {
    local core="${1:?core required}"
    local version="${2:?version required}"
    local expected_sha256="${3:?expected sha256 required}"
    local destination="${4:?destination required}"
    local source_url temp_file destination_dir

    pnm_validate_sha256 "$expected_sha256" || return "$PNM_EXIT_CONFIG"
    source_url="$(pnm_asset_url "$core" "$version")" || return "$PNM_EXIT_CONFIG"
    pnm_command_exists curl || return "$PNM_EXIT_UNAVAILABLE"
    destination_dir="$(dirname -- "$destination")"
    [[ -d "$destination_dir" && -w "$destination_dir" ]] || return "$PNM_EXIT_CANTCREAT"
    [[ ! -e "$destination" ]] || return "$PNM_EXIT_CANTCREAT"
    temp_file="$(mktemp "$destination_dir/.pnm-asset.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"

    if ! curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 --retry 2 --output "$temp_file" "$source_url"; then
        rm -f -- "$temp_file"
        return "$PNM_EXIT_UNAVAILABLE"
    fi
    if ! pnm_asset_verify_file "$temp_file" "$expected_sha256"; then
        rm -f -- "$temp_file"
        return "$PNM_EXIT_CONFIG"
    fi
    chmod 0600 -- "$temp_file"
    mv -n -- "$temp_file" "$destination" || {
        rm -f -- "$temp_file"
        return "$PNM_EXIT_CANTCREAT"
    }
}

pnm_asset_stage_xray_zip() {
    local archive="${1:?xray archive required}"
    local staging_dir="${2:?staging directory required}"
    local extract_dir member

    [[ -f "$archive" && ! -L "$archive" ]] || return "$PNM_EXIT_CONFIG"
    pnm_command_exists unzip || return "$PNM_EXIT_UNAVAILABLE"
    pnm_mkdir_mode 0700 "$staging_dir" || return "$PNM_EXIT_CANTCREAT"
    extract_dir="$staging_dir/xray-extract"
    mkdir -m 0700 -- "$extract_dir" || return "$PNM_EXIT_CANTCREAT"

    while IFS= read -r member; do
        case "$member" in
            '' | /* | ../* | */../* | */ | *$'\n'* | *$'\r'*)
                return "$PNM_EXIT_CONFIG"
                ;;
        esac
    done < <(unzip -Z1 -- "$archive" 2>/dev/null) || return "$PNM_EXIT_CONFIG"
    unzip -qq -- "$archive" -d "$extract_dir" || return "$PNM_EXIT_CONFIG"
    [[ -f "$extract_dir/xray" && ! -L "$extract_dir/xray" ]] || return "$PNM_EXIT_CONFIG"
    chmod 0755 -- "$extract_dir/xray"
    printf '%s\n' "$extract_dir/xray"
}

pnm_asset_stage_hysteria_binary() {
    local binary="${1:?hysteria binary required}"
    local staging_dir="${2:?staging directory required}"
    local destination="$staging_dir/hysteria"

    [[ -f "$binary" && ! -L "$binary" ]] || return "$PNM_EXIT_CONFIG"
    pnm_mkdir_mode 0700 "$staging_dir" || return "$PNM_EXIT_CANTCREAT"
    install -m 0755 -- "$binary" "$destination" || return "$PNM_EXIT_CANTCREAT"
    [[ -x "$destination" ]] || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "$destination"
}
