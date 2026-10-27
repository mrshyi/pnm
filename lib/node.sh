#!/usr/bin/env bash

readonly PNM_NODE_DEFAULT_REGION='vps'
readonly PNM_NODE_DEFAULT_TIMEZONE='UTC'
readonly PNM_NODE_DEFAULT_XRAY_SERVER_NAME='www.cloudflare.com'
readonly PNM_NODE_DEFAULT_XRAY_PORT='443'
readonly PNM_NODE_DEFAULT_XRAY_TARGET_PORT='443'
readonly PNM_NODE_DEFAULT_HY2_PORT='8443'
readonly PNM_NODE_DEFAULT_HY2_TLS_MODE='selfsigned-pin'

declare -Ag PNM_NODE_LATEST_VERSIONS=()
PNM_NODE_LATEST_ERROR=''

pnm_node_fetch_url() {
    local url="${1:?URL required}"
    local destination="${2:?destination required}"

    pnm_command_exists curl || return "$PNM_EXIT_UNAVAILABLE"
    curl --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 --connect-timeout 15 --retry 2 \
        --header 'Accept: application/vnd.github+json' \
        --header 'User-Agent: pnm-node-init' \
        "$url" --output "$destination"
}

pnm_node_parse_release_tag() {
    local json_file="${1:?release metadata file required}"

    [[ -r "$json_file" ]] || return "$PNM_EXIT_CONFIG"
    sed 's/[{},]/\n/g' "$json_file" |
        awk -F '"' '$2 == "tag_name" { print $4; exit }'
}

pnm_node_parse_xray_sha256() {
    local digest_file="${1:?Xray digest file required}"

    [[ -r "$digest_file" ]] || return "$PNM_EXIT_CONFIG"
    awk -F '=' 'tolower($1) ~ /256/ {
        gsub(/[[:space:]\r]/, "", $2)
        print tolower($2)
        exit
    }' "$digest_file"
}

