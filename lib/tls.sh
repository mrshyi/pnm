#!/usr/bin/env bash

pnm_tls_require_openssl() {
    pnm_command_exists openssl || return "$PNM_EXIT_UNAVAILABLE"
}

pnm_tls_spki_pin() {
    local certificate="${1:?certificate required}"
    local public_key pin

    pnm_tls_require_openssl || return $?
    [[ -f "$certificate" && ! -L "$certificate" ]] || return "$PNM_EXIT_CONFIG"
    public_key="$(openssl x509 -in "$certificate" -pubkey -noout 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    pin="$(
        set -o pipefail
        printf '%s\n' "$public_key" | openssl pkey -pubin -outform DER 2>/dev/null \
            | openssl dgst -sha256 -binary 2>/dev/null | base64 -w0
    )" || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "$pin"
}

# Official Hysteria clients pin the full leaf certificate DER, not its SPKI.
# Keep the persisted SPKI/base64 field for existing configuration compatibility.
pnm_tls_certificate_sha256() {
    local certificate="${1:?certificate required}"
    local fingerprint

    pnm_tls_require_openssl || return $?
    [[ -f "$certificate" && ! -L "$certificate" ]] || return "$PNM_EXIT_CONFIG"
    fingerprint="$(LC_ALL=C openssl x509 -in "$certificate" -noout -sha256 -fingerprint 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    fingerprint="${fingerprint#*=}"
    fingerprint="${fingerprint//:/}"
    [[ "$fingerprint" =~ ^[A-Fa-f0-9]{64}$ ]] || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "${fingerprint,,}"
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
    key_pin="$(
        set -o pipefail
        openssl pkey -in "$private_key" -pubout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | base64 -w0
    )" || return "$PNM_EXIT_CONFIG"
    [[ -n "$certificate_pin" && "$certificate_pin" == "$key_pin" ]]
}

pnm_tls_certificate_dns_names() {
    local certificate="${1:?certificate path required}"
    local extension entry names=''

    pnm_tls_require_openssl || return $?
    [[ -f "$certificate" && ! -L "$certificate" && -r "$certificate" ]] || return "$PNM_EXIT_CONFIG"
    extension="$(openssl x509 -in "$certificate" -noout -ext subjectAltName 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    [[ "$extension" == *'X509v3 Subject Alternative Name'* ]] || return "$PNM_EXIT_CONFIG"
    while IFS= read -r entry; do
        entry="${entry#"${entry%%[![:space:]]*}"}"
        [[ "$entry" == DNS:* ]] || continue
        names+="${entry#DNS:}"$'\n'
    done < <(tr ',' '\n' <<<"$extension")
    [[ -n "$names" ]] || return "$PNM_EXIT_CONFIG"
    printf '%s' "$names"
}

pnm_tls_certificate_matches_dns_name() {
    local certificate="${1:?certificate path required}"
    local server_name="${2:?TLS server name required}"
    local dns_names match_result

    pnm_validate_hy2_tls_server_name "$server_name" || return "$PNM_EXIT_CONFIG"
    dns_names="$(pnm_tls_certificate_dns_names "$certificate")" || return "$PNM_EXIT_CONFIG"
    [[ -n "$dns_names" ]] || return "$PNM_EXIT_CONFIG"
    # OpenSSL 3.0 can return zero for a hostname mismatch.
    match_result="$(LC_ALL=C openssl x509 -in "$certificate" -noout -checkhost "$server_name" 2>/dev/null)" || return "$PNM_EXIT_CONFIG"
    [[ "$match_result" == "Hostname $server_name does match certificate" ]] || return "$PNM_EXIT_CONFIG"
}

# Legacy nodes may omit HY2_TLS_SERVER_NAME. Infer only an unambiguous name
# from the existing certificate; never rewrite node.conf or replace its cert.
pnm_hysteria_tls_server_name() {
    local node_name="${1:?node config array required}"
    local hysteria_name="${2:?Hysteria secret array required}"
    local certificate="${3:-}"
    local -n node_ref="$node_name"
    local -n hysteria_ref="$hysteria_name"
    local configured_name="${node_ref[HY2_TLS_SERVER_NAME]-}"
    local address="${node_ref[NODE_ADDRESS]-}"
    local dns_names
    local -a names=()

    [[ -n "$certificate" ]] || certificate="${hysteria_ref[HY2_TLS_CERT_PATH]-}"
    if [[ -n "$configured_name" ]]; then
        if ! pnm_tls_certificate_matches_dns_name "$certificate" "$configured_name"; then
            pnm_error 'HY2_TLS_SERVER_NAME does not match a DNS name in the configured TLS certificate SAN.'
            return "$PNM_EXIT_CONFIG"
        fi
        printf '%s\n' "$configured_name"
        return 0
    fi

    if pnm_validate_hy2_tls_server_name "$address" &&
        pnm_tls_certificate_matches_dns_name "$certificate" "$address"; then
        printf '%s\n' "$address"
        return 0
    fi
    dns_names="$(pnm_tls_certificate_dns_names "$certificate")" || {
        pnm_error 'HY2 TLS server name cannot be resolved because the configured certificate has no readable DNS SAN.'
        return "$PNM_EXIT_CONFIG"
    }
    mapfile -t names <<<"$dns_names"
    if ((${#names[@]} == 1)) && pnm_validate_hy2_tls_server_name "${names[0]}"; then
        printf '%s\n' "${names[0]}"
        return 0
    fi
    pnm_error 'HY2_TLS_SERVER_NAME is unset and the existing certificate SAN is ambiguous; set HY2_TLS_SERVER_NAME explicitly.'
    return "$PNM_EXIT_CONFIG"
}

pnm_tls_certificate_check() {
    local mode="${1:?TLS mode required}"
    local certificate="${2:?certificate path required}"
    local dates not_before not_after not_before_epoch not_after_epoch now

    case "$mode" in
        selfsigned-pin | external-ca) ;;
        *) printf 'SKIP|TLS certificate is managed outside the configured static certificate modes\n'; return 0 ;;
    esac
    if ! pnm_command_exists openssl || ! pnm_command_exists date ||
        [[ ! -f "$certificate" || -L "$certificate" || ! -r "$certificate" ]]; then
        printf 'WARN|TLS certificate cannot be read or validity cannot be determined\n'
        return 0
    fi
    if ! dates="$(LC_ALL=C openssl x509 -in "$certificate" -noout -startdate -enddate 2>/dev/null)"; then
        printf 'WARN|TLS certificate is unreadable or invalid\n'
        return 0
    fi
    not_before="$(sed -n 's/^notBefore=//p' <<<"$dates")"
    not_after="$(sed -n 's/^notAfter=//p' <<<"$dates")"
    if [[ -z "$not_before" || -z "$not_after" ]] ||
        ! not_before_epoch="$(LC_ALL=C date -u -d "$not_before" +%s 2>/dev/null)" ||
        ! not_after_epoch="$(LC_ALL=C date -u -d "$not_after" +%s 2>/dev/null)" ||
        ! now="$(date -u +%s 2>/dev/null)"; then
        printf 'WARN|TLS certificate validity dates cannot be determined\n'
        return 0
    fi
    if ((now < not_before_epoch)); then
        printf 'FAIL|TLS certificate is not yet valid\n'
    elif ((now >= not_after_epoch)); then
        printf 'FAIL|TLS certificate is expired\n'
    else
        printf 'OK|TLS certificate is currently valid; expires %s\n' "$not_after"
    fi
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
