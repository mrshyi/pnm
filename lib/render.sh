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
    # Caller-local arrays may themselves be named node/reality. A same-name
    # nameref would hide them under Bash dynamic scope during post-health.
    local -n _pnm_xray_node="$node_name"
    local -n _pnm_xray_reality="$reality_name"

    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_reality_secret_config "$reality_name" || return "$PNM_EXIT_CONFIG"
    cat <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${_pnm_xray_node[XRAY_PORT]},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": $(pnm_json_string "${_pnm_xray_reality[XRAY_UUID]}"), "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": $(pnm_json_string "${_pnm_xray_node[XRAY_TARGET]}"),
          "xver": 0,
          "serverNames": [$(pnm_json_string "${_pnm_xray_node[XRAY_SERVER_NAME]}")],
          "privateKey": $(pnm_json_string "${_pnm_xray_reality[XRAY_REALITY_PRIVATE_KEY]}"),
          "shortIds": [$(pnm_json_string "${_pnm_xray_reality[XRAY_REALITY_SHORT_ID]}")]
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
        1) pnm_error "Xray runtime configuration drift; $comparison" ;;
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

# JSON decoding ignores whitespace and object-key order, while values, types,
# and array order remain significant for the runtime configuration.
def field_name(key):
    text = str(key)
    known = {
        "log", "loglevel", "inbounds", "listen", "port", "protocol", "settings",
        "clients", "id", "flow", "decryption", "streamSettings", "network",
        "security", "realitySettings", "show", "dest", "xver", "serverNames",
        "privateKey", "shortIds", "outbounds", "tag",
    }
    return text if text in known else "<field>"

def differences(expected, actual, path="$"):
    if type(expected) is not type(actual):
        return [path or "$"]
    if isinstance(expected, dict):
        result = []
        for key in sorted(expected.keys() | actual.keys(), key=str):
            child = f"{path}.{field_name(key)}"
            if key not in expected or key not in actual:
                result.append(child)
            else:
                result.extend(differences(expected[key], actual[key], child))
        return result
    if isinstance(expected, list):
        result = []
        if len(expected) != len(actual):
            result.append(f"{path}.length")
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
    local -n _pnm_hy2_node="$node_name"
    local -n _pnm_hy2_secret="$hysteria_name"

    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
    cat <<EOF
listen: :${_pnm_hy2_node[HY2_PORT]}
tls:
  cert: $(pnm_yaml_scalar "${_pnm_hy2_secret[HY2_TLS_CERT_PATH]}")
  key: $(pnm_yaml_scalar "${_pnm_hy2_secret[HY2_TLS_KEY_PATH]}")
auth:
  type: password
  password: $(pnm_yaml_scalar "${_pnm_hy2_secret[HY2_AUTH_PASSWORD]}")
masquerade:
  type: proxy
  proxy:
    url: $(pnm_yaml_scalar "https://${_pnm_hy2_node[XRAY_SERVER_NAME]}")
EOF
}

