#!/usr/bin/env bash

PNM_CORE_ID=''
PNM_CORE_UNIT=''
PNM_CORE_BINARY=''
PNM_CORE_CONFIG=''
PNM_CORE_RESTORE_XRAY_ACTIVE=''
PNM_CORE_RESTORE_XRAY_ENABLED=''
PNM_CORE_RESTORE_HY2_ACTIVE=''
PNM_CORE_RESTORE_HY2_ENABLED=''

pnm_core_resolve() {
    case "$1" in
        xray)
            PNM_CORE_ID=xray PNM_CORE_UNIT=xray.service
            PNM_CORE_BINARY=$PNM_XRAY_BIN PNM_CORE_CONFIG=$PNM_XRAY_CONFIG
            ;;
        hy2 | hysteria2)
            PNM_CORE_ID=hysteria2 PNM_CORE_UNIT=hysteria-server.service
            PNM_CORE_BINARY=$PNM_HY2_BIN PNM_CORE_CONFIG=$PNM_HY2_CONFIG
            ;;
        *) return "$PNM_EXIT_USAGE" ;;
    esac
}

pnm_core_restart() {
    local core rc
    pnm_core_resolve "$1" || return $?
    core=$PNM_CORE_ID
    pnm_require_root || return $?
    pnm_core_lifecycle_snapshot "$core" || return $?
    pnm_tx_begin "core-lifecycle-$core" || return $?
    if ((PNM_DRY_RUN == 0)); then
        pnm_tx_record_core_state "$core" "$PNM_CORE_UNIT" "$PNM_LIFECYCLE_PRE_ACTIVE" "$PNM_LIFECYCLE_PRE_ENABLED" || {
            rc=$?; pnm_tx_close; return "$rc";
        }
    fi
    pnm_tx_add_rollback pnm_core_lifecycle_restore || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run restart pnm_core_restart_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    if pnm_tx_run health pnm_core_lifecycle_health_step; then :; else rc=$?; pnm_tx_close; return "$rc"; fi
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    pnm_success "$core restarted and healthy."
}

pnm_core_restart_step() {
    pnm_systemctl restart "$PNM_CORE_UNIT"
}

pnm_core_log() {
    local lines=100 follow=0 arg
    pnm_core_resolve "$1" || return $?
    shift
    while (($#)); do
        arg=$1; shift
        case "$arg" in
            --follow) follow=1 ;;
            --lines)
                (($#)) || return "$PNM_EXIT_USAGE"
                lines=$1; shift
                [[ "$lines" =~ ^[1-9][0-9]{0,4}$ ]] || return "$PNM_EXIT_USAGE"
                ;;
            *) return "$PNM_EXIT_USAGE" ;;
        esac
    done
    pnm_command_exists journalctl || return "$PNM_EXIT_UNAVAILABLE"
    if ((follow)); then
        journalctl -u "$PNM_CORE_UNIT" -n "$lines" -f --no-pager
    else
        journalctl -u "$PNM_CORE_UNIT" -n "$lines" --no-pager
    fi
}

pnm_core_fix_owner() {
    case "$1" in
        xray) chown root:xray -- "$2" && chmod 0640 -- "$2" ;;
        hysteria2) chown hysteria:hysteria -- "$2" && chmod 0600 -- "$2" ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
}

pnm_core_restore_config() {
    local rc=0
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    if [[ -f "$PNM_CORE_CONFIG" ]]; then
        pnm_core_fix_owner "$PNM_CORE_ID" "$PNM_CORE_CONFIG" || return "$PNM_EXIT_SOFTWARE"
    fi
    if [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]]; then
        pnm_systemctl restart "$PNM_CORE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
        pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl stop "$PNM_CORE_UNIT" || rc="$PNM_EXIT_SOFTWARE"
    fi
    return "$rc"
}