pnm_node_parse_hysteria_sha256() {
    local digest_file="${1:?Hysteria2 hash file required}"
    local asset_name='hysteria-linux-amd64'

    [[ -r "$digest_file" ]] || return "$PNM_EXIT_CONFIG"
    awk -v asset="$asset_name" '
        {
            line=$0
            gsub(/\r/, "", line)
            file=$NF
            sub(/^\*/, "", file)
            sub(/^.*\//, "", file)
            if (file == asset) {
                print tolower($1)
                exit
            }
            if (index(line, "(" asset ")") && line ~ /=/) {
                sub(/^.*=[[:space:]]*/, "", line)
                print tolower(line)
                exit
            }
        }
    ' "$digest_file"
}

pnm_node_uri_encode() {
    local value="${1-}"
    local character index

    local LC_ALL=C
    for ((index = 0; index < ${#value}; index += 1)); do
        character="${value:index:1}"
        case "$character" in
            [A-Za-z0-9._~-]) printf '%s' "$character" ;;
            *) printf '%%%02X' "'${character}" ;;
        esac
    done
}

pnm_node_xray_reality_public_key() {
    local private_key="${1:?REALITY private key required}"
    local public_key

    [[ -x "$PNM_XRAY_BIN" && ! -L "$PNM_XRAY_BIN" ]] || return "$PNM_EXIT_UNAVAILABLE"
    public_key="$("$PNM_XRAY_BIN" x25519 -i "$private_key" 2>/dev/null | awk -F ': ' '$1 == "Password (PublicKey)" || $1 == "Password" || $1 == "Public key" || $1 == "PublicKey" { print $2; exit }')" || return "$PNM_EXIT_CONFIG"
    [[ "$public_key" =~ ^[A-Za-z0-9_-]{43}$ ]] || return "$PNM_EXIT_CONFIG"
    printf '%s\n' "$public_key"
}

pnm_node_fetch_redirect_tag() {
    local release_url="${1:?release URL required}"
    local final_url tag

    pnm_command_exists curl || return "$PNM_EXIT_UNAVAILABLE"
    final_url="$(curl --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 --connect-timeout 15 --retry 2 \
        --header 'User-Agent: pnm-node-init' --write-out '%{url_effective}' \
        --output /dev/null "$release_url")" || return "$PNM_EXIT_UNAVAILABLE"
    case "$final_url" in
        https://github.com/*/releases/tag/*)
            tag="${final_url#*/releases/tag/}"
            tag="${tag%%\?*}"
            tag="${tag//%2F//}"
            tag="${tag//%2f//}"
            [[ -n "$tag" ]] || return "$PNM_EXIT_CONFIG"
            printf '%s\n' "$tag"
            ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
}

pnm_node_resolve_latest_tag() {
    local api_url="${1:?API URL required}"
    local release_url="${2:?release URL required}"
    local metadata_file="${3:?metadata file required}"
    local tag

    # GitHub API is preferred because it returns structured metadata. The
    # public release redirect is a rate-limit-resistant fallback for VPSes
    # whose egress policy blocks or throttles unauthenticated API requests.
    if pnm_node_fetch_url "$api_url" "$metadata_file" 2>/dev/null; then
        tag="$(pnm_node_parse_release_tag "$metadata_file")" || true
        [[ -n "$tag" ]] && {
            printf '%s\n' "$tag"
            return "$PNM_EXIT_OK"
        }
    fi
    pnm_node_fetch_redirect_tag "$release_url"
}

pnm_node_fetch_latest_versions() {
    local temp_dir xray_metadata hysteria_metadata xray_digest hysteria_digest
    local xray_tag hysteria_tag xray_version hysteria_version xray_sha256 hysteria_sha256
    local release_channel='latest'
    local xray_api_url="https://api.github.com/repos/XTLS/Xray-core/releases/${release_channel}"
    local hysteria_api_url="https://api.github.com/repos/apernet/hysteria/releases/${release_channel}"
    local xray_release_url="https://github.com/XTLS/Xray-core/releases/${release_channel}"
    local hysteria_release_url="https://github.com/apernet/hysteria/releases/${release_channel}"

    PNM_NODE_LATEST_VERSIONS=()
    PNM_NODE_LATEST_ERROR=''
    pnm_make_temp_dir temp_dir || return $?
    xray_metadata="$temp_dir/xray-release.json"
    hysteria_metadata="$temp_dir/hysteria-release.json"
    xray_digest="$temp_dir/xray.dgst"
    hysteria_digest="$temp_dir/hysteria.hashes"

    xray_tag="$(pnm_node_resolve_latest_tag "$xray_api_url" "$xray_release_url" "$xray_metadata")" || {
        PNM_NODE_LATEST_ERROR='Xray stable release metadata is unavailable'
        return "$PNM_EXIT_UNAVAILABLE"
    }
    [[ "$xray_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || {
        PNM_NODE_LATEST_ERROR='Xray stable release tag is invalid'
        return "$PNM_EXIT_CONFIG"
    }
    xray_version="$xray_tag"
    pnm_node_fetch_url \
        "https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-64.zip.dgst" \
        "$xray_digest" || {
        PNM_NODE_LATEST_ERROR='Xray official SHA-256 file is unavailable'
        return "$PNM_EXIT_UNAVAILABLE"
    }
    xray_sha256="$(pnm_node_parse_xray_sha256 "$xray_digest")" || {
        PNM_NODE_LATEST_ERROR='Xray official SHA-256 file is invalid'
        return "$PNM_EXIT_CONFIG"
    }
    pnm_validate_sha256 "$xray_sha256" || {
        PNM_NODE_LATEST_ERROR='Xray official SHA-256 value is invalid'
        return "$PNM_EXIT_CONFIG"
    }

    hysteria_tag="$(pnm_node_resolve_latest_tag "$hysteria_api_url" "$hysteria_release_url" "$hysteria_metadata")" || {
        PNM_NODE_LATEST_ERROR='Hysteria2 stable release metadata is unavailable'
        return "$PNM_EXIT_UNAVAILABLE"
    }
    hysteria_version="${hysteria_tag##*/}"
    [[ "$hysteria_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9.-]+)?$ ]] || {
        PNM_NODE_LATEST_ERROR='Hysteria2 stable release tag is invalid'
        return "$PNM_EXIT_CONFIG"
    }
    pnm_node_fetch_url \
        "https://github.com/apernet/hysteria/releases/download/app%2F${hysteria_version}/hashes.txt" \
        "$hysteria_digest" || {
        PNM_NODE_LATEST_ERROR='Hysteria2 official SHA-256 file is unavailable'
        return "$PNM_EXIT_UNAVAILABLE"
    }
    hysteria_sha256="$(pnm_node_parse_hysteria_sha256 "$hysteria_digest")" || {
        PNM_NODE_LATEST_ERROR='Hysteria2 official SHA-256 file is invalid'
        return "$PNM_EXIT_CONFIG"
    }
    pnm_validate_sha256 "$hysteria_sha256" || {
        PNM_NODE_LATEST_ERROR='Hysteria2 official SHA-256 value is invalid'
        return "$PNM_EXIT_CONFIG"
    }

    PNM_NODE_LATEST_VERSIONS=(
        [XRAY_VERSION]="$xray_version"
        [XRAY_SHA256]="$xray_sha256"
        [HY2_VERSION]="$hysteria_version"
        [HY2_SHA256]="$hysteria_sha256"
    )
}

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

    printf 'SCHEMA_VERSION=1\nNODE_REGION=%s\nNODE_ADDRESS=%s\nTIMEZONE=%s\nPNM_CONFIGURED=no\nXRAY_PORT=%s\nXRAY_SERVER_NAME=%s\nXRAY_TARGET=%s\nHY2_PORT=%s\nHY2_TLS_MODE=%s\nHY2_TLS_SERVER_NAME=%s\n' \
        "${node_ref[NODE_REGION]}" "${node_ref[NODE_ADDRESS]}" "${node_ref[TIMEZONE]}" "${node_ref[XRAY_PORT]}" \
        "${node_ref[XRAY_SERVER_NAME]}" "${node_ref[XRAY_TARGET]}" "${node_ref[HY2_PORT]}" \
        "${node_ref[HY2_TLS_MODE]}" "${node_ref[HY2_TLS_SERVER_NAME]}" >"$directory/node.conf" || return "$PNM_EXIT_CANTCREAT"
    printf 'SCHEMA_VERSION=1\nXRAY_VERSION=%s\nXRAY_SHA256=%s\nHY2_VERSION=%s\nHY2_SHA256=%s\nAPPROVED=yes\n' \
        "${versions_ref[XRAY_VERSION]}" "${versions_ref[XRAY_SHA256]}" \
        "${versions_ref[HY2_VERSION]}" "${versions_ref[HY2_SHA256]}" >"$directory/versions.conf" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$directory/node.conf" "$directory/versions.conf" || return "$PNM_EXIT_NOPERM"
}

pnm_node_init() {
    local replace_existing="${1:?replace mode required}"
    shift
    local region='' address='' timezone='' xray_port='' server_name='' target=''
    local hy2_port='' tls_mode='' hy2_server_name='' hy2_server_name_auto=0
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
            --address) (($# > 0)) || { pnm_error '--address requires a value'; return "$PNM_EXIT_USAGE"; }; address="$1"; shift ;;
            --server-address) (($# > 0)) || { pnm_error '--server-address requires a value'; return "$PNM_EXIT_USAGE"; }; address="$1"; shift ;;
            --timezone) (($# > 0)) || { pnm_error '--timezone requires a value'; return "$PNM_EXIT_USAGE"; }; timezone="$1"; shift ;;
            --xray-port) (($# > 0)) || { pnm_error '--xray-port requires a value'; return "$PNM_EXIT_USAGE"; }; xray_port="$1"; shift ;;
            --server-name) (($# > 0)) || { pnm_error '--server-name requires a value'; return "$PNM_EXIT_USAGE"; }; server_name="$1"; shift ;;
            --target) (($# > 0)) || { pnm_error '--target requires a value'; return "$PNM_EXIT_USAGE"; }; target="$1"; shift ;;
            --hy2-port) (($# > 0)) || { pnm_error '--hy2-port requires a value'; return "$PNM_EXIT_USAGE"; }; hy2_port="$1"; shift ;;
            --tls-mode) (($# > 0)) || { pnm_error '--tls-mode requires a value'; return "$PNM_EXIT_USAGE"; }; tls_mode="$1"; shift ;;
            --hy2-server-name) (($# > 0)) || { pnm_error '--hy2-server-name requires a value'; return "$PNM_EXIT_USAGE"; }; hy2_server_name="$1"; shift ;;
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
        if pnm_load_node_config existing_node 2>/dev/null && pnm_validate_node_config existing_node; then
            [[ -n "$region" ]] || region="${existing_node[NODE_REGION]}"
            [[ -n "$address" ]] || address="${existing_node[NODE_ADDRESS]-}"
            [[ -n "$timezone" ]] || timezone="${existing_node[TIMEZONE]}"
            [[ -n "$xray_port" ]] || xray_port="${existing_node[XRAY_PORT]}"
            [[ -n "$server_name" ]] || server_name="${existing_node[XRAY_SERVER_NAME]}"
            [[ -n "$target" ]] || target="${existing_node[XRAY_TARGET]}"
            [[ -n "$hy2_port" ]] || hy2_port="${existing_node[HY2_PORT]}"
            [[ -n "$tls_mode" ]] || tls_mode="${existing_node[HY2_TLS_MODE]}"
            [[ -n "$hy2_server_name" ]] || hy2_server_name="${existing_node[HY2_TLS_SERVER_NAME]-}"
            [[ "${existing_node[PNM_CONFIGURED]}" == no ]] || {
                pnm_error 'The managed node is already configured; use core-specific apply commands or restore a reviewed backup.'
                return "$PNM_EXIT_CONFIG"
            }
        else
            pnm_warn 'Existing node.conf is invalid; --force will replace it after successful validation.'
        fi
    fi
    if [[ -f "$versions_file" && ! -L "$versions_file" ]]; then
        if pnm_load_versions_config existing_versions 2>/dev/null && pnm_validate_versions_config existing_versions; then
            [[ -n "$xray_version" ]] || xray_version="${existing_versions[XRAY_VERSION]}"
            [[ -n "$xray_sha256" ]] || xray_sha256="${existing_versions[XRAY_SHA256]}"
            [[ -n "$hy2_version" ]] || hy2_version="${existing_versions[HY2_VERSION]}"
            [[ -n "$hy2_sha256" ]] || hy2_sha256="${existing_versions[HY2_SHA256]}"
        else
            pnm_warn 'Existing versions.conf is invalid; --force will replace it after successful validation.'
        fi
    fi
    [[ -n "$region" ]] || region="$PNM_NODE_DEFAULT_REGION"
    [[ -n "$timezone" ]] || timezone="$PNM_NODE_DEFAULT_TIMEZONE"
    [[ -n "$xray_port" ]] || xray_port="$PNM_NODE_DEFAULT_XRAY_PORT"
    [[ -n "$server_name" ]] || server_name="$PNM_NODE_DEFAULT_XRAY_SERVER_NAME"
    [[ -n "$target" ]] || target="${server_name}:$PNM_NODE_DEFAULT_XRAY_TARGET_PORT"
    [[ -n "$hy2_port" ]] || hy2_port="$PNM_NODE_DEFAULT_HY2_PORT"
    [[ -n "$tls_mode" ]] || tls_mode="$PNM_NODE_DEFAULT_HY2_TLS_MODE"
    if [[ -z "$hy2_server_name" && "$tls_mode" == selfsigned-pin ]]; then
        hy2_server_name_auto=1
        hy2_server_name="proxy-$region"
    fi

    if pnm_is_tty; then
        if { [[ -z "$xray_version" && -z "$xray_sha256" ]] ||
            [[ -z "$hy2_version" && -z "$hy2_sha256" ]]; }; then
            if pnm_node_fetch_latest_versions; then
                [[ -n "$xray_version" || -n "$xray_sha256" ]] || {
                    xray_version="${PNM_NODE_LATEST_VERSIONS[XRAY_VERSION]}"
                    xray_sha256="${PNM_NODE_LATEST_VERSIONS[XRAY_SHA256]}"
                }
                [[ -n "$hy2_version" || -n "$hy2_sha256" ]] || {
                    hy2_version="${PNM_NODE_LATEST_VERSIONS[HY2_VERSION]}"
                    hy2_sha256="${PNM_NODE_LATEST_VERSIONS[HY2_SHA256]}"
                }
                pnm_info 'Latest stable Core versions and official SHA-256 values loaded; pressing Enter keeps them pinned.'
            else
                pnm_warn "${PNM_NODE_LATEST_ERROR:-Latest stable Core metadata could not be fetched}; enter both pinned version and SHA-256 pairs manually."
            fi
        fi
        pnm_node_prompt region 'Node region (lowercase, for example osaka)' "$region" || return $?
        pnm_node_prompt address 'VPS public address (IPv4 or hostname; used in share links)' "$address" || return $?
        pnm_node_require_value '--address' "$address" || return $?
        pnm_node_prompt timezone 'Timezone' "$timezone" || return $?
        pnm_node_prompt server_name 'Xray REALITY SNI (public DNS name covered by the target certificate)' "$server_name" || return $?
        pnm_node_prompt target 'Xray REALITY target host:port' "$target" || return $?
        pnm_node_prompt xray_port 'Xray listen port' "$xray_port" || return $?
        pnm_node_prompt hy2_port 'Hysteria2 listen port' "$hy2_port" || return $?
        pnm_node_prompt tls_mode 'Hysteria2 TLS mode (selfsigned-pin|external-ca)' "$tls_mode" || return $?
        if ((hy2_server_name_auto == 1)); then
            if [[ "$tls_mode" == external-ca ]]; then
                hy2_server_name=''
            elif pnm_validate_hy2_tls_server_name "$address"; then
                hy2_server_name="$address"
            else
                hy2_server_name="proxy-$region"
            fi
        fi
        pnm_node_prompt hy2_server_name 'Hysteria2 TLS SNI (must match a certificate DNS SAN)' "$hy2_server_name" || return $?
        pnm_node_prompt xray_version 'Pinned Xray version (latest stable if shown)' "$xray_version" || return $?
        pnm_node_prompt xray_sha256 'Xray SHA-256 (official checksum if shown)' "$xray_sha256" || return $?
        pnm_node_prompt hy2_version 'Pinned Hysteria2 version (latest stable if shown)' "$hy2_version" || return $?
        pnm_node_prompt hy2_sha256 'Hysteria2 SHA-256 (official checksum if shown)' "$hy2_sha256" || return $?
    else
        pnm_node_require_value '--region' "$region" || return $?
        pnm_node_require_value '--address' "$address" || return $?
        pnm_node_require_value '--server-name' "$server_name" || return $?
        pnm_node_require_value '--target' "$target" || return $?
        pnm_node_require_value '--hy2-server-name' "$hy2_server_name" || return $?
        pnm_node_require_value '--xray-version' "$xray_version" || return $?
        pnm_node_require_value '--xray-sha256' "$xray_sha256" || return $?
        pnm_node_require_value '--hy2-version' "$hy2_version" || return $?
        pnm_node_require_value '--hy2-sha256' "$hy2_sha256" || return $?
    fi

    pnm_node_prepare_config_dir || return $?

    node_config=(
        [SCHEMA_VERSION]=1 [NODE_REGION]="$region" [NODE_ADDRESS]="$address" [TIMEZONE]="$timezone" [PNM_CONFIGURED]=no
        [XRAY_PORT]="$xray_port" [XRAY_SERVER_NAME]="$server_name" [XRAY_TARGET]="$target"
        [HY2_PORT]="$hy2_port" [HY2_TLS_MODE]="$tls_mode" [HY2_TLS_SERVER_NAME]="$hy2_server_name"
    )
    versions_config=(
        [SCHEMA_VERSION]=1 [XRAY_VERSION]="$xray_version" [XRAY_SHA256]="$xray_sha256"
        [HY2_VERSION]="$hy2_version" [HY2_SHA256]="$hy2_sha256" [APPROVED]=yes
    )
    if ! pnm_node_validate_input node_config versions_config; then
        if ! pnm_validate_reality_server_name "${node_config[XRAY_SERVER_NAME]}"; then
            pnm_error 'REALITY SNI must be a fully qualified DNS name covered by the target certificate; do not use the VPS hostname.'
            return "$PNM_EXIT_CONFIG"
        fi
        pnm_error 'Node values are invalid; check ports, host names, versions, and SHA-256 values.'
        return "$PNM_EXIT_CONFIG"
    fi

    pnm_make_temp_dir temp_dir || return $?
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
        pnm_info 'For external-ca, add --tls-cert FILE --tls-key FILE to the install command.'
    fi
}

pnm_node_show() {
    pnm_require_root || return $?
    pnm_with_deployment_read_lock pnm_node_show_unlocked
}

pnm_node_show_unlocked() {
    local reality_server_name reality_sni_valid=1 runtime_consistency=not-applied
    local runtime_port='' runtime_target='' runtime_server_names='' runtime_network=''
    local xray_service_state=unknown hy2_service_state=unknown runtime_summary='' consistency_rc
    local xray_applied=unknown hy2_consistency=not-applied hy2_applied=unknown
    local xray_link_status=unknown hy2_link_status=unknown xray_status_line='' hy2_status_line=''
    local xray_reason='' hy2_reason=''
    local -A node_config=() versions_config=()
    local -A reality_secret=() hysteria_secret=()

    pnm_load_node_config node_config || {
        pnm_error "Node configuration is missing or unreadable: $PNM_CONFIG_DIR/node.conf"
        return "$PNM_EXIT_CONFIG"
    }
    pnm_load_versions_config versions_config || {
        pnm_error "Version manifest is missing or unreadable: $PNM_CONFIG_DIR/versions.conf"
        return "$PNM_EXIT_CONFIG"
    }
    reality_server_name="${node_config[XRAY_SERVER_NAME]-}"
    if ! pnm_validate_node_config node_config; then
        if pnm_validate_reality_server_name "$reality_server_name"; then
            pnm_error 'Node configuration values are invalid.'
            return "$PNM_EXIT_CONFIG"
        fi
        node_config[XRAY_SERVER_NAME]='example.com'
        if ! pnm_validate_node_config node_config; then
            node_config[XRAY_SERVER_NAME]="$reality_server_name"
            pnm_error 'Node configuration values are invalid.'
            return "$PNM_EXIT_CONFIG"
        fi
        node_config[XRAY_SERVER_NAME]="$reality_server_name"
        reality_sni_valid=0
    fi
    pnm_validate_versions_config versions_config || { pnm_error 'Version manifest values are invalid.'; return "$PNM_EXIT_CONFIG"; }

    xray_service_state="$(pnm_systemd_active_state xray.service 2>/dev/null || printf unknown)"
    hy2_service_state="$(pnm_systemd_active_state hysteria-server.service 2>/dev/null || printf unknown)"
    if [[ "${node_config[PNM_CONFIGURED]}" == yes ]] && ((reality_sni_valid == 1)); then
        if pnm_load_reality_secret reality_secret && pnm_validate_reality_secret_config reality_secret; then
            xray_status_line="$(pnm_node_core_link_status xray node_config reality_secret)"
            IFS='|' read -r xray_link_status xray_service_state runtime_consistency xray_applied xray_reason <<<"$xray_status_line"
            if runtime_summary="$(pnm_xray_config_runtime_values "$PNM_XRAY_CONFIG" 2>/dev/null)"; then
                IFS=$'\t' read -r runtime_port runtime_target runtime_server_names runtime_network <<<"$runtime_summary"
            fi
        else
            runtime_consistency=unavailable
        fi
        if pnm_load_hysteria_secret hysteria_secret && pnm_validate_hysteria_secret_config hysteria_secret; then
            hy2_status_line="$(pnm_node_core_link_status hysteria2 node_config hysteria_secret)"
            IFS='|' read -r hy2_link_status hy2_service_state hy2_consistency hy2_applied hy2_reason <<<"$hy2_status_line"
        else
            hy2_link_status=unknown
            hy2_consistency=unavailable
            hy2_applied=unknown
        fi
    fi

    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.node.v1","config_dir":%s,"node":{"region":%s,"address":%s,"timezone":%s,"configured":%s,"xray_port":%s,"server_name":%s,"target":%s,"hy2_port":%s,"tls_mode":%s},"runtime":{"xray_service":%s,"xray_port":%s,"xray_server_names":%s,"xray_target":%s,"xray_network":%s,"configuration_consistency":%s,"xray_applied_state":%s,"xray_link_status":%s,"hysteria2_service":%s,"hysteria2_configuration_consistency":%s,"hysteria2_applied_state":%s,"hysteria2_link_status":%s},"versions":{"xray":%s,"xray_sha256":%s,"hysteria2":%s,"hysteria2_sha256":%s}}\n' \
            "$(pnm_json_string "$PNM_CONFIG_DIR")" "$(pnm_json_string "${node_config[NODE_REGION]}")" \
            "$(pnm_json_string "${node_config[NODE_ADDRESS]-}")" "$(pnm_json_string "${node_config[TIMEZONE]}")" \
            "$(pnm_json_string "${node_config[PNM_CONFIGURED]}")" "$(pnm_json_string "${node_config[XRAY_PORT]}")" \
            "$(pnm_json_string "${node_config[XRAY_SERVER_NAME]}")" "$(pnm_json_string "${node_config[XRAY_TARGET]}")" \
            "$(pnm_json_string "${node_config[HY2_PORT]}")" "$(pnm_json_string "${node_config[HY2_TLS_MODE]}")" \
            "$(pnm_json_string "$xray_service_state")" "$(pnm_json_string "$runtime_port")" \
            "$(pnm_json_string "$runtime_server_names")" "$(pnm_json_string "$runtime_target")" \
            "$(pnm_json_string "$runtime_network")" \
            "$(pnm_json_string "$runtime_consistency")" "$(pnm_json_string "$xray_applied")" \
            "$(pnm_json_string "$xray_link_status")" "$(pnm_json_string "$hy2_service_state")" \
            "$(pnm_json_string "$hy2_consistency")" "$(pnm_json_string "$hy2_applied")" \
            "$(pnm_json_string "$hy2_link_status")" \
            "$(pnm_json_string "${versions_config[XRAY_VERSION]}")" "$(pnm_json_string "${versions_config[XRAY_SHA256]}")" \
            "$(pnm_json_string "${versions_config[HY2_VERSION]}")" "$(pnm_json_string "${versions_config[HY2_SHA256]}")"
        if ((reality_sni_valid == 0)); then
            pnm_warn 'Saved REALITY SNI is not a fully qualified DNS name; do not use the VPS hostname.'
            return "$PNM_EXIT_CONFIG"
        fi
        if [[ "$xray_link_status" != ready ]]; then
            if [[ "$runtime_consistency" == drift ]]; then
                pnm_error "Persistent node.conf differs from the runtime Xray configuration; ${xray_reason:-runtime fields differ}. Review and apply with 'sudo pnm apply xray'."
            else
                pnm_error "Xray persistent/runtime state is not safe for links: ${xray_reason:-status unavailable}. Review and apply with 'sudo pnm apply xray' if appropriate."
            fi
            return "$PNM_EXIT_CONFIG"
        fi
        if [[ "$hy2_link_status" != ready ]]; then
            pnm_error "Hysteria2 persistent/runtime state is not safe for links: ${hy2_reason:-status unavailable}. Review and apply with 'sudo pnm apply hy2' if appropriate."
            return "$PNM_EXIT_CONFIG"
        fi
        return 0
    fi

    printf 'PNM node\n'
    printf '  region: %s\n  address: %s\n  timezone: %s\n  configured: %s\n' \
        "${node_config[NODE_REGION]}" "${node_config[NODE_ADDRESS]-not-set}" \
        "${node_config[TIMEZONE]}" "${node_config[PNM_CONFIGURED]}"
    printf '  xray: %s -> %s (%s) [persisted]\n' "${node_config[XRAY_PORT]}" "${node_config[XRAY_SERVER_NAME]}" "${node_config[XRAY_TARGET]}"
    printf '  xray runtime: service=%s config=%s applied=%s link=%s' \
        "$xray_service_state" "$runtime_consistency" "$xray_applied" "$xray_link_status"
    if [[ -n "$runtime_port" ]]; then
        printf ' port=%s sni=%s target=%s transport=%s' \
            "$runtime_port" "$runtime_server_names" "$runtime_target" "$runtime_network"
    fi
    printf '\n'
    printf '  hysteria2: %s (%s) [persisted]\n' "${node_config[HY2_PORT]}" "${node_config[HY2_TLS_MODE]}"
    printf '  hysteria2 runtime: service=%s config=%s applied=%s link=%s\n' \
        "$hy2_service_state" "$hy2_consistency" "$hy2_applied" "$hy2_link_status"
    printf '  versions: xray %s; hysteria2 %s\n' "${versions_config[XRAY_VERSION]}" "${versions_config[HY2_VERSION]}"
    if ((reality_sni_valid == 0)); then
        pnm_warn 'Saved REALITY SNI is not a fully qualified DNS name; do not use the VPS hostname.'
        return "$PNM_EXIT_CONFIG"
    fi
    if [[ "$xray_link_status" != ready ]]; then
        if [[ "$runtime_consistency" == drift ]]; then
            pnm_error "Persistent node.conf differs from the runtime Xray configuration; ${xray_reason:-runtime fields differ}. Review and apply with 'sudo pnm apply xray'."
        else
            pnm_error "Xray persistent/runtime state is not safe for links: ${xray_reason:-status unavailable}. Review and apply with 'sudo pnm apply xray' if appropriate."
        fi
        return "$PNM_EXIT_CONFIG"
    fi
    if [[ "$hy2_link_status" != ready ]]; then
        pnm_error "Hysteria2 persistent/runtime state is not safe for links: ${hy2_reason:-status unavailable}. Review and apply with 'sudo pnm apply hy2' if appropriate."
        return "$PNM_EXIT_CONFIG"
    fi
}

pnm_node_links() {
    local argument
    for argument in "$@"; do
        if [[ "$argument" == -h || "$argument" == --help ]]; then
            pnm_node_links_unlocked "$@"
            return $?
        fi
    done
    pnm_require_root || return $?
    pnm_with_deployment_read_lock pnm_node_links_unlocked "$@"
}

pnm_node_links_unlocked() {
    local address='' argument xray_public_key xray_link='' hy2_link='' xray_label hy2_label rc
    local xray_status xray_service xray_config_state xray_applied xray_reason
    local hy2_status hy2_service hy2_config_state hy2_applied hy2_reason hy2_server_name='' hy2_client_pin=''
    local -A node_config=() reality_secret=() hysteria_secret=()

    while (($# > 0)); do
        argument="$1"
        shift
        case "$argument" in
            --address | --server-address)
                (($# > 0)) || { pnm_error "$argument requires a value"; return "$PNM_EXIT_USAGE"; }
                address="$1"
                shift
                ;;
            -h | --help)
                printf '%s\n' 'Usage: pnm node links [--address IPv4-or-hostname]' \
                    'Print client import links. Links contain credentials and must be handled as secrets.'
                return "$PNM_EXIT_OK"
                ;;
            *) pnm_error "Unknown node links option: $argument"; return "$PNM_EXIT_USAGE" ;;
        esac
    done

    pnm_require_root || return $?
    pnm_load_node_config node_config || {
        pnm_error "Node configuration is missing or unreadable: $PNM_CONFIG_DIR/node.conf"
        return "$PNM_EXIT_CONFIG"
    }
    pnm_validate_reality_server_name "${node_config[XRAY_SERVER_NAME]-}" || {
        pnm_error 'REALITY SNI must be a fully qualified DNS name covered by the target certificate; do not use the VPS hostname.'
        return "$PNM_EXIT_CONFIG"
    }
    pnm_validate_node_config node_config || {
        pnm_error 'Node configuration values are invalid.'
        return "$PNM_EXIT_CONFIG"
    }
    [[ "${node_config[PNM_CONFIGURED]}" == yes ]] || {
        pnm_error 'Node is not installed yet; run sudo pnm install --apply --yes first.'
        return "$PNM_EXIT_CONFIG"
    }
    [[ -n "$address" ]] || address="${node_config[NODE_ADDRESS]-}"
    if [[ -z "$address" ]]; then
        pnm_error 'A VPS public address is required. Use pnm node links --address ADDRESS.'
        return "$PNM_EXIT_CONFIG"
    fi
    pnm_validate_node_address "$address" || {
        pnm_error 'Share-link address must be an IPv4 address or hostname.'
        return "$PNM_EXIT_CONFIG"
    }
    if pnm_load_reality_secret reality_secret && pnm_validate_reality_secret_config reality_secret; then
        IFS='|' read -r xray_status xray_service xray_config_state xray_applied xray_reason \
            <<<"$(pnm_node_core_link_status xray node_config reality_secret)"
    else
        xray_status=unknown
        xray_service=unknown
        xray_config_state=unknown
        xray_applied=unknown
        xray_reason='REALITY credentials are missing or invalid'
    fi
    if [[ "$xray_status" == ready ]]; then
        xray_public_key="$(pnm_node_xray_reality_public_key "${reality_secret[XRAY_REALITY_PRIVATE_KEY]}")" || {
            xray_status=unknown
            xray_reason='REALITY public key could not be derived'
        }
    fi
    if [[ "$xray_status" == ready ]]; then
        xray_label="$(pnm_node_uri_encode "PNM-${node_config[NODE_REGION]}-Xray")"
        xray_link="vless://$(pnm_node_uri_encode "${reality_secret[XRAY_UUID]}")@$address:${node_config[XRAY_PORT]}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(pnm_node_uri_encode "${node_config[XRAY_SERVER_NAME]}")&fp=chrome&pbk=$(pnm_node_uri_encode "$xray_public_key")&sid=$(pnm_node_uri_encode "${reality_secret[XRAY_REALITY_SHORT_ID]}")&type=tcp&headerType=none#$xray_label"
    fi

    if ! pnm_load_hysteria_secret hysteria_secret || ! pnm_validate_hysteria_secret_config hysteria_secret; then
        hy2_status=unknown
        hy2_service=unknown
        hy2_config_state=unknown
        hy2_applied=unknown
        hy2_reason='Hysteria2 credentials are missing or invalid'
    elif ! hy2_server_name="$(pnm_hysteria_tls_server_name node_config hysteria_secret 2>/dev/null)"; then
        hy2_status=unknown
        hy2_service=unknown
        hy2_config_state=unknown
        hy2_applied=unknown
        hy2_reason='HY2 TLS SNI is missing or does not match the configured certificate SAN'
    else
        IFS='|' read -r hy2_status hy2_service hy2_config_state hy2_applied hy2_reason \
            <<<"$(pnm_node_core_link_status hysteria2 node_config hysteria_secret)"
    fi

    if [[ "$hy2_status" == ready && "${node_config[HY2_TLS_MODE]}" == selfsigned-pin ]]; then
        if ! hy2_client_pin="$(pnm_tls_certificate_sha256 "${hysteria_secret[HY2_TLS_CERT_PATH]}")"; then
            hy2_status=unknown
            hy2_reason='HY2 TLS certificate fingerprint could not be derived'
        fi
    fi
    if [[ "$hy2_status" == ready ]]; then
        hy2_label="$(pnm_node_uri_encode "PNM-${node_config[NODE_REGION]}-Hysteria2")"
        hy2_link="hysteria2://$(pnm_node_uri_encode "${hysteria_secret[HY2_AUTH_PASSWORD]}")@$address:${node_config[HY2_PORT]}/?sni=$(pnm_node_uri_encode "$hy2_server_name")"
        if [[ "${node_config[HY2_TLS_MODE]}" == selfsigned-pin ]]; then
            hy2_link+="&insecure=1&pinSHA256=$(pnm_node_uri_encode "$hy2_client_pin")"
        fi
        hy2_link+="#$hy2_label"
    fi

    if [[ "$PNM_OUTPUT_MODE" == json ]]; then
        printf '{"schema":"pnm.node-links.v1","address":%s,"xray_vless_reality":%s,"xray_status":%s,"hysteria2":%s,"hysteria2_status":%s}\n' \
            "$(pnm_json_string "$address")" \
            "$([[ -n "$xray_link" ]] && pnm_json_string "$xray_link" || printf null)" \
            "$(pnm_json_string "$xray_status")" \
            "$([[ -n "$hy2_link" ]] && pnm_json_string "$hy2_link" || printf null)" \
            "$(pnm_json_string "$hy2_status")"
        [[ -n "$xray_link" || -n "$hy2_link" ]] || return "$PNM_EXIT_CONFIG"
        [[ -n "$xray_link" ]] || pnm_error "Xray link omitted: $xray_reason."
        [[ -n "$hy2_link" ]] || pnm_error "Hysteria2 link omitted: $hy2_reason."
        return "$PNM_EXIT_OK"
    fi
    printf 'PNM client share links (sensitive)\n'
    if [[ -n "$xray_link" ]]; then
        printf '  Xray VLESS + REALITY:\n%s\n' "$xray_link"
    else
        pnm_warn "Xray link omitted: $xray_reason."
    fi
    if [[ -n "$hy2_link" ]]; then
        printf '  Hysteria2:\n%s\n' "$hy2_link"
    else
        pnm_warn "Hysteria2 link omitted: $hy2_reason."
    fi
    [[ -n "$xray_link" || -n "$hy2_link" ]] || return "$PNM_EXIT_CONFIG"
    pnm_warn 'These links contain client credentials. Store and transmit them as secrets.'
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
        links | share)
            pnm_node_links "$@"
            ;;
        validate | check)
            (($# == 0)) || { pnm_error 'Usage: pnm node validate'; return "$PNM_EXIT_USAGE"; }
            pnm_node_validate
            ;;
        help | -h | --help) pnm_print_help node ;;
        *) pnm_error "Unknown node action: $action"; return "$PNM_EXIT_USAGE" ;;
    esac
}
