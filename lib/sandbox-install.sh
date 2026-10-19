#!/usr/bin/env bash

PNM_SANDBOX_ROOT=''
PNM_SANDBOX_STAGING=''
PNM_SANDBOX_GENERATE_REALITY_SECRET=0
PNM_SANDBOX_GENERATE_HYSTERIA_SECRET=0
declare -Ag PNM_SANDBOX_NODE=()
declare -Ag PNM_SANDBOX_REALITY=()
declare -Ag PNM_SANDBOX_HYSTERIA=()

pnm_sandbox_path() {
    local relative="${1:?absolute install-relative path required}"
    local path component component_path
    local -a path_components=()

    [[ "$relative" == /* && "$relative" != *'..'* && "$relative" != *$'\n'* ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_SANDBOX_ROOT" == '/' ]]; then
        (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 )) || return "$PNM_EXIT_NOPERM"
        [[ "${PNM_HOST_APPLY_CONFIRMED:-no}" == yes ]] || return "$PNM_EXIT_NOPERM"
    else
        [[ -n "$PNM_SANDBOX_ROOT" && "$PNM_SANDBOX_ROOT" == /* ]] || return "$PNM_EXIT_CONFIG"
        # A pre-existing symlink below the sandbox root could redirect writes outside it.
        path="${PNM_SANDBOX_ROOT%/}${relative}"
        IFS='/' read -r -a path_components <<< "$path"
        component_path=''
        for component in "${path_components[@]}"; do
            [[ -n "$component" && "$component" != '.' ]] || continue
            component_path+="/$component"
            [[ ! -L "$component_path" ]] || return "$PNM_EXIT_CONFIG"
        done
    fi
    printf '%s%s\n' "${PNM_SANDBOX_ROOT%/}" "$relative"
}

pnm_sandbox_prepare_dirs() {
    local relative destination

    # Shared host directories may already have administrator-selected modes.
    for relative in /usr/local/bin /etc/systemd/system; do
        destination="$(pnm_sandbox_path "$relative")" || return $?
        (umask 022; mkdir -p -- "$destination") || return "$PNM_EXIT_CANTCREAT"
    done

    for relative in \
        /usr/local/etc/xray \
        /etc/hysteria \
        /etc/hysteria/tls; do
        destination="$(pnm_sandbox_path "$relative")" || return $?
        pnm_mkdir_mode 0755 "$destination" || return "$PNM_EXIT_CANTCREAT"
    done
    for relative in /etc/pnm /etc/pnm/secrets; do
        destination="$(pnm_sandbox_path "$relative")" || return $?
        pnm_mkdir_mode 0700 "$destination" || return "$PNM_EXIT_CANTCREAT"
    done
}

pnm_sandbox_prepare_secrets() {
    local reality_file="$PNM_CONFIG_DIR/secrets/reality.env"
    local hysteria_file="$PNM_CONFIG_DIR/secrets/hysteria.env"

    PNM_SANDBOX_GENERATE_REALITY_SECRET=0
    PNM_SANDBOX_GENERATE_HYSTERIA_SECRET=0
    if [[ -e "$reality_file" || -L "$reality_file" ]]; then
        if [[ ! -f "$reality_file" || -L "$reality_file" ]] ||
            ! pnm_load_reality_secret PNM_SANDBOX_REALITY ||
            ! pnm_validate_reality_secret_config PNM_SANDBOX_REALITY; then
            pnm_error "Existing REALITY secret is invalid; refusing to replace $reality_file."
            return "$PNM_EXIT_CONFIG"
        fi
    else
        PNM_SANDBOX_GENERATE_REALITY_SECRET=1
        PNM_SANDBOX_REALITY=()
    fi

    if [[ -e "$hysteria_file" || -L "$hysteria_file" ]]; then
        if [[ ! -f "$hysteria_file" || -L "$hysteria_file" ]] ||
            ! pnm_load_hysteria_secret PNM_SANDBOX_HYSTERIA ||
            ! pnm_validate_hysteria_secret_config PNM_SANDBOX_HYSTERIA; then
            pnm_error "Existing Hysteria2 secret is invalid; refusing to replace $hysteria_file."
            return "$PNM_EXIT_CONFIG"
        fi
    else
        PNM_SANDBOX_GENERATE_HYSTERIA_SECRET=1
        PNM_SANDBOX_HYSTERIA=(
            [SCHEMA_VERSION]=1
            [HY2_AUTH_PASSWORD]=''
            [HY2_TLS_CERT_PATH]='/etc/hysteria/tls/server.crt'
            [HY2_TLS_KEY_PATH]='/etc/hysteria/tls/server.key'
            [HY2_TLS_PIN_SHA256]=''
        )
    fi
}

pnm_sandbox_generate_missing_secrets() {
    local uuid private_key short_id password

    if ((PNM_SANDBOX_GENERATE_REALITY_SECRET == 1 || PNM_SANDBOX_GENERATE_HYSTERIA_SECRET == 1)); then
        pnm_command_exists openssl || return "$PNM_EXIT_UNAVAILABLE"
    fi

    if ((PNM_SANDBOX_GENERATE_REALITY_SECRET == 1)); then
        IFS= read -r uuid </proc/sys/kernel/random/uuid || return "$PNM_EXIT_UNAVAILABLE"
        pnm_validate_uuid "$uuid" || return "$PNM_EXIT_CONFIG"
        private_key="$(openssl rand -base64 32 2>/dev/null | tr '+/' '-_' | tr -d '=\n')" || return "$PNM_EXIT_UNAVAILABLE"
        short_id="$(openssl rand -hex 8 2>/dev/null)" || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$private_key" =~ ^[A-Za-z0-9_-]{43}$ && "$short_id" =~ ^[a-f0-9]{16}$ ]] || return "$PNM_EXIT_SOFTWARE"
        PNM_SANDBOX_REALITY=(
            [SCHEMA_VERSION]=1
            [XRAY_UUID]="$uuid"
            [XRAY_REALITY_PRIVATE_KEY]="$private_key"
            [XRAY_REALITY_SHORT_ID]="$short_id"
        )
    fi

    if ((PNM_SANDBOX_GENERATE_HYSTERIA_SECRET == 1)); then
        password="$(openssl rand -base64 32 2>/dev/null | tr '+/' '-_' | tr -d '=\n')" || return "$PNM_EXIT_UNAVAILABLE"
        [[ "$password" =~ ^[A-Za-z0-9_-]{43}$ ]] || return "$PNM_EXIT_SOFTWARE"
        PNM_SANDBOX_HYSTERIA[HY2_AUTH_PASSWORD]="$password"
    fi
}

pnm_sandbox_step_assets() {
    local xray_staged hy2_staged
    local xray_target hy2_target

    [[ -r "${PNM_SANDBOX_XRAY_ARCHIVE:-}" && -r "${PNM_SANDBOX_HY2_BINARY:-}" ]] || return "$PNM_EXIT_CONFIG"
    xray_staged="$(pnm_asset_stage_xray_zip "$PNM_SANDBOX_XRAY_ARCHIVE" "$PNM_SANDBOX_STAGING/xray")" || return $?
    hy2_staged="$(pnm_asset_stage_hysteria_binary "$PNM_SANDBOX_HY2_BINARY" "$PNM_SANDBOX_STAGING/hysteria")" || return $?
    xray_target="$(pnm_sandbox_path /usr/local/bin/xray)" || return $?
    hy2_target="$(pnm_sandbox_path /usr/local/bin/hysteria)" || return $?
    pnm_tx_write_file "$xray_staged" "$xray_target" xray_binary 0755 || return $?
    pnm_tx_write_file "$hy2_staged" "$hy2_target" hysteria_binary 0755 || return $?
}

pnm_sandbox_step_tls() {
    local cert_staged="$PNM_SANDBOX_STAGING/tls/server.crt"
    local key_staged="$PNM_SANDBOX_STAGING/tls/server.key"
    local cert_target key_target certificate_mode key_mode

    pnm_mkdir_mode 0700 "$PNM_SANDBOX_STAGING/tls" || return "$PNM_EXIT_CANTCREAT"
    case "${PNM_SANDBOX_NODE[HY2_TLS_MODE]}" in
        selfsigned-pin)
            cert_target="$(pnm_sandbox_path /etc/hysteria/tls/server.crt)" || return $?
            key_target="$(pnm_sandbox_path /etc/hysteria/tls/server.key)" || return $?
            if [[ -e "$cert_target" || -L "$cert_target" || -e "$key_target" || -L "$key_target" ]]; then
                pnm_tls_validate_pair "$cert_target" "$key_target" || {
                    pnm_error 'Existing Hysteria2 TLS certificate/key pair is invalid; refusing to replace it.'
                    return "$PNM_EXIT_CONFIG"
                }
                certificate_mode="$(stat -c '%a' -- "$cert_target")" || return "$PNM_EXIT_CONFIG"
                key_mode="$(stat -c '%a' -- "$key_target")" || return "$PNM_EXIT_CONFIG"
                [[ "$certificate_mode" == 644 && "$key_mode" == 600 ]] || {
                    pnm_error 'Existing Hysteria2 TLS files have unsafe permissions; refusing to replace them.'
                    return "$PNM_EXIT_CONFIG"
                }
            else
                pnm_tls_generate_selfsigned "$cert_staged" "$key_staged" "${PNM_SANDBOX_NODE[XRAY_SERVER_NAME]}" || return $?
                pnm_tx_write_file "$cert_staged" "$cert_target" hysteria_cert 0644 || return $?
                pnm_tx_write_file "$key_staged" "$key_target" hysteria_key 0600 || return $?
            fi
            ;;
        external-ca)
            [[ -r "${PNM_SANDBOX_EXTERNAL_CERT:-}" && -r "${PNM_SANDBOX_EXTERNAL_KEY:-}" ]] || return "$PNM_EXIT_CONFIG"
            pnm_tls_stage_external_pair "$PNM_SANDBOX_EXTERNAL_CERT" "$PNM_SANDBOX_EXTERNAL_KEY" "$PNM_SANDBOX_STAGING/tls" || return $?
            cert_target="$(pnm_sandbox_path /etc/hysteria/tls/server.crt)" || return $?
            key_target="$(pnm_sandbox_path /etc/hysteria/tls/server.key)" || return $?
            pnm_tx_write_file "$cert_staged" "$cert_target" hysteria_cert 0644 || return $?
            pnm_tx_write_file "$key_staged" "$key_target" hysteria_key 0600 || return $?
            ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
    PNM_SANDBOX_HYSTERIA[HY2_TLS_PIN_SHA256]="$(pnm_tls_spki_pin "$cert_target")" || return "$PNM_EXIT_CONFIG"
    pnm_validate_pin_sha256 "${PNM_SANDBOX_HYSTERIA[HY2_TLS_PIN_SHA256]}" || return "$PNM_EXIT_CONFIG"
    pnm_tls_validate_pair "$cert_target" "$key_target"
}

pnm_sandbox_step_secrets() {
    local reality_staged="$PNM_SANDBOX_STAGING/secrets/reality.env"
    local hysteria_staged="$PNM_SANDBOX_STAGING/secrets/hysteria.env"
    local reality_target hysteria_target

    pnm_mkdir_mode 0700 "$PNM_SANDBOX_STAGING/secrets" || return "$PNM_EXIT_CANTCREAT"
    pnm_render_reality_secret_config PNM_SANDBOX_REALITY >"$reality_staged" || return $?
    pnm_render_hysteria_secret_config PNM_SANDBOX_HYSTERIA >"$hysteria_staged" || return $?
    chmod 0600 -- "$reality_staged" "$hysteria_staged" || return "$PNM_EXIT_NOPERM"
    reality_target="$(pnm_sandbox_path /etc/pnm/secrets/reality.env)" || return $?
    hysteria_target="$(pnm_sandbox_path /etc/pnm/secrets/hysteria.env)" || return $?
    pnm_tx_write_file "$reality_staged" "$reality_target" reality_secret 0600 || return $?
    pnm_tx_write_file "$hysteria_staged" "$hysteria_target" hysteria_secret 0600 || return $?
}

pnm_sandbox_step_configs() {
    local xray_staged="$PNM_SANDBOX_STAGING/config/xray.json"
    local hy2_staged="$PNM_SANDBOX_STAGING/config/hysteria.yaml"
    local xray_target hy2_target

    pnm_mkdir_mode 0700 "$PNM_SANDBOX_STAGING/config" || return "$PNM_EXIT_CANTCREAT"
    pnm_render_xray_config PNM_SANDBOX_NODE PNM_SANDBOX_REALITY >"$xray_staged" || return $?
    pnm_render_hysteria_config PNM_SANDBOX_NODE PNM_SANDBOX_HYSTERIA >"$hy2_staged" || return $?
    xray_target="$(pnm_sandbox_path /usr/local/etc/xray/config.json)" || return $?
    hy2_target="$(pnm_sandbox_path /etc/hysteria/config.yaml)" || return $?
    pnm_tx_write_file "$xray_staged" "$xray_target" xray_config 0640 || return $?
    pnm_tx_write_file "$hy2_staged" "$hy2_target" hysteria_config 0600 || return $?
    if [[ "$PNM_SANDBOX_ROOT" == '/' ]]; then
        chown root:xray -- "$xray_target" || return "$PNM_EXIT_NOPERM"
        chown hysteria:hysteria -- "$hy2_target" || return "$PNM_EXIT_NOPERM"
        chown hysteria:hysteria -- /etc/hysteria/tls/server.key || return "$PNM_EXIT_NOPERM"
        chown root:hysteria -- /etc/hysteria/tls/server.crt || return "$PNM_EXIT_NOPERM"
    fi
}

pnm_sandbox_step_units() {
    local xray_staged="$PNM_SANDBOX_STAGING/unit/xray.service"
    local hy2_staged="$PNM_SANDBOX_STAGING/unit/hysteria-server.service"
    local xray_target hy2_target

    pnm_mkdir_mode 0700 "$PNM_SANDBOX_STAGING/unit" || return "$PNM_EXIT_CANTCREAT"
    pnm_render_xray_unit >"$xray_staged" || return "$PNM_EXIT_SOFTWARE"
    pnm_render_hysteria_unit >"$hy2_staged" || return "$PNM_EXIT_SOFTWARE"
    xray_target="$(pnm_sandbox_path /etc/systemd/system/xray.service)" || return $?
    hy2_target="$(pnm_sandbox_path /etc/systemd/system/hysteria-server.service)" || return $?
    pnm_tx_write_file "$xray_staged" "$xray_target" xray_unit 0644 || return $?
    pnm_tx_write_file "$hy2_staged" "$hy2_target" hysteria_unit 0644 || return $?
}

pnm_sandbox_step_validate() {
    local xray_binary xray_config hy2_config cert key unit secrets

    xray_binary="$(pnm_sandbox_path /usr/local/bin/xray)" || return $?
    xray_config="$(pnm_sandbox_path /usr/local/etc/xray/config.json)" || return $?
    hy2_config="$(pnm_sandbox_path /etc/hysteria/config.yaml)" || return $?
    cert="$(pnm_sandbox_path /etc/hysteria/tls/server.crt)" || return $?
    key="$(pnm_sandbox_path /etc/hysteria/tls/server.key)" || return $?
    unit="$(pnm_sandbox_path /etc/systemd/system/xray.service)" || return $?
    secrets="$(pnm_sandbox_path /etc/pnm/secrets/hysteria.env)" || return $?
    [[ -x "$xray_binary" && -f "$xray_config" && -f "$hy2_config" ]] || return "$PNM_EXIT_CONFIG"
    python3 -m json.tool "$xray_config" >/dev/null 2>&1 || return "$PNM_EXIT_CONFIG"
    if [[ "${PNM_SANDBOX_SKIP_XRAY_TEST:-0}" != 1 ]]; then
        "$xray_binary" run -test -config "$xray_config" >/dev/null 2>&1 || return "$PNM_EXIT_CONFIG"
    fi
    pnm_tls_validate_pair "$cert" "$key" || return $?
    [[ -f "$secrets" && "$(stat -c '%a' "$secrets")" == 600 ]] || return "$PNM_EXIT_CONFIG"
    pnm_unit_validate_text "$(<"$unit")" xray /usr/local/bin/xray || return "$PNM_EXIT_CONFIG"
    pnm_unit_validate_text "$(<"$(pnm_sandbox_path /etc/systemd/system/hysteria-server.service)")" hysteria /usr/local/bin/hysteria || return "$PNM_EXIT_CONFIG"
}

pnm_sandbox_abort() {
    local rc="${1:?sandbox failure code required}"
    local commit_failed="${2:-0}"
    local original_rc="$PNM_TX_STEP_FAILURE_RC"

    if ((PNM_TX_ACTIVE == 1 && PNM_TX_COMMITTED == 0 && PNM_TX_ROLLED_BACK == 0)) &&
        ((PNM_TX_RECOVERY_REQUIRED == 0 || commit_failed == 1)); then
        pnm_tx_rollback || rc="$PNM_EXIT_SOFTWARE"
    fi
    if ((PNM_TX_RECOVERY_REQUIRED == 1)); then
        ((original_rc != 0)) || original_rc="$rc"
        if ((PNM_TX_ROLLBACK_FAILURE_RC != 0)); then
            pnm_error "Installation step '${PNM_TX_STEP_FAILURE_NAME:-unknown}' failed with exit code $original_rc; rollback failed with exit code $PNM_TX_ROLLBACK_FAILURE_RC. Recovery is required; transaction evidence retained at $PNM_TX_PATH."
        else
            pnm_error "Installation stopped with exit code $rc; transaction state is uncertain and recovery is required. Evidence retained at $PNM_TX_PATH."
        fi
    fi
    # Retain staging evidence when automatic recovery could not complete.
    if ((PNM_TX_RECOVERY_REQUIRED == 0)); then
        pnm_sandbox_cleanup_staging || true
    fi
    pnm_tx_close
    return "$rc"
}

pnm_sandbox_install() {
    local root="${1:?isolated root required}"
    local rc component component_path
    local -a root_components=()

    [[ "$root" == /* && "$root" != *'..'* && "$root" != *$'\n'* ]] || return "$PNM_EXIT_CONFIG"
    while [[ "$root" != / && "$root" == */ ]]; do root="${root%/}"; done
    IFS='/' read -r -a root_components <<< "$root"
    component_path=''
    for component in "${root_components[@]}"; do
        [[ -n "$component" && "$component" != '.' ]] || continue
        component_path+="/$component"
        [[ ! -L "$component_path" ]] || return "$PNM_EXIT_CONFIG"
    done
    # Keep the host identity intact, including equivalent spellings such as /./.
    if [[ "$root" -ef / ]]; then root=/; fi
    if [[ "$root" == '/' ]]; then
        (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 )) || return "$PNM_EXIT_NOPERM"
        [[ "${PNM_HOST_APPLY_CONFIRMED:-no}" == yes ]] || return "$PNM_EXIT_NOPERM"
        pnm_require_root || return $?
    fi
    PNM_SANDBOX_ROOT="$root"
    PNM_SANDBOX_STAGING=''
    pnm_load_node_config PNM_SANDBOX_NODE || { pnm_error 'Node configuration is missing or invalid; installation stopped.'; return "$PNM_EXIT_CONFIG"; }
    pnm_validate_node_config PNM_SANDBOX_NODE || { pnm_error 'Node configuration is invalid; installation stopped.'; return "$PNM_EXIT_CONFIG"; }
    pnm_sandbox_prepare_secrets || return $?
    # Validate inputs before creating any directory. Never change the host root.
    if [[ "$root" != '/' ]]; then
        pnm_mkdir_mode 0700 "$root" || return "$PNM_EXIT_CANTCREAT"
    fi
    PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || return $?
    PNM_SANDBOX_STAGING="$PNM_TX_PATH/staging"
    mkdir -m 0700 -- "$PNM_SANDBOX_STAGING" || {
        rc="$PNM_EXIT_CANTCREAT"; pnm_sandbox_abort "$rc"; return $?;
    }
    pnm_sandbox_generate_missing_secrets || {
        rc=$?; pnm_sandbox_abort "$rc"; return $?
    }
    pnm_tx_add_rollback pnm_tx_restore_written_files || {
        pnm_sandbox_abort "$PNM_EXIT_SOFTWARE"
        return $?
    }
    if [[ "$PNM_SANDBOX_ROOT" == '/' ]]; then
        pnm_tx_add_rollback pnm_service_accounts_rollback || {
            pnm_sandbox_abort "$PNM_EXIT_SOFTWARE"
            return $?
        }
        if pnm_tx_run ensure_service_accounts pnm_service_accounts_step; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    fi

    if pnm_tx_run prepare_dirs pnm_sandbox_prepare_dirs; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run stage_assets pnm_sandbox_step_assets; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run stage_tls pnm_sandbox_step_tls; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run write_secrets pnm_sandbox_step_secrets; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run render_configs pnm_sandbox_step_configs; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run install_units pnm_sandbox_step_units; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_run validate pnm_sandbox_step_validate; then :; else rc=$?; pnm_sandbox_abort "$rc"; return $?; fi
    if pnm_tx_commit; then :; else
        rc=$?
        pnm_sandbox_abort "$rc" 1
        return $?
    fi
    pnm_sandbox_cleanup_staging || { pnm_tx_journal CLEANUP_REQUIRED 'staging directory remains'; }
    pnm_tx_close
}

pnm_sandbox_cleanup_staging() {
    [[ -n "$PNM_TX_PATH" && "$PNM_TX_PATH" == /* && "$PNM_TX_PATH" != / &&
        "$PNM_SANDBOX_STAGING" == "$PNM_TX_PATH/staging" && ! -L "$PNM_SANDBOX_STAGING" ]] || return "$PNM_EXIT_CONFIG"
    [[ ! -e "$PNM_SANDBOX_STAGING" ]] || rm -rf -- "$PNM_SANDBOX_STAGING"
}