pnm_core_apply_config() {
    local core=$1 rc stage config
    local node_name=PNM_CORE_NODE secret_name=PNM_CORE_SECRET
    local -A PNM_CORE_NODE=() PNM_CORE_SECRET=()
    pnm_core_resolve "$core" || return $?
    core=$PNM_CORE_ID
    pnm_require_root || return $?
    [[ -d "$(dirname -- "$PNM_CORE_CONFIG")" && ! -L "$(dirname -- "$PNM_CORE_CONFIG")" ]] || return "$PNM_EXIT_CONFIG"
    pnm_load_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config "$node_name" || return "$PNM_EXIT_CONFIG"
    [[ "${PNM_CORE_NODE[PNM_CONFIGURED]}" == yes ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$core" == xray ]]; then
        pnm_load_reality_secret "$secret_name" && pnm_validate_reality_secret_config "$secret_name" || return "$PNM_EXIT_CONFIG"
    else
        pnm_load_hysteria_secret "$secret_name" && pnm_validate_hysteria_secret_config "$secret_name" || return "$PNM_EXIT_CONFIG"
    fi
    stage="$(pnm_make_temp_dir)" || return $?
    config="$stage/config"
    if [[ "$core" == xray ]]; then
        pnm_render_xray_config "$node_name" "$secret_name" >"$config" || return $?
        local validation_output
        pnm_capture validation_output "$PNM_XRAY_BIN" run -test -config "$config" || return "$PNM_EXIT_CONFIG"
    else
        pnm_render_hysteria_config "$node_name" "$secret_name" >"$config" || return $?
    fi
    chmod 0600 -- "$config"
    pnm_core_lifecycle_snapshot "$core" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    pnm_tx_begin "core-config-$core" || return $?
    pnm_tx_add_rollback pnm_core_restore_config || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_write_file "$config" "$PNM_CORE_CONFIG" core_config "$([[ "$core" == xray ]] && printf 0640 || printf 0600)" || {
        rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc";
    }
    pnm_core_fix_owner "$core" "$PNM_CORE_CONFIG" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; }
    pnm_systemctl restart "$PNM_CORE_UNIT" || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG"; }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    pnm_success "$core configuration applied."
}

pnm_core_backup() {
    local destination=$1 directory staging file manifest
    local -a files=(etc/pnm/node.conf etc/pnm/versions.conf etc/pnm/secrets/reality.env etc/pnm/secrets/hysteria.env
        usr/local/etc/xray/config.json etc/hysteria/config.yaml etc/hysteria/tls/server.crt etc/hysteria/tls/server.key
        usr/local/bin/xray usr/local/bin/hysteria etc/systemd/system/xray.service etc/systemd/system/hysteria-server.service)
    pnm_require_root || return $?
    if [[ -z "$destination" ]]; then
        directory=/var/backups/pnm
        pnm_mkdir_mode 0700 "$directory" || return "$PNM_EXIT_CANTCREAT"
        destination="$directory/pnm-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
    else
        directory="$(dirname -- "$destination")"
        [[ -d "$directory" && ! -L "$directory" ]] || return "$PNM_EXIT_CONFIG"
    fi
    [[ ! -e "$destination" && ! -L "$destination" ]] || return "$PNM_EXIT_CANTCREAT"
    for file in "${files[@]}"; do
        if [[ ! -f "/$file" || -L "/$file" ]]; then
            pnm_error "Cannot create a complete Core backup; required file is missing or unsafe: /$file"
            return "$PNM_EXIT_CONFIG"
        fi
    done
    staging="$(pnm_make_temp_dir)" || return $?
    for file in "${files[@]}"; do
        [[ -f "/$file" && ! -L "/$file" ]] || continue
        mkdir -p -- "$staging/$(dirname -- "$file")" || return "$PNM_EXIT_CANTCREAT"
        install -m 0600 -- "/$file" "$staging/$file" || return "$PNM_EXIT_CANTCREAT"
    done
    manifest="$staging/MANIFEST.txt"
    {
        printf 'CONTAINS SECRETS\nPNM_VERSION=%s\nHOSTNAME=%s\nKERNEL=%s\n' "$(pnm_read_version)" "$(hostname)" "$(uname -r)"
        printf 'XRAY_VERSION=%s\nHY2_VERSION=%s\nTCP_PORT=443\nUDP_PORT=8443\n' \
            "$(pnm_binary_version "$PNM_XRAY_BIN" xray 2>/dev/null || printf unknown)" \
            "$(pnm_binary_version "$PNM_HY2_BIN" hysteria 2>/dev/null || printf unknown)"
        printf 'XRAY_ACTIVE=%s\nXRAY_ENABLED=%s\nHY2_ACTIVE=%s\nHY2_ENABLED=%s\n' \
            "$(pnm_systemd_active_state xray.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_enabled_state xray.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_active_state hysteria-server.service 2>/dev/null || printf unknown)" \
            "$(pnm_systemd_enabled_state hysteria-server.service 2>/dev/null || printf unknown)"
    } >"$manifest" || return "$PNM_EXIT_CANTCREAT"
    chmod 0600 -- "$manifest"
    tar --create --gzip --file "$destination" --directory "$staging" . || {
        rm -f -- "$destination"; return "$PNM_EXIT_CANTCREAT";
    }
    chmod 0600 -- "$destination" || { rm -f -- "$destination"; return "$PNM_EXIT_NOPERM"; }
    printf '%s\n' "$destination"
}

pnm_core_update() {
    local requested='' version hash arg asset staged rc previous_dir previous_file previous_meta old_version tmp style
    pnm_core_resolve "$1" || return $?
    shift
    while (($#)); do
        arg=$1; shift
        case "$arg" in
            --version) (($#)) || return "$PNM_EXIT_USAGE"; requested=$1; shift ;;
            *) return "$PNM_EXIT_USAGE" ;;
        esac
    done
    pnm_require_root || return $?
    pnm_assets_load || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_CORE_ID" == xray ]]; then
        version=${PNM_ASSET_VERSIONS[XRAY_VERSION]} hash=${PNM_ASSET_VERSIONS[XRAY_SHA256]}
        style=xray
    else
        version=${PNM_ASSET_VERSIONS[HY2_VERSION]} hash=${PNM_ASSET_VERSIONS[HY2_SHA256]}
        style=hysteria
    fi
    [[ -z "$requested" || "$requested" == "$version" ]] || {
        pnm_error "Requested version is not approved in $PNM_CONFIG_DIR/versions.conf."
        return "$PNM_EXIT_CONFIG"
    }
    [[ -x "$PNM_CORE_BINARY" && -f "$PNM_CORE_CONFIG" ]] || return "$PNM_EXIT_CONFIG"
    pnm_core_lifecycle_snapshot "$PNM_CORE_ID" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    old_version="$(pnm_binary_version "$PNM_CORE_BINARY" "$style" | grep -Eo '[0-9]+(\.[A-Za-z0-9+-]+){2}' | head -n 1)" || return "$PNM_EXIT_CONFIG"
    [[ -n "$old_version" ]] || return "$PNM_EXIT_CONFIG"
    PNM_CORE_STAGE="$(pnm_make_temp_dir)" || return $?
    asset="$PNM_CORE_STAGE/asset"
    pnm_asset_download_verified "$PNM_CORE_ID" "$version" "$hash" "$asset" || return $?
    if [[ "$PNM_CORE_ID" == xray ]]; then
        staged="$(pnm_asset_stage_xray_zip "$asset" "$PNM_CORE_STAGE/extract")" || return $?
    local validation_output
    pnm_capture validation_output "$staged" run -test -config "$PNM_CORE_CONFIG" || return "$PNM_EXIT_CONFIG"
    else
        staged="$(pnm_asset_stage_hysteria_binary "$asset" "$PNM_CORE_STAGE")" || return $?
    fi
    previous_dir="$PNM_STATE_DIR/cores/$PNM_CORE_ID"
    pnm_mkdir_mode 0700 "$previous_dir" || return "$PNM_EXIT_CANTCREAT"
    previous_file="$previous_dir/previous"
    previous_meta="$previous_dir/previous.env"
    tmp="$(mktemp -- "$previous_dir/.previous.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    pnm_tx_begin "core-update-$PNM_CORE_ID" || { rm -f -- "$tmp"; return $?; }
    pnm_tx_add_rollback pnm_core_update_rollback || { pnm_tx_close; rm -f -- "$tmp"; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_write_file "$staged" "$PNM_CORE_BINARY" core_binary 0755 || {
        rc=$?; pnm_tx_rollback || true; pnm_tx_close; rm -f -- "$tmp"; return "$rc";
    }
    if [[ "$(pnm_binary_version "$PNM_CORE_BINARY" "$style")" != *"${version#v}"* ]]; then
        pnm_tx_rollback || true; pnm_tx_close; rm -f -- "$tmp"; return "$PNM_EXIT_CONFIG"
    fi
    pnm_systemctl restart "$PNM_CORE_UNIT" || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; rm -f -- "$tmp"; return "$rc"; }
    pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || { pnm_tx_rollback || true; pnm_tx_close; rm -f -- "$tmp"; return "$PNM_EXIT_CONFIG"; }
    install -m 0755 -- "$PNM_TX_PATH/snapshots/core_binary" "$tmp" || {
        pnm_tx_rollback || true; pnm_tx_close; rm -f -- "$tmp"; return "$PNM_EXIT_CANTCREAT";
    }
    mv -f -- "$tmp" "$previous_file" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
    printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=%s\n' "$PNM_CORE_ID" "$old_version" >"$previous_meta" || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT";
    }
    chmod 0600 -- "$previous_meta" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    pnm_success "$PNM_CORE_ID updated to $version; use 'pnm rollback $PNM_CORE_ID' to revert."
}

pnm_core_update_rollback() {
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    pnm_systemctl restart "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
    pnm_systemd_unit_healthy "$PNM_CORE_UNIT"
}

pnm_core_rollback() {
    local core version current_version previous_dir previous_file previous_meta rc style
    pnm_core_resolve "$1" || return $?
    pnm_require_root || return $?
    core=$PNM_CORE_ID
    style=xray
    [[ "$core" == hysteria2 ]] && style=hysteria
    previous_dir="$PNM_STATE_DIR/cores/$core"
    previous_file="$previous_dir/previous"
    previous_meta="$previous_dir/previous.env"
    [[ -f "$previous_file" && ! -L "$previous_file" && -f "$previous_meta" && ! -L "$previous_meta" ]] || return "$PNM_EXIT_UNAVAILABLE"
    local -A previous=()
    pnm_config_load "$previous_meta" previous SCHEMA_VERSION CORE VERSION || return "$PNM_EXIT_CONFIG"
    [[ "${previous[SCHEMA_VERSION]-}" == 1 && "${previous[CORE]-}" == "$core" && "${previous[VERSION]-}" =~ ^[A-Za-z0-9._+-]+$ ]] || return "$PNM_EXIT_CONFIG"
    version=${previous[VERSION]}
    [[ "$(pnm_binary_version "$previous_file" "$style")" == *"$version"* ]] || return "$PNM_EXIT_CONFIG"
    pnm_core_lifecycle_snapshot "$core" || return $?
    [[ "$PNM_LIFECYCLE_PRE_ACTIVE" == active ]] || return "$PNM_EXIT_CONFIG"
    PNM_CORE_STAGE="$(pnm_make_temp_dir)" || return $?
    current_version="$(pnm_binary_version "$PNM_CORE_BINARY" "$style" | grep -Eo '[0-9]+(\.[A-Za-z0-9+-]+){2}' | head -n 1)" || return "$PNM_EXIT_CONFIG"
    install -m 0755 -- "$PNM_CORE_BINARY" "$PNM_CORE_STAGE/current" || return "$PNM_EXIT_CANTCREAT"
    pnm_tx_begin "core-rollback-$core" || return $?
    pnm_tx_add_rollback pnm_core_update_rollback || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_write_file "$previous_file" "$PNM_CORE_BINARY" core_binary 0755 || {
        rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc";
    }
    pnm_systemctl restart "$PNM_CORE_UNIT" || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemd_unit_healthy "$PNM_CORE_UNIT" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG"; }
    mv -f -- "$PNM_CORE_STAGE/current" "$previous_file" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
    printf 'SCHEMA_VERSION=1\nCORE=%s\nVERSION=%s\n' "$core" "$current_version" >"$PNM_CORE_STAGE/previous.env" || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT";
    }
    chmod 0600 -- "$PNM_CORE_STAGE/previous.env" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; }
    mv -f -- "$PNM_CORE_STAGE/previous.env" "$previous_meta" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    pnm_success "$core rolled back to $version."
}

