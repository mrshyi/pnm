#!/usr/bin/env bash

PNM_SANDBOX_ROOT=''
PNM_SANDBOX_STAGING=''
declare -Ag PNM_SANDBOX_NODE=()
declare -Ag PNM_SANDBOX_REALITY=()
declare -Ag PNM_SANDBOX_HYSTERIA=()

pnm_sandbox_path() {
    local relative="${1:?absolute install-relative path required}"

    [[ "$relative" == /* && "$relative" != *'..'* && "$relative" != *$'\n'* ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$PNM_SANDBOX_ROOT" == '/' ]]; then
        (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 )) || return "$PNM_EXIT_NOPERM"
        [[ "${PNM_HOST_APPLY_CONFIRMED:-no}" == yes ]] || return "$PNM_EXIT_NOPERM"
    else
        [[ -n "$PNM_SANDBOX_ROOT" && "$PNM_SANDBOX_ROOT" == /* ]] || return "$PNM_EXIT_CONFIG"
    fi
    printf '%s%s\n' "${PNM_SANDBOX_ROOT%/}" "$relative"
}

pnm_sandbox_prepare_dirs() {
    local relative

    for relative in \
        /usr/local/bin \
        /usr/local/etc/xray \
        /etc/pnm/secrets \
        /etc/hysteria/tls \
        /etc/systemd/system; do
        pnm_mkdir_mode 0755 "$(pnm_sandbox_path "$relative")" || return "$PNM_EXIT_CANTCREAT"
    done
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
    local cert_target key_target

    pnm_mkdir_mode 0700 "$PNM_SANDBOX_STAGING/tls" || return "$PNM_EXIT_CANTCREAT"
    case "${PNM_SANDBOX_NODE[HY2_TLS_MODE]}" in
        selfsigned-pin)
            pnm_tls_generate_selfsigned "$cert_staged" "$key_staged" "${PNM_SANDBOX_NODE[XRAY_SERVER_NAME]}" || return $?
            ;;
        external-ca)
            [[ -r "${PNM_SANDBOX_EXTERNAL_CERT:-}" && -r "${PNM_SANDBOX_EXTERNAL_KEY:-}" ]] || return "$PNM_EXIT_CONFIG"
            pnm_tls_stage_external_pair "$PNM_SANDBOX_EXTERNAL_CERT" "$PNM_SANDBOX_EXTERNAL_KEY" "$PNM_SANDBOX_STAGING/tls" || return $?
            ;;
        *) return "$PNM_EXIT_CONFIG" ;;
    esac
    cert_target="$(pnm_sandbox_path /etc/hysteria/tls/server.crt)" || return $?
    key_target="$(pnm_sandbox_path /etc/hysteria/tls/server.key)" || return $?
    pnm_tx_write_file "$cert_staged" "$cert_target" hysteria_cert 0644 || return $?
    pnm_tx_write_file "$key_staged" "$key_target" hysteria_key 0600 || return $?
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

    pnm_sandbox_cleanup_staging || true
    pnm_tx_close
    return "$rc"
}

pnm_sandbox_install() {
    local root="${1:?isolated root required}"
    local rc

    [[ "$root" == /* && ! -L "$root" ]] || return "$PNM_EXIT_CONFIG"
    if [[ "$root" == '/' ]]; then
        (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 )) || return "$PNM_EXIT_NOPERM"
        [[ "${PNM_HOST_APPLY_CONFIRMED:-no}" == yes ]] || return "$PNM_EXIT_NOPERM"
        pnm_require_root || return $?
    fi
    pnm_mkdir_mode 0700 "$root" || return "$PNM_EXIT_CANTCREAT"
    PNM_SANDBOX_ROOT="${root%/}"
    PNM_SANDBOX_STAGING="$PNM_SANDBOX_ROOT/.pnm-staging"
    pnm_load_node_config PNM_SANDBOX_NODE || return "$PNM_EXIT_CONFIG"
    pnm_load_reality_secret PNM_SANDBOX_REALITY || return "$PNM_EXIT_CONFIG"
    pnm_load_hysteria_secret PNM_SANDBOX_HYSTERIA || return "$PNM_EXIT_CONFIG"
    pnm_render_validate_inputs PNM_SANDBOX_NODE PNM_SANDBOX_REALITY PNM_SANDBOX_HYSTERIA || return "$PNM_EXIT_CONFIG"
    PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || return $?
    pnm_tx_add_rollback pnm_tx_restore_written_files || {
        pnm_tx_close
        return "$PNM_EXIT_SOFTWARE"
    }
    if [[ "$PNM_SANDBOX_ROOT" == '/' ]]; then
        pnm_tx_add_rollback pnm_service_accounts_rollback || {
            pnm_tx_close
            return "$PNM_EXIT_SOFTWARE"
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
    pnm_tx_commit || { rc=$?; pnm_sandbox_abort "$rc"; return $?; }
    pnm_sandbox_cleanup_staging || { pnm_tx_journal CLEANUP_REQUIRED 'staging directory remains'; }
    pnm_tx_close
}

pnm_sandbox_cleanup_staging() {
    [[ -n "$PNM_SANDBOX_ROOT" && "$PNM_SANDBOX_STAGING" == "$PNM_SANDBOX_ROOT/.pnm-staging" ]] || return "$PNM_EXIT_CONFIG"
    [[ ! -e "$PNM_SANDBOX_STAGING" ]] || rm -rf -- "$PNM_SANDBOX_STAGING"
}
