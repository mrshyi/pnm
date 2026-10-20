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

pnm_xray_config_matches_node() {
    local node_name="${1:?node config array required}"
    local reality_name="${2:?REALITY secret array required}"
    local expected comparison rc

    [[ -f "$PNM_XRAY_CONFIG" && ! -L "$PNM_XRAY_CONFIG" ]] || return "$PNM_EXIT_UNAVAILABLE"
    expected="$(mktemp -- "${TMPDIR:-/tmp}/pnm-xray-config.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$expected" || { rm -f -- "$expected"; return "$PNM_EXIT_NOPERM"; }
    if pnm_render_xray_config "$node_name" "$reality_name" >"$expected"; then
        if comparison="$(pnm_xray_config_compare_files "$expected" "$PNM_XRAY_CONFIG")"; then
            rc=0
        else
            rc=$?
        fi
    else
        rc="$PNM_EXIT_CONFIG"
    fi
    rm -f -- "$expected"
    case "$rc" in
        0) ;;
        1)
            if [[ "$PNM_OUTPUT_MODE" == json ]]; then
                pnm_error "Xray runtime configuration drift; $comparison"
            else
                pnm_warn "Xray runtime configuration drift; $comparison"
            fi
            ;;
        "$PNM_EXIT_CONFIG") pnm_error 'Xray runtime configuration is invalid JSON; consistency cannot be determined.' ;;
        *) return "$rc" ;;
    esac
    return "$rc"
}

pnm_xray_config_compare_files() {
    local expected="${1:?expected Xray config required}"
    local runtime="${2:?runtime Xray config required}"

    python3 - "$expected" "$runtime" <<'PY'
import json
import sys

def field_name(key):
    text = str(key)
    known = {
        "log", "loglevel", "inbounds", "listen", "port", "protocol", "settings",
        "clients", "id", "flow", "decryption", "streamSettings", "network",
        "security", "realitySettings", "show", "dest", "xver", "serverNames",
        "privateKey", "shortIds", "outbounds", "tag",
    }
    return text if text in known else "<field>"

def differences(expected, actual, path=""):
    if type(expected) is not type(actual):
        return [path or "$"]
    if isinstance(expected, dict):
        result = []
        for key in sorted(expected.keys() | actual.keys(), key=str):
            child = f"{path}.{field_name(key)}" if path else field_name(key)
            if key not in expected or key not in actual:
                result.append(child)
            else:
                result.extend(differences(expected[key], actual[key], child))
        return result
    if isinstance(expected, list):
        result = []
        if len(expected) != len(actual):
            result.append(f"{path}.length" if path else "$.length")
        for index, (left, right) in enumerate(zip(expected, actual)):
            result.extend(differences(left, right, f"{path}[{index}]"))
        return result
    return [] if expected == actual else [path or "$"]

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        expected = json.load(source)
    with open(sys.argv[2], encoding="utf-8") as source:
        actual = json.load(source)
except (OSError, UnicodeError, json.JSONDecodeError):
    print("runtime JSON could not be parsed")
    sys.exit(78)

fields = differences(expected, actual)
if fields:
    fields = fields[:32]
    suffix = ", ..." if len(fields) == 32 else ""
    print("drift fields: " + ", ".join(fields) + suffix)
    sys.exit(1)

print("consistent")
PY
}

pnm_xray_config_runtime_values() {
    local config_file="${1:?Xray config path required}"

    [[ -f "$config_file" && ! -L "$config_file" && -r "$config_file" ]] || return "$PNM_EXIT_CONFIG"
    python3 - "$config_file" <<'PY'
import json
import sys

def safe(value):
    return isinstance(value, str) and not any(ord(char) < 32 or ord(char) == 127 for char in value)

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        config = json.load(source)
    reality_inbounds = [
        inbound for inbound in config.get("inbounds", [])
        if isinstance(inbound, dict)
        and isinstance(inbound.get("streamSettings"), dict)
        and inbound["streamSettings"].get("security") == "reality"
    ]
    if len(reality_inbounds) != 1:
        raise ValueError("expected exactly one REALITY inbound")
    inbound = reality_inbounds[0]
    stream = inbound["streamSettings"]
    reality = stream.get("realitySettings", {})
    names = reality.get("serverNames", [])
    port = inbound.get("port")
    destination = reality.get("dest")
    network = stream.get("network")
    values = [str(port), destination, ",".join(names), network]
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise ValueError("invalid REALITY port")
    if not isinstance(names, list) or not names or not all(safe(name) and name and "," not in name for name in names):
        raise ValueError("invalid serverNames")
    if not isinstance(destination, str) or not destination or not isinstance(network, str) or not network:
        raise ValueError("invalid REALITY destination or network")
    if not all(safe(value) for value in values):
        raise ValueError("invalid public REALITY fields")
    print("\t".join(values))
except (OSError, UnicodeError, ValueError, TypeError, AttributeError, json.JSONDecodeError) as error:
    print(f"invalid Xray runtime configuration: {error}", file=sys.stderr)
    sys.exit(1)
PY
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

# Hysteria v2.13.0 has no independent config-check command. Require exact
# output from PNM's validated deterministic renderer; this avoids starting a
# server or binding a port and deliberately rejects custom YAML.
pnm_hysteria_config_validate_candidate() {
    local candidate="${1:?candidate config required}"
    local node_name="${2:?node config array required}"
    local hysteria_name="${3:?hysteria secret array required}"
    local -n node="$node_name"
    local -n hysteria="$hysteria_name"
    local -a lines=()

    [[ -f "$candidate" && ! -L "$candidate" && -r "$candidate" ]] || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config "$node_name" && pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
    mapfile -t lines <"$candidate" || return "$PNM_EXIT_CONFIG"
    ((${#lines[@]} == 11)) || return "$PNM_EXIT_CONFIG"
    [[ "${lines[0]}" == "listen: :${node[HY2_PORT]}" &&
        "${lines[1]}" == 'tls:' &&
        "${lines[2]}" == "  cert: $(pnm_yaml_scalar "${hysteria[HY2_TLS_CERT_PATH]}")" &&
        "${lines[3]}" == "  key: $(pnm_yaml_scalar "${hysteria[HY2_TLS_KEY_PATH]}")" &&
        "${lines[4]}" == 'auth:' &&
        "${lines[5]}" == '  type: password' &&
        "${lines[6]}" == "  password: $(pnm_yaml_scalar "${hysteria[HY2_AUTH_PASSWORD]}")" &&
        "${lines[7]}" == 'masquerade:' &&
        "${lines[8]}" == '  type: proxy' &&
        "${lines[9]}" == '  proxy:' &&
        "${lines[10]}" == "    url: $(pnm_yaml_scalar "https://${node[XRAY_SERVER_NAME]}")" ]]
}

pnm_hysteria_config_matches_node() {
    local node_name="${1:?node config array required}"
    local hysteria_name="${2:?hysteria secret array required}"

    [[ -f "$PNM_HY2_CONFIG" && ! -L "$PNM_HY2_CONFIG" && -r "$PNM_HY2_CONFIG" ]] || return "$PNM_EXIT_UNAVAILABLE"
    pnm_hysteria_config_validate_candidate "$PNM_HY2_CONFIG" "$node_name" "$hysteria_name"
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
