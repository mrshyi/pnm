#!/usr/bin/env bash

pnm_config_key_allowed() {
    local candidate="${1:?candidate key required}"
    shift
    local allowed

    for allowed in "$@"; do
        [[ "$candidate" == "$allowed" ]] && return 0
    done
    return 1
}

pnm_config_value_safe() {
    local value="${1-}"

    [[ "$value" =~ ^[A-Za-z0-9._:/,@%+\-=]*$ ]]
}

pnm_config_load() {
    local file="${1:?configuration file required}"
    local target_name="${2:?target associative array required}"
    shift 2
    local -a allowed_keys=("$@")
    local line key value line_number=0
    local -n target="$target_name"

    target=()

    [[ -e "$file" ]] || return 1
    [[ -f "$file" && ! -L "$file" ]] || {
        pnm_error "Configuration must be a regular, non-symlink file: $file"
        return "$PNM_EXIT_CONFIG"
    }
    [[ -r "$file" ]] || {
        pnm_error "Configuration is not readable: $file"
        return "$PNM_EXIT_CONFIG"
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"

        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
            pnm_error "Invalid configuration syntax at $file:$line_number"
            return "$PNM_EXIT_CONFIG"
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if ! pnm_config_key_allowed "$key" "${allowed_keys[@]}"; then
            pnm_error "Unknown configuration key '$key' at $file:$line_number"
            return "$PNM_EXIT_CONFIG"
        fi
        if ! pnm_config_value_safe "$value"; then
            pnm_error "Unsafe value for '$key' at $file:$line_number"
            return "$PNM_EXIT_CONFIG"
        fi
        if [[ -v "target[$key]" ]]; then
            pnm_error "Duplicate configuration key '$key' at $file:$line_number"
            return "$PNM_EXIT_CONFIG"
        fi

        target["$key"]="$value"
    done <"$file"
}

pnm_validate_port() {
    local value="${1-}"

    [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1
    ((10#$value >= 1 && 10#$value <= 65535))
}

pnm_validate_node_address() {
    local value="${1-}"

    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]
}

pnm_validate_sha256() {
    [[ "${1-}" =~ ^[a-fA-F0-9]{64}$ ]]
}

pnm_validate_pin_sha256() {
    [[ "${1-}" =~ ^[A-Za-z0-9+/]{43}={0,1}$ ]]
}

pnm_validate_node_config() {
    local target_name="${1:?node configuration array required}"
    local -n config="$target_name"

    [[ "${config[SCHEMA_VERSION]-}" == '1' ]] || return 1
    [[ "${config[PNM_CONFIGURED]-}" == 'yes' || "${config[PNM_CONFIGURED]-}" == 'no' ]] || return 1
    [[ "${config[NODE_REGION]-}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || return 1
    if [[ -n "${config[NODE_ADDRESS]-}" ]]; then
        pnm_validate_node_address "${config[NODE_ADDRESS]}" || return 1
    fi
    [[ "${config[TIMEZONE]-}" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] || return 1
    pnm_validate_port "${config[XRAY_PORT]-}" || return 1
    pnm_validate_port "${config[HY2_PORT]-}" || return 1
    [[ "${config[XRAY_SERVER_NAME]-}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "${config[XRAY_TARGET]-}" =~ ^[A-Za-z0-9.-]+:[0-9]{1,5}$ ]] || return 1
    pnm_validate_port "${config[XRAY_TARGET]##*:}" || return 1
    [[ "${config[HY2_TLS_MODE]-}" == 'selfsigned-pin' || "${config[HY2_TLS_MODE]-}" == 'external-ca' ]]
}

pnm_validate_versions_config() {
    local target_name="${1:?versions configuration array required}"
    local -n config="$target_name"

    [[ "${config[SCHEMA_VERSION]-}" == '1' ]] || return 1
    [[ "${config[APPROVED]-}" == 'yes' ]] || return 1
    [[ "${config[XRAY_VERSION]-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || return 1
    [[ "${config[HY2_VERSION]-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || return 1
    pnm_validate_sha256 "${config[XRAY_SHA256]-}" || return 1
    pnm_validate_sha256 "${config[HY2_SHA256]-}"
}

pnm_validate_uuid() {
    [[ "${1-}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

pnm_validate_reality_secret_config() {
    local target_name="${1:?reality secret array required}"
    local -n config="$target_name"

    [[ "${config[SCHEMA_VERSION]-}" == '1' ]] || return 1
    pnm_validate_uuid "${config[XRAY_UUID]-}" || return 1
    [[ "${config[XRAY_REALITY_PRIVATE_KEY]-}" =~ ^[A-Za-z0-9_-]{40,64}$ ]] || return 1
    [[ "${config[XRAY_REALITY_SHORT_ID]-}" =~ ^[a-fA-F0-9]{2,16}$ ]]
}

pnm_validate_hysteria_secret_config() {
    local target_name="${1:?hysteria secret array required}"
    local -n config="$target_name"

    [[ "${config[SCHEMA_VERSION]-}" == '1' ]] || return 1
    [[ "${config[HY2_AUTH_PASSWORD]-}" =~ ^[A-Za-z0-9_-]{20,128}$ ]] || return 1
    [[ "${config[HY2_TLS_CERT_PATH]-}" =~ ^/[A-Za-z0-9._/+-]+$ ]] || return 1
    [[ "${config[HY2_TLS_KEY_PATH]-}" =~ ^/[A-Za-z0-9._/+-]+$ ]] || return 1
    pnm_validate_pin_sha256 "${config[HY2_TLS_PIN_SHA256]-}"
}

pnm_load_node_config() {
    local target_name="${1:?target associative array required}"
    local file="$PNM_CONFIG_DIR/node.conf"

    pnm_config_load "$file" "$target_name" \
        SCHEMA_VERSION NODE_REGION NODE_ADDRESS TIMEZONE PNM_CONFIGURED \
        XRAY_PORT XRAY_SERVER_NAME XRAY_TARGET HY2_PORT HY2_TLS_MODE
}

pnm_load_versions_config() {
    local target_name="${1:?target associative array required}"
    local file="$PNM_CONFIG_DIR/versions.conf"

    pnm_config_load "$file" "$target_name" \
        SCHEMA_VERSION XRAY_VERSION XRAY_SHA256 HY2_VERSION HY2_SHA256 APPROVED
}

pnm_load_reality_secret() {
    local target_name="${1:?target associative array required}"
    local file="$PNM_CONFIG_DIR/secrets/reality.env"

    pnm_config_load "$file" "$target_name" \
        SCHEMA_VERSION XRAY_UUID XRAY_REALITY_PRIVATE_KEY XRAY_REALITY_SHORT_ID
}

pnm_load_hysteria_secret() {
    local target_name="${1:?target associative array required}"
    local file="$PNM_CONFIG_DIR/secrets/hysteria.env"

    pnm_config_load "$file" "$target_name" \
        SCHEMA_VERSION HY2_AUTH_PASSWORD HY2_TLS_CERT_PATH HY2_TLS_KEY_PATH HY2_TLS_PIN_SHA256
}