# Decode the scalar subset emitted by PNM's Hysteria2 renderer. Unsupported
# YAML syntax is rejected so consistency checks never guess at its meaning.
pnm_hysteria_yaml_decode_scalar() {
    local raw="${1-}"
    local target_name="${2:?decoded scalar target required}"
    local decoded='' body char next_char index=0 length
    local -n result="$target_name"

    length="${#raw}"
    if [[ "$raw" == \'* ]]; then
        ((length >= 2)) && [[ "${raw: -1}" == \' ]] || return "$PNM_EXIT_CONFIG"
        body="${raw:1:length-2}"
        while ((index < ${#body})); do
            char="${body:index:1}"
            if [[ "$char" == \' ]]; then
                next_char="${body:index+1:1}"
                [[ "$next_char" == \' ]] || return "$PNM_EXIT_CONFIG"
                decoded+="'"
                ((index += 2))
            else
                decoded+="$char"
                ((index += 1))
            fi
        done
    elif [[ "$raw" == \"* ]]; then
        ((length >= 2)) && [[ "${raw: -1}" == \" ]] || return "$PNM_EXIT_CONFIG"
        body="${raw:1:length-2}"
        while ((index < ${#body})); do
            char="${body:index:1}"
            if [[ "$char" == \\ ]]; then
                ((index + 1 < ${#body})) || return "$PNM_EXIT_CONFIG"
                next_char="${body:index+1:1}"
                case "$next_char" in
                    \\ | \" | /) decoded+="$next_char" ;;
                    n) decoded+=$'\n' ;;
                    r) decoded+=$'\r' ;;
                    t) decoded+=$'\t' ;;
                    *) return "$PNM_EXIT_CONFIG" ;;
                esac
                ((index += 2))
            else
                [[ "$char" != \" ]] || return "$PNM_EXIT_CONFIG"
                decoded+="$char"
                ((index += 1))
            fi
        done
    else
        [[ -n "$raw" && "$raw" != '['* && "$raw" != '{'* && "$raw" != '|'* && "$raw" != '>'* ]] || return "$PNM_EXIT_CONFIG"
        if [[ "$raw" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
            raw="${BASH_REMATCH[1]}"
        fi
        decoded="$raw"
    fi

    result="$decoded"
}

pnm_hysteria_config_parse_candidate() {
    local candidate="${1:?candidate config required}"
    local target_name="${2:?parsed field map required}"
    local -n fields="$target_name"
    local line indent key raw parent path value parsed=0
    local -a lines=() stack_indents=() stack_paths=()
    local -A seen=()

    fields=()
    if ! mapfile -t lines <"$candidate" 2>/dev/null; then
        [[ -e "$candidate" || -L "$candidate" ]] && return "$PNM_EXIT_NOPERM"
        return "$PNM_EXIT_UNAVAILABLE"
    fi
    for line in "${lines[@]}"; do
        line="${line%$'\r'}"
        while [[ "$line" == *' ' || "$line" == *$'\t' ]]; do line="${line%?}"; done
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" != *$'\t'* ]] || return "$PNM_EXIT_CONFIG"
        [[ "$line" =~ ^([[:space:]]*)([A-Za-z][A-Za-z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)$ ]] || return "$PNM_EXIT_CONFIG"
        indent="${#BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
        raw="${BASH_REMATCH[3]}"
        while ((${#stack_indents[@]} > 0)) && ((indent <= stack_indents[${#stack_indents[@]} - 1])); do
            unset 'stack_indents[-1]' 'stack_paths[-1]'
        done
        parent=''
        if ((${#stack_paths[@]} > 0)); then
            parent="${stack_paths[${#stack_paths[@]} - 1]}"
        fi
        path="${parent:+$parent.}$key"

        case "$path" in
            tls | auth | masquerade | masquerade.proxy)
                [[ -z "$raw" && -z "${seen[$path]+present}" ]] || return "$PNM_EXIT_CONFIG"
                seen[$path]=map
                stack_indents+=("$indent")
                stack_paths+=("$path")
                parsed=1
                ;;
            listen | tls.cert | tls.key | auth.type | auth.password | masquerade.type | masquerade.proxy.url)
                [[ -n "$raw" && -z "${seen[$path]+present}" ]] || return "$PNM_EXIT_CONFIG"
                pnm_hysteria_yaml_decode_scalar "$raw" value || return "$PNM_EXIT_CONFIG"
                fields[$path]="$value"
                seen[$path]=scalar
                parsed=1
                ;;
            *) return "$PNM_EXIT_CONFIG" ;;
        esac
    done
    ((parsed == 1)) || return "$PNM_EXIT_CONFIG"
}

# Hysteria v2.13.0 has no independent config-check command. Compare the
# supported PNM YAML subset against the deterministic rendered configuration.
pnm_hysteria_config_validate_candidate() {
    local candidate="${1:?candidate config required}"
    local node_name="${2:?node config array required}"
    local hysteria_name="${3:?hysteria secret array required}"
    local expected expected_rc path
    local -a differences=() required_fields=(listen tls.cert tls.key auth.type auth.password masquerade.type masquerade.proxy.url)
    local -A expected_fields=() actual_fields=()

    PNM_HY2_CONFIG_DIAGNOSTIC=''

    if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
        PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration is missing'
        return "$PNM_EXIT_UNAVAILABLE"
    fi
    if [[ -L "$candidate" || ! -f "$candidate" ]]; then
        PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration is damaged or is not a regular file'
        return "$PNM_EXIT_CONFIG"
    fi
    if [[ ! -r "$candidate" ]]; then
        PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration cannot be read due to permissions'
        return "$PNM_EXIT_NOPERM"
    fi
    pnm_validate_node_config "$node_name" && pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"

    expected="$(mktemp -- "${TMPDIR:-/tmp}/pnm-hysteria-config.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$expected" || { rm -f -- "$expected"; return "$PNM_EXIT_NOPERM"; }
    if ! pnm_render_hysteria_config "$node_name" "$hysteria_name" >"$expected"; then
        rm -f -- "$expected"
        PNM_HY2_CONFIG_DIAGNOSTIC='PNM could not render the expected configuration'
        return "$PNM_EXIT_CONFIG"
    fi
    if ! pnm_hysteria_config_parse_candidate "$expected" expected_fields; then
        rm -f -- "$expected"
        PNM_HY2_CONFIG_DIAGNOSTIC='PNM rendered an invalid configuration'
        return "$PNM_EXIT_SOFTWARE"
    fi
    if pnm_hysteria_config_parse_candidate "$candidate" actual_fields; then
        :
    else
        expected_rc=$?
        rm -f -- "$expected"
        if ((expected_rc == PNM_EXIT_NOPERM)); then
            PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration cannot be read due to permissions'
            return "$PNM_EXIT_NOPERM"
        fi
        if ((expected_rc == PNM_EXIT_UNAVAILABLE)); then
            PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration is missing'
            return "$PNM_EXIT_UNAVAILABLE"
        fi
        PNM_HY2_CONFIG_DIAGNOSTIC='runtime configuration is damaged or uses unsupported YAML syntax'
        return "$PNM_EXIT_CONFIG"
    fi
    rm -f -- "$expected"

    for path in "${required_fields[@]}"; do
        if [[ -z "${actual_fields[$path]+present}" || "${expected_fields[$path]}" != "${actual_fields[$path]}" ]]; then
            differences+=("$path")
        fi
    done
    if ((${#differences[@]} > 0)); then
        PNM_HY2_CONFIG_DIAGNOSTIC="runtime configuration differs from PNM settings; fields: ${differences[*]}"
        return 1
    fi
}

pnm_hysteria_config_matches_node() {
    local node_name="${1:?node config array required}"
    local hysteria_name="${2:?hysteria secret array required}"

    pnm_hysteria_config_validate_candidate "$PNM_HY2_CONFIG" "$node_name" "$hysteria_name"
}

pnm_core_runtime_listener_ready() {
    local core="${1:?core id required}" config="${2:?runtime configuration required}"
    local runtime_values port protocol
    local -A recovered_fields=()
    [[ -f "$config" && ! -L "$config" && -r "$config" ]] || return "$PNM_EXIT_SOFTWARE"
    # Inspect runtime ports rather than desired node.conf. Recovery callers
    # verify the original configuration hash; disabled policy is unchanged.
    case "$core" in
        xray)
            runtime_values="$(pnm_xray_config_runtime_values "$config")" || return "$PNM_EXIT_SOFTWARE"
            [[ "${runtime_values##*$'\t'}" == tcp ]] || return "$PNM_EXIT_SOFTWARE"
            port="${runtime_values%%$'\t'*}" protocol=tcp
            ;;
        hysteria2)
            pnm_hysteria_config_parse_candidate "$config" recovered_fields || return "$PNM_EXIT_SOFTWARE"
            [[ "${recovered_fields[listen]-}" =~ ^:([0-9]+)$ ]] || return "$PNM_EXIT_SOFTWARE"
            port="${BASH_REMATCH[1]}" protocol=udp
            ;;
        *) return "$PNM_EXIT_SOFTWARE" ;;
    esac
    pnm_validate_port "$port" && pnm_listener_present "$protocol" "$port" 26 || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_applied_config_status() {
    local core="${1:?core id required}"
    local config="${2:?runtime configuration required}"
    local record="$PNM_STATE_DIR/cores/$core/applied.env"
    local digest unit invocation
    local -A applied=()

    case "$core" in
        xray | hysteria2) ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
    if [[ ! -e "$record" && ! -L "$record" ]]; then
        printf 'unknown\n'
        return 0
    fi
    if [[ ! -f "$record" || -L "$record" || ! -r "$record" ]] ||
        ! pnm_config_load "$record" applied SCHEMA_VERSION CORE CONFIG_SHA256 SERVICE_INVOCATION_ID ||
        [[ "${applied[SCHEMA_VERSION]-}" != 1 || "${applied[CORE]-}" != "$core" ||
            ! "${applied[CONFIG_SHA256]-}" =~ ^[a-f0-9]{64}$ ||
            ! "${applied[SERVICE_INVOCATION_ID]-}" =~ ^[a-f0-9]{32}$ ]]; then
        printf 'damaged\n'
        return 0
    fi
    [[ -f "$config" && ! -L "$config" && -r "$config" ]] || {
        printf 'unknown\n'
        return 0
    }
    digest="$(sha256sum 2>/dev/null <"$config")" || {
        printf 'unknown\n'
        return 0
    }
    digest="${digest%% *}"
    case "$core" in
        xray) unit=xray.service ;;
        hysteria2) unit='hysteria-server.service' ;;
    esac
    invocation="$(pnm_systemd_show_value "$unit" InvocationID 2>/dev/null)" || {
        printf 'unknown\n'
        return 0
    }
    [[ "$invocation" =~ ^[a-fA-F0-9]{32}$ ]] || {
        printf 'unknown\n'
        return 0
    }
    if [[ "$digest" == "${applied[CONFIG_SHA256]}" && "$invocation" == "${applied[SERVICE_INVOCATION_ID]}" ]]; then
        printf 'confirmed\n'
    else
        printf 'changed\n'
    fi
}

pnm_node_core_link_status() {
    local core="${1:?core id required}"
    local node_name="${2:?node configuration array required}"
    local secret_name="${3:?Core secret array required}"
    local unit active config consistency_rc applied_status config_status=unknown diagnostic='' listener_rc protocol port
    local -n node_ref="$node_name"

    case "$core" in
        xray) unit=xray.service; config="$PNM_XRAY_CONFIG"; protocol=tcp; port="${node_ref[XRAY_PORT]}" ;;
        hysteria2) unit='hysteria-server.service'; config="$PNM_HY2_CONFIG"; protocol=udp; port="${node_ref[HY2_PORT]}" ;;
        *) printf 'unknown|unknown|unknown|unknown|unsupported Core\n'; return 0 ;;
    esac
    if ! active="$(pnm_systemd_active_state "$unit" 2>/dev/null)"; then
        printf 'unknown|unknown|unknown|unknown|service state cannot be determined\n'
        return 0
    fi
    if [[ "$active" != active ]]; then
        printf 'inactive|%s|unknown|unknown|service is %s\n' "$active" "$active"
        return 0
    fi
    if [[ "$core" == xray ]]; then
        if diagnostic="$(pnm_xray_config_matches_node "$node_name" "$secret_name" 2>&1 >/dev/null)"; then
            config_status=consistent
        else
            consistency_rc=$?
            case "$consistency_rc" in
                1) printf 'drift|%s|drift|unknown|runtime configuration differs from node.conf; %s\n' "$active" "${diagnostic#*; }" ;;
                "$PNM_EXIT_UNAVAILABLE" | "$PNM_EXIT_NOPERM") printf 'unknown|%s|unknown|unknown|runtime configuration cannot be read\n' "$active" ;;
                *) printf 'damaged|%s|damaged|unknown|runtime configuration is invalid\n' "$active" ;;
            esac
            return 0
        fi
    else
        if pnm_hysteria_config_matches_node "$node_name" "$secret_name" >/dev/null 2>&1; then
            config_status=consistent
        else
            consistency_rc=$?
            diagnostic="${PNM_HY2_CONFIG_DIAGNOSTIC:-}"
            case "$consistency_rc" in
                1) printf 'drift|%s|drift|unknown|%s\n' "$active" "$diagnostic" ;;
                "$PNM_EXIT_UNAVAILABLE" | "$PNM_EXIT_NOPERM") printf 'unknown|%s|unknown|unknown|%s\n' "$active" "${diagnostic:-runtime configuration cannot be read}" ;;
                *) printf 'damaged|%s|damaged|unknown|%s\n' "$active" "${diagnostic:-runtime configuration is invalid}" ;;
            esac
            return 0
        fi
    fi
    applied_status="$(pnm_core_applied_config_status "$core" "$config")" || {
        printf 'unknown|%s|%s|unknown|applied configuration evidence cannot be read\n' "$active" "$config_status"
        return 0
    }
    case "$applied_status" in
        confirmed)
            if pnm_listener_present "$protocol" "$port"; then
                printf 'ready|%s|%s|confirmed|configuration is verified as applied; local listener is present\n' "$active" "$config_status"
            else
                listener_rc=$?
                if ((listener_rc == 1)); then
                    printf 'unavailable|%s|%s|confirmed|expected local %s/%s listener is absent\n' "$active" "$config_status" "${protocol^^}" "$port"
                else
                    printf 'unknown|%s|%s|confirmed|local listener state cannot be determined\n' "$active" "$config_status"
                fi
            fi
            ;;
        changed) printf 'drift|%s|%s|changed|runtime file or service invocation changed since the last successful PNM apply\n' "$active" "$config_status" ;;
        damaged) printf 'unknown|%s|%s|damaged|applied configuration evidence is damaged\n' "$active" "$config_status" ;;
        *) printf 'unknown|%s|%s|unknown|no successful PNM apply record exists\n' "$active" "$config_status" ;;
    esac
}

pnm_render_reality_secret_config() {
    local reality_name="${1:?reality secret array required}"
    local -n _pnm_reality_secret="$reality_name"

    pnm_validate_reality_secret_config "$reality_name" || return "$PNM_EXIT_CONFIG"
    printf 'SCHEMA_VERSION=1\nXRAY_UUID=%s\nXRAY_REALITY_PRIVATE_KEY=%s\nXRAY_REALITY_SHORT_ID=%s\n' \
        "${_pnm_reality_secret[XRAY_UUID]}" \
        "${_pnm_reality_secret[XRAY_REALITY_PRIVATE_KEY]}" \
        "${_pnm_reality_secret[XRAY_REALITY_SHORT_ID]}"
}

pnm_render_hysteria_secret_config() {
    local hysteria_name="${1:?hysteria secret array required}"
    local -n _pnm_hy2_secret_config="$hysteria_name"

    pnm_validate_hysteria_secret_config "$hysteria_name" || return "$PNM_EXIT_CONFIG"
    printf 'SCHEMA_VERSION=1\nHY2_AUTH_PASSWORD=%s\nHY2_TLS_CERT_PATH=%s\nHY2_TLS_KEY_PATH=%s\nHY2_TLS_PIN_SHA256=%s\n' \
        "${_pnm_hy2_secret_config[HY2_AUTH_PASSWORD]}" \
        "${_pnm_hy2_secret_config[HY2_TLS_CERT_PATH]}" \
        "${_pnm_hy2_secret_config[HY2_TLS_KEY_PATH]}" \
        "${_pnm_hy2_secret_config[HY2_TLS_PIN_SHA256]}"
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
