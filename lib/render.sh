#!/usr/bin/env bash

pnm_render_validate_inputs() {
    local node_name="${1:?node config array required}"
    local reality_name="${2:?reality secret array required}"
    local hysteria_name="${3:?hysteria secret array required}"

    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_reality_secret_config "$reality_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
}

pnm_yaml_scalar() {
    local value="${1-}"
    value="${value//\'/\'\'}"
    printf "'%s'" "$value"
}

pnm_render_xray_config() {
    local node_name="${1:?node config array required}"
    local reality_name="${2:?reality secret array required}"
    local -n node="$node_name"
    local -n reality="$reality_name"

    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_reality_secret_config "$reality_name" || return "$PNM_EXIT_CONFIG"
    cat <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${node[XRAY_PORT]},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": $(pnm_json_string "${reality[XRAY_UUID]}"), "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": $(pnm_json_string "${node[XRAY_TARGET]}"),
          "xver": 0,
          "serverNames": [$(pnm_json_string "${node[XRAY_SERVER_NAME]}")],
          "privateKey": $(pnm_json_string "${reality[XRAY_REALITY_PRIVATE_KEY]}"),
          "shortIds": [$(pnm_json_string "${reality[XRAY_REALITY_SHORT_ID]}")]
        }
      }
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
}

pnm_render_hysteria_config() {
    local node_name="${1:?node config array required}"
    local hysteria_name="${2:?hysteria secret array required}"
    local -n node="$node_name"
    local -n hysteria="$hysteria_name"

    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
    cat <<EOF
listen: :${node[HY2_PORT]}
tls:
  cert: $(pnm_yaml_scalar "${hysteria[HY2_TLS_CERT_PATH]}")
  key: $(pnm_yaml_scalar "${hysteria[HY2_TLS_KEY_PATH]}")
auth:
  type: password
  password: $(pnm_yaml_scalar "${hysteria[HY2_AUTH_PASSWORD]}")
masquerade:
  type: proxy
  proxy:
    url: $(pnm_yaml_scalar "https://${node[XRAY_SERVER_NAME]}")
EOF
}

pnm_render_reality_secret_config() {
    local reality_name="${1:?reality secret array required}"
    local -n reality="$reality_name"

    pnm_validate_reality_secret_config "$reality_name" || return "$PNM_EXIT_CONFIG"
    printf 'SCHEMA_VERSION=1\nXRAY_UUID=%s\nXRAY_REALITY_PRIVATE_KEY=%s\nXRAY_REALITY_SHORT_ID=%s\n' \
        "${reality[XRAY_UUID]}" \
        "${reality[XRAY_REALITY_PRIVATE_KEY]}" \
        "${reality[XRAY_REALITY_SHORT_ID]}"
}

pnm_render_hysteria_secret_config() {
    local hysteria_name="${1:?hysteria secret array required}"
    local -n hysteria="$hysteria_name"

    pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
    printf 'SCHEMA_VERSION=1\nHY2_AUTH_PASSWORD=%s\nHY2_TLS_CERT_PATH=%s\nHY2_TLS_KEY_PATH=%s\nHY2_TLS_PIN_SHA256=%s\n' \
        "${hysteria[HY2_AUTH_PASSWORD]}" \
        "${hysteria[HY2_TLS_CERT_PATH]}" \
        "${hysteria[HY2_TLS_KEY_PATH]}" \
        "${hysteria[HY2_TLS_PIN_SHA256]}"
}

pnm_render_write_file() {
    local render_function="${1:?render function required}"
    local destination="${2:?destination required}"
    shift 2
    local parent temp_file

    parent="$(dirname -- "$destination")"
    [[ -d "$parent" && ! -L "$parent" ]] || return "$PNM_EXIT_CANTCREAT"
    temp_file="$(mktemp "$parent/.pnm-render.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    if ! "$render_function" "$@" >"$temp_file"; then
        rm -f -- "$temp_file"
        return "$PNM_EXIT_CONFIG"
    fi
    chmod 0600 -- "$temp_file"
    mv -f -- "$temp_file" "$destination"
}
