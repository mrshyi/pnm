#!/usr/bin/env bash

pnm_node_prompt() {
    local target_name="${1:?target variable required}"
    local prompt="${2:?prompt required}"
    local default_value="${3-}"
    local value

    if [[ -n "$default_value" ]]; then
        printf '%s [%s]: ' "$prompt" "$default_value" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi
    if ! IFS= read -r value; then
        return "$PNM_EXIT_USAGE"
    fi
    [[ -n "$value" ]] || value="$default_value"
    printf -v "$target_name" '%s' "$value"
}

pnm_node_require_value() {
    local name="${1:?option name required}"
    local value="${2-}"

    [[ -n "$value" ]] || {
        pnm_error "Missing required node value: $name"
        return "$PNM_EXIT_USAGE"
    }
}

pnm_node_validate_input() {
    local target_name="${1:?node configuration array required}"
    local versions_name="${2:?versions configuration array required}"
    local -n node_ref="$target_name"
    local -n versions_ref="$versions_name"
    local key

    for key in "${!node_ref[@]}"; do
        pnm_config_value_safe "${node_ref[$key]}" || return 1
    done
    for key in "${!versions_ref[@]}"; do
        pnm_config_value_safe "${versions_ref[$key]}" || return 1
    done
    pnm_validate_node_config "$target_name" || return 1
    pnm_validate_versions_config "$versions_name"
}

