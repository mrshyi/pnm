#!/usr/bin/env bash

pnm_tls_require_openssl() {
    pnm_command_exists openssl || return "$PNM_EXIT_UNAVAILABLE"
}

pnm_tls_spki_pin() {
    local certificate="${1:?certificate required}"
    local public_key

    pnm_tls_require_openssl || return $?
    [[ -f "$certificate" && ! -L "$certificate" ]] || return "$PNM_EXIT_CONFIG"
    public_key="$(openssl x509 -in "$certificate" -pubkey -noout 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "$public_key" | openssl pkey -pubin -outform DER 2>/dev/null \
        | openssl dgst -sha256 -binary 2>/dev/null | base64 -w0
    printf '\n'
}

pnm_tls_validate_pair() {
    local certificate="${1:?certificate required}"
    local private_key="${2:?private key required}"
    local certificate_pin key_pin

    pnm_tls_require_openssl || return $?
    [[ -f "$certificate" && ! -L "$certificate" ]] || return "$PNM_EXIT_CONFIG"
    [[ -f "$private_key" && ! -L "$private_key" ]] || return "$PNM_EXIT_CONFIG"
    openssl x509 -in "$certificate" -noout >/dev/null 2>&1 || return "$PNM_EXIT_CONFIG"
    openssl pkey -in "$private_key" -noout -check >/dev/null 2>&1 || return "$PNM_EXIT_CONFIG"
    certificate_pin="$(pnm_tls_spki_pin "$certificate")" || return "$PNM_EXIT_CONFIG"
    key_pin="$(openssl pkey -in "$private_key" -pubout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64 -w0)" || return "$PNM_EXIT_CONFIG"
    [[ -n "$certificate_pin" && "$certificate_pin" == "$key_pin" ]]
}

pnm_tls_generate_selfsigned() {
    local certificate="${1:?certificate destination required}"
    local private_key="${2:?private key destination required}"
    local common_name="${3:?certificate common name required}"
    local certificate_parent key_parent temp_certificate temp_key

    [[ "$common_name" =~ ^[A-Za-z0-9.-]+$ ]] || return "$PNM_EXIT_CONFIG"
    pnm_tls_require_openssl || return $?
    certificate_parent="$(dirname -- "$certificate")"
    key_parent="$(dirname -- "$private_key")"
    [[ -d "$certificate_parent" && -d "$key_parent" ]] || return "$PNM_EXIT_CANTCREAT"
    [[ ! -e "$certificate" && ! -e "$private_key" ]] || return "$PNM_EXIT_CANTCREAT"
    temp_certificate="$(mktemp "$certificate_parent/.pnm-cert.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    temp_key="$(mktemp "$key_parent/.pnm-key.XXXXXXXX")" || {
        rm -f -- "$temp_certificate"
        return "$PNM_EXIT_CANTCREAT"
    }
    if ! openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -days 3650 -subj "/CN=$common_name" \
        -addext "subjectAltName=DNS:$common_name" \
        -keyout "$temp_key" -out "$temp_certificate" >/dev/null 2>&1; then
        rm -f -- "$temp_certificate" "$temp_key"
        return "$PNM_EXIT_SOFTWARE"
    fi
    chmod 0644 -- "$temp_certificate"
    chmod 0600 -- "$temp_key"
    mv -n -- "$temp_certificate" "$certificate" || {
        rm -f -- "$temp_certificate" "$temp_key"
        return "$PNM_EXIT_CANTCREAT"
    }
    mv -n -- "$temp_key" "$private_key" || {
        rm -f -- "$certificate" "$temp_key"
        return "$PNM_EXIT_CANTCREAT"
    }
    if ! pnm_tls_validate_pair "$certificate" "$private_key"; then
        rm -f -- "$certificate" "$private_key"
        return "$PNM_EXIT_CONFIG"
    fi
}

pnm_tls_stage_external_pair() {
    local source_certificate="${1:?source certificate required}"
    local source_key="${2:?source private key required}"
    local destination_dir="${3:?destination directory required}"
    local certificate="$destination_dir/server.crt"
    local private_key="$destination_dir/server.key"

    [[ -f "$source_certificate" && ! -L "$source_certificate" ]] || return "$PNM_EXIT_CONFIG"
    [[ -f "$source_key" && ! -L "$source_key" ]] || return "$PNM_EXIT_CONFIG"
    pnm_mkdir_mode 0700 "$destination_dir" || return "$PNM_EXIT_CANTCREAT"
    [[ ! -e "$certificate" && ! -e "$private_key" ]] || return "$PNM_EXIT_CANTCREAT"
    install -m 0644 -- "$source_certificate" "$certificate" || return "$PNM_EXIT_CANTCREAT"
    if ! install -m 0600 -- "$source_key" "$private_key"; then
        rm -f -- "$certificate" "$private_key"
        return "$PNM_EXIT_CANTCREAT"
    fi
    if ! pnm_tls_validate_pair "$certificate" "$private_key"; then
        rm -f -- "$certificate" "$private_key"
        return "$PNM_EXIT_CONFIG"
    fi
}
