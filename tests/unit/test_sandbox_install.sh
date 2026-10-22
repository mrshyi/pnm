#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TEST_ROOT/.." && pwd -P)"
PNM_LIB_DIR="$PROJECT_ROOT/lib"
PNM_ADAPTER_DIR="$PROJECT_ROOT/adapters"
PNM_VERSION_FILE="$PROJECT_ROOT/VERSION"
# shellcheck source=../../lib/common.sh
source "$PNM_LIB_DIR/common.sh"
# shellcheck source=../../lib/output.sh
source "$PNM_LIB_DIR/output.sh"
# shellcheck source=../../lib/config.sh
source "$PNM_LIB_DIR/config.sh"
# shellcheck source=../../lib/lock.sh
source "$PNM_LIB_DIR/lock.sh"
# shellcheck source=../../lib/transaction.sh
source "$PNM_LIB_DIR/transaction.sh"
# shellcheck source=../../lib/accounts.sh
source "$PNM_LIB_DIR/accounts.sh"
# shellcheck source=../../lib/render.sh
source "$PNM_LIB_DIR/render.sh"
# shellcheck source=../../lib/service.sh
source "$PNM_LIB_DIR/service.sh"
# shellcheck source=../../lib/tls.sh
source "$PNM_LIB_DIR/tls.sh"
# shellcheck source=../../adapters/assets.sh
source "$PNM_ADAPTER_DIR/assets.sh"
# shellcheck source=../../lib/sandbox-install.sh
source "$PNM_LIB_DIR/sandbox-install.sh"
# shellcheck source=../../lib/node.sh
source "$PNM_LIB_DIR/node.sh"
# shellcheck source=../../lib/deploy.sh
source "$PNM_LIB_DIR/deploy.sh"
source "$PNM_LIB_DIR/core-ops.sh"
source "$PNM_LIB_DIR/lifecycle.sh"
source "$PNM_LIB_DIR/apply-gate.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

# Share links contain client credentials. Keep assertion failures from dumping
# the captured output into CI logs.
assert_sensitive_output_contains() { [[ "${1-}" == *"${2-}"* ]]; }

make_xray_archive() {
    local destination="${1:?archive destination required}"
    local behavior="${2:?behavior required}"
    local temp_dir script

    temp_dir="$(mktemp -d)"
    script="$temp_dir/xray"
    if [[ "$behavior" == pass ]]; then
        printf '%s\n' '#!/usr/bin/env bash' \
            'case "${1-}" in' \
            '  run) [[ "${2-}" == -test ]] ;;' \
            '  x25519) printf "PrivateKey: fixture-private\\nPassword (PublicKey): AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\nHash32: ignored\\n" ;;' \
            '  *) exit 1 ;;' \
            'esac' >"$script"
    else
        printf '%s\n' '#!/usr/bin/env bash' 'exit 23' >"$script"
    fi
    chmod 0755 -- "$script"
    (cd "$temp_dir" && zip -q -j "$destination" xray)
    rm -rf -- "$temp_dir"
}

prepare_sandbox_inputs() {
    local temp_dir="$1"
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='sandbox-test'
    PNM_SANDBOX_HY2_BINARY="$temp_dir/hysteria"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$PNM_SANDBOX_HY2_BINARY"
    chmod 0755 -- "$PNM_SANDBOX_HY2_BINARY"
}

prepare_external_tls_inputs() {
    local temp_dir="$1"
    local config_dir="$temp_dir/config"

    mkdir -p -- "$config_dir/secrets"
    sed 's/^HY2_TLS_MODE=.*/HY2_TLS_MODE=external-ca/;s/^HY2_TLS_SERVER_NAME=.*/HY2_TLS_SERVER_NAME=example.com/' \
        "$TEST_ROOT/fixtures/config-secrets/node.conf" >"$config_dir/node.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/versions.conf" "$config_dir/versions.conf"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/reality.env" "$config_dir/secrets/reality.env"
    cp -- "$TEST_ROOT/fixtures/config-secrets/secrets/hysteria.env" "$config_dir/secrets/hysteria.env"
    PNM_CONFIG_DIR="$config_dir"
    PNM_SANDBOX_EXTERNAL_CERT="$temp_dir/external.crt"
    PNM_SANDBOX_EXTERNAL_KEY="$temp_dir/external.key"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -days 2 -subj '/CN=example.com' -addext 'subjectAltName=DNS:example.com' \
        -keyout "$PNM_SANDBOX_EXTERNAL_KEY" -out "$PNM_SANDBOX_EXTERNAL_CERT" >/dev/null 2>&1
}

