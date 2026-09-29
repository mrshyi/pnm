#!/usr/bin/env bash

pnm_os_release_value() {
    local key="${1:?os-release key required}"
    local file="${PNM_OS_RELEASE_FILE:?os-release file required}"
    local line value

    [[ -r "$file" && -f "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == "$key="* ]] || continue
        value="${line#*=}"
        if [[ "$value" =~ ^\"([^\"]*)\"$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" =~ ^\'([^\']*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        [[ "$value" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
        printf '%s\n' "$value"
        return 0
    done <"$file"

    return 1
}

pnm_platform_id() {
    pnm_os_release_value ID
}

pnm_platform_version_id() {
    pnm_os_release_value VERSION_ID
}

pnm_platform_arch() {
    uname -m
}

pnm_platform_summary() {
    local id version arch

    id="$(pnm_platform_id 2>/dev/null || printf 'unknown')"
    version="$(pnm_platform_version_id 2>/dev/null || printf 'unknown')"
    arch="$(pnm_platform_arch 2>/dev/null || printf 'unknown')"
    printf '%s %s (%s)\n' "$id" "$version" "$arch"
}

pnm_platform_supported() {
    [[ "$(pnm_platform_id 2>/dev/null || true)" == "debian" ]] || return 1
    [[ "$(pnm_platform_version_id 2>/dev/null || true)" == "13" ]] || return 1
    [[ "$(pnm_platform_arch 2>/dev/null || true)" == "x86_64" ]]
}