pnm_core_restore_rollback() {
    local rc=0
    pnm_tx_restore_written_files || return "$PNM_EXIT_SOFTWARE"
    [[ ! -f "$PNM_XRAY_CONFIG" ]] || pnm_core_fix_owner xray "$PNM_XRAY_CONFIG" || rc="$PNM_EXIT_SOFTWARE"
    if [[ -f "$PNM_HY2_CONFIG" ]]; then
        chown hysteria:hysteria -- "$PNM_HY2_CONFIG" || rc="$PNM_EXIT_SOFTWARE"
        chmod 0600 -- "$PNM_HY2_CONFIG" || rc="$PNM_EXIT_SOFTWARE"
    fi
    pnm_systemd_daemon_reload || rc="$PNM_EXIT_SOFTWARE"
    if [[ "$PNM_CORE_RESTORE_XRAY_ENABLED" == enabled ]]; then
        pnm_systemctl enable xray.service || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl disable xray.service || rc="$PNM_EXIT_SOFTWARE"
    fi
    if [[ "$PNM_CORE_RESTORE_HY2_ENABLED" == enabled ]]; then
        pnm_systemctl enable hysteria-server.service || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl disable hysteria-server.service || rc="$PNM_EXIT_SOFTWARE"
    fi
    if [[ "$PNM_CORE_RESTORE_XRAY_ACTIVE" == active ]]; then
        pnm_systemctl restart xray.service || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl stop xray.service || rc="$PNM_EXIT_SOFTWARE"
    fi
    if [[ "$PNM_CORE_RESTORE_HY2_ACTIVE" == active ]]; then
        pnm_systemctl restart hysteria-server.service || rc="$PNM_EXIT_SOFTWARE"
    else
        pnm_systemctl stop hysteria-server.service || rc="$PNM_EXIT_SOFTWARE"
    fi
    return "$rc"
}