prepare_fresh_sandbox_inputs() {
    local temp_dir="$1" root="$2"
    mkdir -p -- "$root"
    PNM_CONFIG_DIR="$root/etc/pnm"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_DRY_RUN=0
    PNM_TX_ID_OVERRIDE='fresh-node-init'
    pnm_require_root() { return 0; }
    pnm_node_init 0 \
        --region vps --address 203.0.113.10 \
        --xray-version v1.2.3 --xray-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        --hy2-version v2.3.4 --hy2-sha256 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb || return $?
    PNM_SANDBOX_HY2_BINARY="$temp_dir/hysteria"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$PNM_SANDBOX_HY2_BINARY"
    chmod 0755 -- "$PNM_SANDBOX_HY2_BINARY"
}

test_first_install_generates_and_reuses_secrets() {
    local temp_dir root archive first_reality first_hy2 first_cert_pin second_cert_pin first_cert_hash second_cert_hash
    local -A reality=() hysteria=()
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root"
    make_xray_archive "$archive" pass
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_TX_ID_OVERRIDE='fresh-secrets-first'
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }

    pnm_load_reality_secret reality && pnm_validate_reality_secret_config reality || { rm -rf -- "$temp_dir"; return 1; }
    pnm_load_hysteria_secret hysteria && pnm_validate_hysteria_secret_config hysteria || { rm -rf -- "$temp_dir"; return 1; }
    [[ "${reality[XRAY_UUID]}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "${reality[XRAY_REALITY_SHORT_ID]}" =~ ^[a-f0-9]{16}$ ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "${reality[XRAY_REALITY_PRIVATE_KEY]}" =~ ^[A-Za-z0-9_-]{43}$ ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "${hysteria[HY2_AUTH_PASSWORD]}" =~ ^[A-Za-z0-9_-]{43}$ ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(stat -c '%a' "$PNM_CONFIG_DIR/secrets/reality.env")" == 600 ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(stat -c '%a' "$PNM_CONFIG_DIR/secrets/hysteria.env")" == 600 ]] || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tls_validate_pair "$root/etc/hysteria/tls/server.crt" "$root/etc/hysteria/tls/server.key" || { rm -rf -- "$temp_dir"; return 1; }
    first_reality="${reality[XRAY_UUID]}|${reality[XRAY_REALITY_PRIVATE_KEY]}|${reality[XRAY_REALITY_SHORT_ID]}"
    first_hy2="${hysteria[HY2_AUTH_PASSWORD]}"
    first_cert_pin="${hysteria[HY2_TLS_PIN_SHA256]}"
    first_cert_hash="$(sha256sum "$root/etc/hysteria/tls/server.crt")"

    PNM_TX_ID_OVERRIDE='fresh-secrets-second'
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_load_reality_secret reality && pnm_load_hysteria_secret hysteria || { rm -rf -- "$temp_dir"; return 1; }
    second_cert_pin="$(pnm_tls_spki_pin "$root/etc/hysteria/tls/server.crt")"
    second_cert_hash="$(sha256sum "$root/etc/hysteria/tls/server.crt")"
    pnm_tls_certificate_matches_dns_name "$root/etc/hysteria/tls/server.crt" proxy-vps || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$first_reality" "${reality[XRAY_UUID]}|${reality[XRAY_REALITY_PRIVATE_KEY]}|${reality[XRAY_REALITY_SHORT_ID]}" || return 1
    assert_eq "$first_hy2" "${hysteria[HY2_AUTH_PASSWORD]}" || return 1
    assert_eq "$first_cert_pin" "$second_cert_pin" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$first_cert_hash" "$second_cert_hash" || return 1
    rm -rf -- "$temp_dir"
}

test_corrupt_secret_stops_without_replacing_it() {
    local temp_dir root archive rc original
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root"
    mkdir -m 0700 -- "$PNM_CONFIG_DIR/secrets"
    printf '%s\n' 'SCHEMA_VERSION=1' 'XRAY_UUID=invalid' >"$PNM_CONFIG_DIR/secrets/reality.env"
    original="$(<"$PNM_CONFIG_DIR/secrets/reality.env")"
    make_xray_archive "$archive" pass
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_TX_ID_OVERRIDE='corrupt-secret'
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq "$original" "$(<"$PNM_CONFIG_DIR/secrets/reality.env")" || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/usr/local/bin/xray" && ! -e "$PNM_STATE_DIR/transactions/corrupt-secret" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_failed_first_install_rolls_back_secrets_and_retry_succeeds() {
    local temp_dir root archive rc
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root"
    make_xray_archive "$archive" fail
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_TX_ID_OVERRIDE='fresh-secrets-failed'
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$PNM_CONFIG_DIR/secrets/reality.env" && ! -e "$PNM_CONFIG_DIR/secrets/hysteria.env" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/usr/local/bin/xray" ]] || { rm -rf -- "$temp_dir"; return 1; }

    make_xray_archive "$archive" pass
    PNM_TX_ID_OVERRIDE='fresh-secrets-retry'
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -s "$PNM_CONFIG_DIR/secrets/reality.env" && -s "$PNM_CONFIG_DIR/secrets/hysteria.env" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_node_links_work_after_fresh_install() {
    local temp_dir root archive old_xray_bin old_xray_config old_hy2_config
    local -A link_node=() link_hysteria=()
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root"
    make_xray_archive "$archive" pass
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_TX_ID_OVERRIDE='fresh-secrets-links'
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    old_xray_bin="$PNM_XRAY_BIN"
    old_xray_config="$PNM_XRAY_CONFIG"
    old_hy2_config="$PNM_HY2_CONFIG"
    PNM_XRAY_BIN="$root/usr/local/bin/xray"
    PNM_XRAY_CONFIG="$root/usr/local/etc/xray/config.json"
    PNM_HY2_CONFIG="$root/etc/hysteria/config.yaml"
    pnm_load_node_config link_node && pnm_load_hysteria_secret link_hysteria || { rm -rf -- "$temp_dir"; return 1; }
    link_hysteria[HY2_TLS_CERT_PATH]="$root/etc/hysteria/tls/server.crt"
    link_hysteria[HY2_TLS_KEY_PATH]="$root/etc/hysteria/tls/server.key"
    pnm_render_hysteria_secret_config link_hysteria >"$PNM_CONFIG_DIR/secrets/hysteria.env" || { rm -rf -- "$temp_dir"; return 1; }
    chmod 0600 -- "$PNM_CONFIG_DIR/secrets/hysteria.env" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_render_hysteria_config link_node link_hysteria >"$PNM_HY2_CONFIG" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_systemd_active_state() { printf 'active\n'; }
    pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
    pnm_listener_present() { return 0; }
    PNM_TX_ID_OVERRIDE='fresh-secrets-configured'
    pnm_deploy_mark_configured || { rm -rf -- "$temp_dir"; return 1; }
    pnm_require_root() { return 0; }
    run_capture pnm_node_links --address 203.0.113.10
    PNM_XRAY_BIN="$old_xray_bin"
    PNM_XRAY_CONFIG="$old_xray_config"
    PNM_HY2_CONFIG="$old_hy2_config"
    rm -rf -- "$temp_dir"
    assert_eq 0 "$RUN_RC" || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'vless://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '&sni=www.cloudflare.com&fp=chrome' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'hysteria2://' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" '?sni=proxy-vps&insecure=1' || return 1
    assert_sensitive_output_contains "$RUN_OUTPUT" 'pinSHA256='
}