pnm_node_prepare_config_dir() {
    [[ "$PNM_CONFIG_DIR" == /* && "$PNM_CONFIG_DIR" != / ]] || {
        pnm_error "PNM_CONFIG_DIR must be an absolute non-root path: $PNM_CONFIG_DIR"
        return "$PNM_EXIT_CONFIG"
    }
    [[ ! -L "$PNM_CONFIG_DIR" ]] || {
        pnm_error "PNM configuration directory must not be a symlink: $PNM_CONFIG_DIR"
        return "$PNM_EXIT_CONFIG"
    }
    pnm_mkdir_mode 0700 "$PNM_CONFIG_DIR" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$PNM_CONFIG_DIR" && ! -L "$PNM_CONFIG_DIR" ]] || return "$PNM_EXIT_CONFIG"
}

pnm_node_write_staged_files() {
    local directory="${1:?staging directory required}"
    local node_name="${2:?node configuration array required}"
    local versions_name="${3:?versions configuration array required}"
    local -n node_ref="$node_name"
    local -n versions_ref="$versions_name"

    printf 'SCHEMA_VERSION=1\nNODE_REGION=%s\nTIMEZONE=%s\nPNM_CONFIGURED=no\nXRAY_PORT=%s\nXRAY_SERVER_NAME=%s\nXRAY_TARGET=%s\nHY2_PORT=%s\nHY2_TLS_MODE=%s\n' \
        "${node_ref[NODE_REGION]}" "${node_ref[TIMEZONE]}" "${node_ref[XRAY_PORT]}" \
        "${node_ref[XRAY_SERVER_NAME]}" "${node_ref[XRAY_TARGET]}" "${node_ref[HY2_PORT]}" \
        "${node_ref[HY2_TLS_MODE]}" >"$directory/node.conf" || return "$PNM_EXIT_CANTCREAT"
    printf 'SCHEMA_VERSION=1\nXRAY_VERSION=%s\nXRAY_SHA256=%s\nHY2_VERSION=%s\nHY2_SHA256=%s\nAPPROVED=yes\n' \
        "${versions_ref[XRAY_VERSION]}" "${versions_ref[XRAY_SHA256]}" \
        "${versions_ref[HY2_VERSION]}" "${versions_ref[HY2_SHA256]}" >"$directory/versions.conf" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$directory/node.conf" "$directory/versions.conf" || return "$PNM_EXIT_NOPERM"
}

pnm_node_init() {
    local replace_existing="${1:?replace mode required}"
    shift
    local region='' timezone='' xray_port='' server_name='' target=''
    local hy2_port='' tls_mode=''
    local xray_version='' xray_sha256='' hy2_version='' hy2_sha256=''
    local force=0 argument temp_dir node_stage versions_stage rc
    local node_file="$PNM_CONFIG_DIR/node.conf"
    local versions_file="$PNM_CONFIG_DIR/versions.conf"
    local -A existing_node=() existing_versions=()
    local -A node_config=() versions_config=()

    while (($# > 0)); do
        argument="$1"
        shift
        case "$argument" in
            --region) (($# > 0)) || { pnm_error '--region requires a value'; return "$PNM_EXIT_USAGE"; }; region="$1"; shift ;;
            --timezone) (($# > 0)) || { pnm_error '--timezone requires a value'; return "$PNM_EXIT_USAGE"; }; timezone="$1"; shift ;;
            --xray-port) (($# > 0)) || { pnm_error '--xray-port requires a value'; return "$PNM_EXIT_USAGE"; }; xray_port="$1"; shift ;;
            --server-name) (($# > 0)) || { pnm_error '--server-name requires a value'; return "$PNM_EXIT_USAGE"; }; server_name="$1"; shift ;;
            --target) (($# > 0)) || { pnm_error '--target requires a value'; return "$PNM_EXIT_USAGE"; }; target="$1"; shift ;;
            --hy2-port) (($# > 0)) || { pnm_error '--hy2-port requires a value'; return "$PNM_EXIT_USAGE"; }; hy2_port="$1"; shift ;;
            --tls-mode) (($# > 0)) || { pnm_error '--tls-mode requires a value'; return "$PNM_EXIT_USAGE"; }; tls_mode="$1"; shift ;;
            --xray-version) (($# > 0)) || { pnm_error '--xray-version requires a value'; return "$PNM_EXIT_USAGE"; }; xray_version="$1"; shift ;;
            --xray-sha256) (($# > 0)) || { pnm_error '--xray-sha256 requires a value'; return "$PNM_EXIT_USAGE"; }; xray_sha256="$1"; shift ;;
            --hy2-version) (($# > 0)) || { pnm_error '--hy2-version requires a value'; return "$PNM_EXIT_USAGE"; }; hy2_version="$1"; shift ;;
            --hy2-sha256) (($# > 0)) || { pnm_error '--hy2-sha256 requires a value'; return "$PNM_EXIT_USAGE"; }; hy2_sha256="$1"; shift ;;
            --force) force=1 ;;
            -h | --help) pnm_print_help node; return "$PNM_EXIT_OK" ;;
            *) pnm_error "Unknown node option: $argument"; return "$PNM_EXIT_USAGE" ;;
        esac
    done

    pnm_require_root || return $?

    if ((replace_existing == 0)) && ((force == 0)) && { [[ -e "$node_file" || -L "$node_file" || -e "$versions_file" || -L "$versions_file" ]]; }; then
        pnm_error 'Node configuration already exists; use `pnm node change` or `pnm node init --force`.'
        return "$PNM_EXIT_CONFIG"
    fi

    if [[ -f "$node_file" && ! -L "$node_file" ]]; then
        if pnm_load_node_config existing_node && pnm_validate_node_config existing_node; then
            [[ -n "$region" ]] || region="${existing_node[NODE_REGION]}"
            [[ -n "$timezone" ]] || timezone="${existing_node[TIMEZONE]}"
            [[ -n "$xray_port" ]] || xray_port="${existing_node[XRAY_PORT]}"
            [[ -n "$server_name" ]] || server_name="${existing_node[XRAY_SERVER_NAME]}"
            [[ -n "$target" ]] || target="${existing_node[XRAY_TARGET]}"
            [[ -n "$hy2_port" ]] || hy2_port="${existing_node[HY2_PORT]}"
            [[ -n "$tls_mode" ]] || tls_mode="${existing_node[HY2_TLS_MODE]}"
            [[ "${existing_node[PNM_CONFIGURED]}" == no ]] || {
                pnm_error 'The managed node is already configured; use core-specific apply commands or restore a reviewed backup.'
                return "$PNM_EXIT_CONFIG"
            }
        fi
    fi
    if [[ -f "$versions_file" && ! -L "$versions_file" ]] && pnm_load_versions_config existing_versions && pnm_validate_versions_config existing_versions; then
        [[ -n "$xray_version" ]] || xray_version="${existing_versions[XRAY_VERSION]}"
        [[ -n "$xray_sha256" ]] || xray_sha256="${existing_versions[XRAY_SHA256]}"
        [[ -n "$hy2_version" ]] || hy2_version="${existing_versions[HY2_VERSION]}"
        [[ -n "$hy2_sha256" ]] || hy2_sha256="${existing_versions[HY2_SHA256]}"
    fi
    [[ -n "$timezone" ]] || timezone='UTC'
    [[ -n "$xray_port" ]] || xray_port='443'
    [[ -n "$hy2_port" ]] || hy2_port='8443'
    [[ -n "$tls_mode" ]] || tls_mode='selfsigned-pin'

    if pnm_is_tty; then
        pnm_node_prompt region 'Node region (lowercase, for example osaka)' "$region" || return $?
        pnm_node_prompt timezone 'Timezone' "$timezone" || return $?
        pnm_node_prompt server_name 'Xray REALITY server name' "$server_name" || return $?
        pnm_node_prompt target 'Xray REALITY target host:port' "$target" || return $?
        pnm_node_prompt xray_port 'Xray listen port' "$xray_port" || return $?
        pnm_node_prompt hy2_port 'Hysteria2 listen port' "$hy2_port" || return $?
        pnm_node_prompt tls_mode 'Hysteria2 TLS mode (selfsigned-pin|external-ca)' "$tls_mode" || return $?
        pnm_node_prompt xray_version 'Pinned Xray version, for example v1.8.24' "$xray_version" || return $?
        pnm_node_prompt xray_sha256 'Xray SHA-256' "$xray_sha256" || return $?
        pnm_node_prompt hy2_version 'Pinned Hysteria2 version, for example v2.6.3' "$hy2_version" || return $?
        pnm_node_prompt hy2_sha256 'Hysteria2 SHA-256' "$hy2_sha256" || return $?
    else
        pnm_node_require_value '--region' "$region" || return $?
        pnm_node_require_value '--server-name' "$server_name" || return $?
        pnm_node_require_value '--target' "$target" || return $?
        pnm_node_require_value '--xray-version' "$xray_version" || return $?
        pnm_node_require_value '--xray-sha256' "$xray_sha256" || return $?
        pnm_node_require_value '--hy2-version' "$hy2_version" || return $?
        pnm_node_require_value '--hy2-sha256' "$hy2_sha256" || return $?
    fi

    pnm_node_prepare_config_dir || return $?

    node_config=(
        [SCHEMA_VERSION]=1 [NODE_REGION]="$region" [TIMEZONE]="$timezone" [PNM_CONFIGURED]=no
        [XRAY_PORT]="$xray_port" [XRAY_SERVER_NAME]="$server_name" [XRAY_TARGET]="$target"
        [HY2_PORT]="$hy2_port" [HY2_TLS_MODE]="$tls_mode"
    )
    versions_config=(
        [SCHEMA_VERSION]=1 [XRAY_VERSION]="$xray_version" [XRAY_SHA256]="$xray_sha256"
        [HY2_VERSION]="$hy2_version" [HY2_SHA256]="$hy2_sha256" [APPROVED]=yes
    )
    if ! pnm_node_validate_input node_config versions_config; then
        pnm_error 'Node values are invalid; check ports, host names, versions, and SHA-256 values.'
        return "$PNM_EXIT_CONFIG"
    fi

    temp_dir="$(pnm_make_temp_dir)" || return $?
    node_stage="$temp_dir/node.conf"
    versions_stage="$temp_dir/versions.conf"
    pnm_node_write_staged_files "$temp_dir" node_config versions_config || return $?

    pnm_tx_begin node-init || return $?
    pnm_tx_add_rollback pnm_tx_restore_written_files || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run node_config pnm_tx_write_file "$node_stage" "$node_file" node_config 0600; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run versions_config pnm_tx_write_file "$versions_stage" "$versions_file" versions_config 0600; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_commit; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    pnm_tx_close || return $?

    if ((PNM_DRY_RUN == 1)); then
        pnm_success 'Node configuration passed validation (dry run; no files changed).'
    else
        pnm_success "Node configuration saved under $PNM_CONFIG_DIR."
        pnm_info 'Next: sudo pnm node validate && sudo pnm install --apply --yes'
    fi
}

pnm_node_show() {
    local -A node_config=() versions_config=()

    pnm_load_node_config node_config || {
        pnm_error "Node configuration is missing or unreadable: $PNM_CONFIG_DIR/node.conf"
        return "$PNM_EXIT_CONFIG"
    }
    pnm_load_versions_config versions_config || {
        pnm_error "Version manifest is missing or unreadable: $PNM_CONFIG_DIR/versions.conf"
        return "$PNM_EXIT_CONFIG"
    }
    pnm_validate_node_config node_config || { pnm_error 'Node configuration values are invalid.'; return "$PNM_EXIT_CONFIG"; }
    pnm_validate_versions_config versions_config || { pnm_error 'Version manifest values are invalid.'; return "$PNM_EXIT_CONFIG"; }

    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.node.v1","config_dir":%s,"node":{"region":%s,"timezone":%s,"configured":%s,"xray_port":%s,"server_name":%s,"target":%s,"hy2_port":%s,"tls_mode":%s},"versions":{"xray":%s,"xray_sha256":%s,"hysteria2":%s,"hysteria2_sha256":%s}}\n' \
            "$(pnm_json_string "$PNM_CONFIG_DIR")" "$(pnm_json_string "${node_config[NODE_REGION]}")" \
            "$(pnm_json_string "${node_config[TIMEZONE]}")" "$(pnm_json_string "${node_config[PNM_CONFIGURED]}")" \
            "$(pnm_json_string "${node_config[XRAY_PORT]}")" "$(pnm_json_string "${node_config[XRAY_SERVER_NAME]}")" \
            "$(pnm_json_string "${node_config[XRAY_TARGET]}")" "$(pnm_json_string "${node_config[HY2_PORT]}")" \
            "$(pnm_json_string "${node_config[HY2_TLS_MODE]}")" "$(pnm_json_string "${versions_config[XRAY_VERSION]}")" \
            "$(pnm_json_string "${versions_config[XRAY_SHA256]}")" "$(pnm_json_string "${versions_config[HY2_VERSION]}")" \
            "$(pnm_json_string "${versions_config[HY2_SHA256]}")"
        return 0
    fi

    printf 'PNM node\n'
    printf '  region: %s\n  timezone: %s\n  configured: %s\n' \
        "${node_config[NODE_REGION]}" "${node_config[TIMEZONE]}" "${node_config[PNM_CONFIGURED]}"
    printf '  xray: %s -> %s (%s)\n' "${node_config[XRAY_PORT]}" "${node_config[XRAY_SERVER_NAME]}" "${node_config[XRAY_TARGET]}"
    printf '  hysteria2: %s (%s)\n' "${node_config[HY2_PORT]}" "${node_config[HY2_TLS_MODE]}"
    printf '  versions: xray %s; hysteria2 %s\n' "${versions_config[XRAY_VERSION]}" "${versions_config[HY2_VERSION]}"
}

pnm_node_validate() {
    local -A node_config=() versions_config=()
    local node_valid=0 versions_valid=0

    if pnm_load_node_config node_config && pnm_validate_node_config node_config; then node_valid=1; fi
    if pnm_load_versions_config versions_config && pnm_validate_versions_config versions_config; then versions_valid=1; fi
    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.node-validation.v1","node_config":%s,"versions_config":%s,"valid":%s}\n' \
            "$([[ "$node_valid" -eq 1 ]] && printf true || printf false)" \
            "$([[ "$versions_valid" -eq 1 ]] && printf true || printf false)" \
            "$([[ "$node_valid" -eq 1 && "$versions_valid" -eq 1 ]] && printf true || printf false)"
    else
        if ((node_valid == 1)); then pnm_success "node.conf is valid - $PNM_CONFIG_DIR/node.conf"; else pnm_error "node.conf is invalid or missing - $PNM_CONFIG_DIR/node.conf"; fi
        if ((versions_valid == 1)); then pnm_success "versions.conf is valid - $PNM_CONFIG_DIR/versions.conf"; else pnm_error "versions.conf is invalid or missing - $PNM_CONFIG_DIR/versions.conf"; fi
    fi
    if ((node_valid == 1 && versions_valid == 1)); then
        return "$PNM_EXIT_OK"
    fi
    return "$PNM_EXIT_CONFIG"
}

pnm_node_command() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init | add) pnm_node_init 0 "$@" ;;
        change) pnm_node_init 1 "$@" ;;
        show | info)
            (($# == 0)) || { pnm_error 'Usage: pnm node show'; return "$PNM_EXIT_USAGE"; }
            pnm_node_show
            ;;
        validate | check)
            (($# == 0)) || { pnm_error 'Usage: pnm node validate'; return "$PNM_EXIT_USAGE"; }
            pnm_node_validate
            ;;
        help | -h | --help) pnm_print_help node ;;
        *) pnm_error "Unknown node action: $action"; return "$PNM_EXIT_USAGE" ;;
    esac
}