pnm_core_restore() {
    local archive=$1 staging file destination mode rc index=0
    local -a files=()
    pnm_require_root || return $?
    [[ -f "$archive" && ! -L "$archive" ]] || return "$PNM_EXIT_CONFIG"
    [[ "$(stat -c '%a:%u' -- "$archive" 2>/dev/null)" == 600:0 ]] || return "$PNM_EXIT_NOPERM"
    pnm_platform_supported || return "$PNM_EXIT_CONFIG"
    staging="$(pnm_make_temp_dir)" || return $?
    if python3 - "$archive" "$staging" <<'PY'
import pathlib, shutil, sys, tarfile
allowed = {"etc/pnm/node.conf", "etc/pnm/versions.conf", "etc/pnm/secrets/reality.env",
 "etc/pnm/secrets/hysteria.env", "usr/local/etc/xray/config.json", "etc/hysteria/config.yaml",
 "etc/hysteria/tls/server.crt", "etc/hysteria/tls/server.key", "usr/local/bin/xray",
 "usr/local/bin/hysteria", "etc/systemd/system/xray.service", "etc/systemd/system/hysteria-server.service"}
root = pathlib.Path(sys.argv[2])
try:
    with tarfile.open(sys.argv[1], "r:gz") as source:
        members, seen, manifest_item = {}, set(), None
        archive_members = source.getmembers()
        if len(archive_members) > 64:
            raise ValueError("too many backup members")
        total_size = 0
        for item in archive_members:
            name = item.name.removeprefix("./").lstrip("/")
            if name in ("", "."): continue
            if name == "MANIFEST.txt":
                if not item.isfile() or manifest_item is not None: raise ValueError("invalid or duplicate manifest")
                manifest_item = item
            elif name in allowed:
                if not item.isfile() or name in seen: raise ValueError("unsafe or duplicate backup member")
                if item.size > 268435456: raise ValueError("backup member exceeds size limit")
                total_size += item.size
                if total_size > 536870912: raise ValueError("backup exceeds total size limit")
                seen.add(name); members[name] = item
            elif not item.isdir() or ".." in pathlib.PurePosixPath(name).parts:
                raise ValueError("unexpected backup member")
        if not {"etc/pnm/node.conf", "etc/pnm/versions.conf", "usr/local/etc/xray/config.json",
                "etc/hysteria/config.yaml", "usr/local/bin/xray", "usr/local/bin/hysteria"} <= seen:
            raise ValueError("backup lacks required Core state")
        manifest = None if manifest_item is None else source.extractfile(manifest_item)
        if manifest is None or b"CONTAINS SECRETS" not in manifest.read(256):
            raise ValueError("backup manifest does not identify contained secrets")
        with source.extractfile(manifest_item) as data, (root / "MANIFEST.txt").open("xb") as out:
            out.write(data.read())
        for name, item in members.items():
            target = root / name; target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            data = source.extractfile(item)
            if data is None: raise ValueError("backup member unreadable")
            with data, target.open("xb") as out: shutil.copyfileobj(data, out, 1048576)
except (OSError, tarfile.TarError, ValueError) as error:
    print(f"invalid backup: {error}", file=sys.stderr); sys.exit(1)
PY
    then
        :
    else
        return "$PNM_EXIT_CONFIG"
    fi
    pnm_config_load "$staging/etc/pnm/node.conf" PNM_RESTORE_NODE SCHEMA_VERSION NODE_REGION TIMEZONE PNM_CONFIGURED XRAY_PORT XRAY_SERVER_NAME XRAY_TARGET HY2_PORT HY2_TLS_MODE || return "$PNM_EXIT_CONFIG"
    pnm_validate_node_config PNM_RESTORE_NODE || return "$PNM_EXIT_CONFIG"
    pnm_config_load "$staging/etc/pnm/versions.conf" PNM_RESTORE_VERSIONS SCHEMA_VERSION XRAY_VERSION XRAY_SHA256 HY2_VERSION HY2_SHA256 APPROVED || return "$PNM_EXIT_CONFIG"
    pnm_validate_versions_config PNM_RESTORE_VERSIONS || return "$PNM_EXIT_CONFIG"
    pnm_systemd_available || return "$PNM_EXIT_UNAVAILABLE"
    PNM_CORE_RESTORE_XRAY_ACTIVE="$(pnm_systemd_active_state xray.service)" || return "$PNM_EXIT_UNAVAILABLE"
    PNM_CORE_RESTORE_XRAY_ENABLED="$(pnm_systemd_enabled_state xray.service)" || return "$PNM_EXIT_UNAVAILABLE"
    PNM_CORE_RESTORE_HY2_ACTIVE="$(pnm_systemd_active_state hysteria-server.service)" || return "$PNM_EXIT_UNAVAILABLE"
    PNM_CORE_RESTORE_HY2_ENABLED="$(pnm_systemd_enabled_state hysteria-server.service)" || return "$PNM_EXIT_UNAVAILABLE"
    pnm_tx_begin core-restore || return $?
    pnm_tx_add_rollback pnm_core_restore_rollback || { pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$staging" -type f -print0)
    for file in "${files[@]}"; do
        [[ "$file" == "$staging/MANIFEST.txt" ]] && continue
        destination="/${file#"$staging"/}"
        case "$destination" in
            /usr/local/bin/*) mode=0755 ;;
            /etc/systemd/system/*.service|/etc/hysteria/tls/server.crt) mode=0644 ;;
            *) mode=0600 ;;
        esac
        mkdir -p -- "$(dirname -- "$destination")" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CANTCREAT"; }
        ((index += 1))
        pnm_tx_write_file "$file" "$destination" "restore_$index" "$mode" || {
            rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc";
        }
        case "$destination" in
            /usr/local/etc/xray/config.json) pnm_core_fix_owner xray "$destination" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; } ;;
            /etc/hysteria/config.yaml|/etc/hysteria/tls/server.key) chown hysteria:hysteria -- "$destination" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; } ;;
            /etc/hysteria/tls/server.crt) chown root:hysteria -- "$destination" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; } ;;
            /etc/pnm/*) chown root:root -- "$destination" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; } ;;
        esac
    done
    chmod 0755 /etc/pnm /usr/local/etc/xray /etc/hysteria /etc/hysteria/tls || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM";
    }
    chmod 0700 /etc/pnm/secrets || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM"; }
    chown root:root /etc/pnm /etc/pnm/secrets /usr/local/etc/xray /etc/hysteria /etc/hysteria/tls || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_NOPERM";
    }
    pnm_core_config_validate xray "$PNM_XRAY_CONFIG" || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG"; }
    pnm_load_reality_secret PNM_RESTORE_REALITY && pnm_validate_reality_secret_config PNM_RESTORE_REALITY || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG";
    }
    pnm_load_hysteria_secret PNM_RESTORE_HYSTERIA && pnm_validate_hysteria_secret_config PNM_RESTORE_HYSTERIA || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG";
    }
    pnm_tls_validate_pair /etc/hysteria/tls/server.crt /etc/hysteria/tls/server.key || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG";
    }
    pnm_systemd_daemon_reload || { pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_SOFTWARE"; }
    pnm_systemctl enable xray.service || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemctl enable hysteria-server.service || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemctl restart xray.service || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemctl restart hysteria-server.service || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_systemd_unit_healthy xray.service && pnm_systemd_unit_healthy hysteria-server.service || {
        pnm_tx_rollback || true; pnm_tx_close; return "$PNM_EXIT_CONFIG";
    }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    pnm_success 'Both Cores restored and healthy.'
}

PNM_CORE_REMOVE_PATHS=()
PNM_CORE_REMOVE_STAGED=()

pnm_core_uninstall_restore() {
    local index rc=0
    for ((index=${#PNM_CORE_REMOVE_PATHS[@]} - 1; index >= 0; index -= 1)); do
        if [[ -e "${PNM_CORE_REMOVE_STAGED[index]}" ]]; then
            mkdir -p -- "$(dirname -- "${PNM_CORE_REMOVE_PATHS[index]}")" || { rc="$PNM_EXIT_SOFTWARE"; continue; }
            mv -n -- "${PNM_CORE_REMOVE_STAGED[index]}" "${PNM_CORE_REMOVE_PATHS[index]}" || rc="$PNM_EXIT_SOFTWARE"
        fi
    done
    pnm_core_lifecycle_restore || rc="$PNM_EXIT_SOFTWARE"
    return "$rc"
}

pnm_core_uninstall_stop() {
    pnm_systemctl stop "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
    pnm_systemctl disable "$PNM_CORE_UNIT" || return "$PNM_EXIT_SOFTWARE"
}

pnm_core_uninstall() {
    local core unit binary config secret backup stage path target rc index=0 uninstall_root
    local -a paths=()
    pnm_core_resolve "$1" || return $?
    core=$PNM_CORE_ID unit=$PNM_CORE_UNIT binary=$PNM_CORE_BINARY config=$PNM_CORE_CONFIG
    pnm_require_root || return $?
    ((PNM_ASSUME_YES == 1)) || { pnm_error 'Uninstall requires --yes.'; return "$PNM_EXIT_USAGE"; }
    backup="$(pnm_core_backup '')" || return "$PNM_EXIT_CANTCREAT"
    if [[ "$core" == xray ]]; then
        secret="$PNM_CONFIG_DIR/secrets/reality.env"
        paths=("$binary" "$config" "$secret" /etc/systemd/system/xray.service)
    else
        secret="$PNM_CONFIG_DIR/secrets/hysteria.env"
        paths=("$binary" "$config" "$secret" /etc/hysteria/tls/server.crt /etc/hysteria/tls/server.key /etc/systemd/system/hysteria-server.service)
    fi
    uninstall_root="$PNM_STATE_DIR/uninstall"
    pnm_mkdir_mode 0700 "$uninstall_root" || return "$PNM_EXIT_CANTCREAT"
    [[ -d "$uninstall_root" && ! -L "$uninstall_root" ]] || return "$PNM_EXIT_CONFIG"
    stage="$uninstall_root/$core-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
    [[ "$stage" == "$uninstall_root/"* ]] || return "$PNM_EXIT_CONFIG"
    mkdir -m 0700 -- "$stage" || return "$PNM_EXIT_CANTCREAT"
    pnm_core_lifecycle_snapshot "$core" || { rmdir -- "$stage"; return $?; }
    PNM_CORE_REMOVE_PATHS=()
    PNM_CORE_REMOVE_STAGED=()
    pnm_tx_begin "core-uninstall-$core" || { rmdir -- "$stage"; return $?; }
    pnm_tx_add_rollback pnm_core_uninstall_restore || { pnm_tx_close; rmdir -- "$stage"; return "$PNM_EXIT_SOFTWARE"; }
    if pnm_tx_run stop_core pnm_core_uninstall_stop; then :; else rc=$?; pnm_tx_close; rm -rf -- "$stage"; return "$rc"; fi
    for path in "${paths[@]}"; do
        [[ -e "$path" && ! -L "$path" ]] || continue
        ((index += 1))
        target="$stage/$index"
        if mv -- "$path" "$target"; then
            PNM_CORE_REMOVE_PATHS+=("$path")
            PNM_CORE_REMOVE_STAGED+=("$target")
        else
            pnm_tx_rollback || true
            pnm_tx_close
            rm -rf -- "$stage"
            return "$PNM_EXIT_CANTCREAT"
        fi
    done
    pnm_systemd_daemon_reload || { pnm_tx_rollback || true; pnm_tx_close; rm -rf -- "$stage"; return "$PNM_EXIT_SOFTWARE"; }
    pnm_tx_commit || { rc=$?; pnm_tx_rollback || true; pnm_tx_close; return "$rc"; }
    pnm_tx_close
    rm -rf -- "$stage"
    pnm_success "$core removed; rollback backup: $backup"
}

pnm_core_command() {
    local command=$1
    shift
    if ((PNM_DRY_RUN == 1)) && [[ "$command" != log ]]; then
        pnm_error '--dry-run is supported only by install.'
        return "$PNM_EXIT_USAGE"
    fi
    case "$command" in
        restart) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_restart "$1" ;;
        log) (($# >= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_log "$@" ;;
        apply) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_apply_config "$1" ;;
        backup) (($# <= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_backup "${1-}" ;;
        restore) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_restore "$1" ;;
        update) (($# >= 1)) || return "$PNM_EXIT_USAGE"; pnm_core_update "$@" ;;
        rollback) (($# == 1)) || return "$PNM_EXIT_USAGE"; pnm_core_rollback "$1" ;;
        uninstall)
            (($# >= 1 && $# <= 2)) || return "$PNM_EXIT_USAGE"
            [[ "${2-}" != --yes ]] || PNM_ASSUME_YES=1
            (($# == 1)) || [[ "$2" == --yes ]] || return "$PNM_EXIT_USAGE"
            pnm_core_uninstall "$1"
            ;;
        *) return "$PNM_EXIT_USAGE" ;;
    esac
}

pnm_core_menu_select() {
    local action=$1 core
    read -r -p 'Core [xray/hy2]: ' core || return "$PNM_EXIT_USAGE"
    pnm_core_command "$action" "$core"
}

pnm_core_menu_restore() {
    local archive
    read -r -p 'Backup archive path: ' archive || return "$PNM_EXIT_USAGE"
    pnm_core_command restore "$archive"
}

pnm_core_menu_uninstall() {
    local core
    read -r -p 'Core [xray/hy2]: ' core || return "$PNM_EXIT_USAGE"
    read -r -p "Create a Secret-bearing backup and remove $core? Type yes: " answer || return "$PNM_EXIT_USAGE"
    [[ "$answer" == yes ]] || return 0
    pnm_core_command uninstall "$core" --yes
}