test_sandbox_install_commits_all_resources() {
    local temp_dir root archive journal pin
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    mkdir -p -- "$root/usr/local/bin" "$root/etc/systemd/system"
    chmod 0750 -- "$root/usr/local/bin" "$root/etc/systemd/system"
    make_xray_archive "$archive" pass
    prepare_sandbox_inputs "$temp_dir"
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_STATE_DIR/transactions/sandbox-test/journal.tsv"
    [[ -f "$root/usr/local/etc/xray/config.json" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ -f "$root/etc/hysteria/config.yaml" && -f "$root/etc/hysteria/tls/server.key" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ -f "$root/etc/systemd/system/xray.service" && -f "$root/etc/systemd/system/hysteria-server.service" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/.pnm-staging" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$PNM_SANDBOX_STAGING" ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 750 "$(stat -c '%a' "$root/usr/local/bin")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 750 "$(stat -c '%a' "$root/etc/systemd/system")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 700 "$(stat -c '%a' "$root/etc/pnm/secrets")" || { rm -rf -- "$temp_dir"; return 1; }
    assert_eq 755 "$(stat -c '%a' "$root/etc/hysteria")" || { rm -rf -- "$temp_dir"; return 1; }
    pin="$(sed -n 's/^HY2_TLS_PIN_SHA256=//p' "$root/etc/pnm/secrets/hysteria.env")"
    pnm_validate_pin_sha256 "$pin" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'COMMIT\t'
    assert_not_contains "$(<"$journal")" 'abcdefghijklmnopqrstuvwxyz012345'
    rm -rf -- "$temp_dir"
}

test_sandbox_install_rolls_back_after_validation_failure() {
    local temp_dir root archive journal rc
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray-fail.zip"
    mkdir -m 0700 -- "$root"
    make_xray_archive "$archive" fail
    prepare_sandbox_inputs "$temp_dir"
    PNM_TX_ID_OVERRIDE='sandbox-failure'
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    journal="$PNM_STATE_DIR/transactions/sandbox-failure/journal.tsv"
    [[ "$rc" == 78 ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/usr/local/bin/xray" && ! -e "$root/etc/hysteria/config.yaml" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$PNM_SANDBOX_STAGING" ]] || { rm -rf -- "$temp_dir"; return 1; }
    assert_not_contains "$(<"$journal")" $'COMMIT\t'
    assert_contains "$(<"$journal")" $'RESTORED\t'
    rm -rf -- "$temp_dir"
}

test_asset_staging_failure_rolls_back_transaction() {
    local temp_dir root archive rc journal
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/not-a-zip.zip"
    mkdir -m 0700 -- "$root"
    printf 'invalid archive\n' >"$archive"
    prepare_sandbox_inputs "$temp_dir"
    PNM_TX_ID_OVERRIDE='sandbox-stage-assets-failure'
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    journal="$PNM_STATE_DIR/transactions/sandbox-stage-assets-failure/journal.tsv"
    assert_eq 78 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'STEP_FAILED\tstage_assets rc=78' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'ROLLBACK_COMPLETE\t' || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/usr/local/bin/xray" && ! -e "$root/usr/local/bin/hysteria" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$PNM_SANDBOX_STAGING" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_abort_reports_original_and_rollback_failure_codes() {
    local temp_dir journal rc
    temp_dir="$(mktemp -d)"
    PNM_STATE_DIR="$temp_dir/state"
    PNM_LOCK_FILE="$temp_dir/pnm.lock"
    PNM_TX_ID_OVERRIDE='sandbox-recovery-message'
    PNM_DRY_RUN=0
    pnm_tx_begin sandbox-install || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_TX_PATH/journal.tsv"
    PNM_TX_RECOVERY_REQUIRED=1
    PNM_TX_STEP_FAILURE_NAME='stage_assets'
    PNM_TX_STEP_FAILURE_RC=69
    PNM_TX_ROLLBACK_FAILURE_RC=70
    PNM_SANDBOX_STAGING=''
    run_capture pnm_sandbox_abort 69
    rc="$RUN_RC"
    assert_eq 69 "$rc" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$RUN_ERROR" "step 'stage_assets' failed with exit code 69" || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$RUN_ERROR" 'rollback failed with exit code 70' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$RUN_ERROR" 'Recovery is required' || { rm -rf -- "$temp_dir"; return 1; }
    assert_contains "$(<"$journal")" $'RECOVERY_REQUIRED\ttransaction closed with uncertain state'
    rm -rf -- "$temp_dir"
}

test_sandbox_install_imports_external_tls_and_rewrites_pin() {
    local temp_dir root archive pin expected
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    make_xray_archive "$archive" pass
    prepare_sandbox_inputs "$temp_dir"
    prepare_external_tls_inputs "$temp_dir"
    PNM_TX_ID_OVERRIDE='sandbox-external'
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    pin="$(sed -n 's/^HY2_TLS_PIN_SHA256=//p' "$root/etc/pnm/secrets/hysteria.env")"
    expected="$(pnm_tls_spki_pin "$root/etc/hysteria/tls/server.crt")"
    assert_eq "$expected" "$pin" || { rm -rf -- "$temp_dir"; return 1; }
    pnm_tls_validate_pair "$root/etc/hysteria/tls/server.crt" "$root/etc/hysteria/tls/server.key" || {
        rm -rf -- "$temp_dir"
        return 1
    }
    [[ ! -e "$root/.pnm-staging" ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

test_failed_install_restores_directory_baseline() (
    local temp_dir root archive rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    root="$temp_dir/root" archive="$temp_dir/xray.zip"
    prepare_sandbox_inputs "$temp_dir"
    make_xray_archive "$archive" fail
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    [[ ! -e "$root" ]] || return 1
    pnm_tx_load_for_inspect sandbox-test || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 0 "$PNM_TX_INSPECT_CHANGES" || return 1
    mkdir -p "$root/etc/hysteria"
    chmod 0750 "$root" "$root/etc/hysteria"
    PNM_TX_ID_OVERRIDE=sandbox-existing-dirs
    if pnm_sandbox_install "$root"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq 750 "$(stat -c '%a' "$root")" || return 1
    assert_eq 750 "$(stat -c '%a' "$root/etc/hysteria")" || return 1
    [[ ! -e "$root/etc/hysteria/tls" && ! -e "$root/usr" ]]
)

test_shared_deployment_restores_real_sandbox_resources() (
    local temp_dir root archive rc original_node
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    root="$temp_dir/root" archive="$temp_dir/xray.zip"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root" || return 1
    make_xray_archive "$archive" pass || return 1
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_DEPLOY_SANDBOX_ROOT="$root"
    PNM_XRAY_BIN="$root/usr/local/bin/xray"
    PNM_XRAY_CONFIG="$root/usr/local/etc/xray/config.json"
    PNM_HY2_CONFIG="$root/etc/hysteria/config.yaml"
    PNM_ASSUME_YES=1
    PNM_TX_ID_OVERRIDE=shared-deployment
    PNM_DEPLOY_ID_OVERRIDE=deploy-shared
    PNM_APPLY_GATE_ID_OVERRIDE=apply-shared
    original_node="$(<"$PNM_CONFIG_DIR/node.conf")"
    declare -A fixture_active=([xray.service]=inactive [hysteria-server.service]=inactive)
    declare -A fixture_enabled=([xray.service]=disabled [hysteria-server.service]=disabled)
    pnm_preflight_collect() { return 0; }
    pnm_preflight_exit_code() { return 0; }
    pnm_systemd_load_state() {
        [[ -f "$root/etc/systemd/system/$1" ]] && printf 'loaded\n' || printf 'not-found\n'
    }
    pnm_systemd_active_state() { printf '%s\n' "${fixture_active[$1]}"; }
    pnm_systemd_enabled_state() { printf '%s\n' "${fixture_enabled[$1]}"; }
    pnm_systemd_show_value() { printf '0123456789abcdef0123456789abcdef\n'; }
    pnm_systemd_daemon_reload() { return 0; }
    pnm_systemctl() {
        case "$1" in
            start|restart) fixture_active[$2]=active ;;
            stop) fixture_active[$2]=inactive ;;
            enable) fixture_enabled[$2]=enabled ;;
            disable) fixture_enabled[$2]=disabled ;;
            *) return 70 ;;
        esac
    }
    pnm_systemd_enable() { pnm_systemctl enable "$1"; }
    pnm_systemd_start() { pnm_systemctl start "$1"; }
    pnm_systemd_unit_healthy() { [[ "${fixture_active[$1]}" == active ]]; }
    pnm_check_deploy_core_health() { return 0; }
    fail_outer_health() { return 78; }
    PNM_APPLY_GATE_STEP_HEALTH=fail_outer_health
    if pnm_apply_gate_execute; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq "$original_node" "$(<"$PNM_CONFIG_DIR/node.conf")" || return 1
    [[ ! -e "$root/usr" && ! -e "$root/etc/hysteria" && ! -e "$root/etc/systemd" ]] || return 1
    [[ ! -e "$PNM_CONFIG_DIR/secrets" && ! -e "$PNM_STATE_DIR/cores" ]] || return 1
    pnm_tx_load_for_inspect shared-deployment || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE" || return 1
    assert_eq 0 "$PNM_TX_INSPECT_CHANGES" || return 1
    assert_eq 0 "$PNM_LOCK_DEPTH"
)

test_reused_host_tls_has_transaction_ownership_baseline() (
    local temp_dir root archive cert key cert_hash key_hash cert_metadata key_metadata
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    root="$temp_dir/root" archive="$temp_dir/xray.zip"
    prepare_fresh_sandbox_inputs "$temp_dir" "$root" || return 1
    make_xray_archive "$archive" pass || return 1
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    PNM_TX_ID_OVERRIDE=existing-tls-install
    pnm_sandbox_install "$root" || return 1
    cert="$root/etc/hysteria/tls/server.crt" key="$root/etc/hysteria/tls/server.key"
    cert_hash="$(pnm_tx_file_sha256 "$cert")" key_hash="$(pnm_tx_file_sha256 "$key")"
    cert_metadata="$(stat -c '%a|%u|%g' -- "$cert")" key_metadata="$(stat -c '%a|%u|%g' -- "$key")"

    # Exercise the host-only reuse branch while mapping every path into this
    # disposable root. No host service or account operation is performed.
    pnm_sandbox_path() { printf '%s%s\n' "$root" "$1"; }
    PNM_SANDBOX_ROOT=/ PNM_TX_ID_OVERRIDE=reused-host-tls
    pnm_tx_begin deployment || return 1
    pnm_tx_add_rollback pnm_tx_restore_written_files || return 1
    PNM_DEPLOY_XRAY_LOAD=not-found PNM_DEPLOY_HY2_LOAD=not-found
    PNM_DEPLOY_XRAY_ACTIVE=inactive PNM_DEPLOY_HY2_ACTIVE=inactive
    PNM_DEPLOY_XRAY_ENABLED=disabled PNM_DEPLOY_HY2_ENABLED=disabled
    pnm_deploy_record_baseline || return 1
    PNM_SANDBOX_STAGING="$PNM_TX_PATH/staging"
    mkdir -m 0700 "$PNM_SANDBOX_STAGING" || return 1
    pnm_sandbox_step_tls || return 1
    pnm_tx_record_written_metadata "$key" || return 1
    pnm_tx_record_written_metadata "$cert" || return 1
    if ((EUID == 0)); then
        chown +65534:+65534 -- "$key" "$cert" || return 1
        pnm_tx_record_written_metadata "$key" || return 1
        pnm_tx_record_written_metadata "$cert" || return 1
    fi
    pnm_tx_verify_written_resources || return 1
    pnm_tx_rollback && pnm_tx_close || return 1
    assert_eq "$cert_hash" "$(pnm_tx_file_sha256 "$cert")" || return 1
    assert_eq "$key_hash" "$(pnm_tx_file_sha256 "$key")" || return 1
    assert_eq "$cert_metadata" "$(stat -c '%a|%u|%g' -- "$cert")" || return 1
    assert_eq "$key_metadata" "$(stat -c '%a|%u|%g' -- "$key")" || return 1
    pnm_tx_load_for_inspect reused-host-tls || return 1
    assert_eq ROLLED_BACK "$PNM_TX_INSPECT_STATE"
)

run_test 'reused host TLS keeps its bytes and restores ownership after rollback' test_reused_host_tls_has_transaction_ownership_baseline
run_test 'shared deployment restores actual staged sandbox resources after outer failure' test_shared_deployment_restores_real_sandbox_resources
run_test 'failed install restores original directories and removes new empty ancestors' test_failed_install_restores_directory_baseline
run_test 'sandbox install commits Core, TLS, config, and units' test_sandbox_install_commits_all_resources
run_test 'sandbox validation failure compensates all written files' test_sandbox_install_rolls_back_after_validation_failure
run_test 'asset staging failure rolls back the installation transaction' test_asset_staging_failure_rolls_back_transaction
run_test 'recovery message distinguishes original and rollback error codes' test_abort_reports_original_and_rollback_failure_codes
run_test 'sandbox install imports external TLS and rewrites pin' test_sandbox_install_imports_external_tls_and_rewrites_pin
run_test 'first install generates secure credentials and reuses them on repeat' test_first_install_generates_and_reuses_secrets
run_test 'corrupt credentials stop install without replacement' test_corrupt_secret_stops_without_replacing_it
run_test 'failed first install rolls back generated credentials and retry succeeds' test_failed_first_install_rolls_back_secrets_and_retry_succeeds
run_test 'client links work after fresh install' test_node_links_work_after_fresh_install
finish_tests
