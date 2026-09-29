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

pnm_platform_support_policy() {
    printf '%s\n' 'Debian 12/13 or Ubuntu 22.04/24.04 amd64'
}

pnm_platform_supported() {
    local id version arch

    id="$(pnm_platform_id 2>/dev/null || true)"
    version="$(pnm_platform_version_id 2>/dev/null || true)"
    arch="$(pnm_platform_arch 2>/dev/null || true)"

    [[ "$arch" == 'x86_64' ]] || return 1
    case "$id:$version" in
        debian:12 | debian:13 | ubuntu:22.04 | ubuntu:24.04) return 0 ;;
        *) return 1 ;;
    esac
}
