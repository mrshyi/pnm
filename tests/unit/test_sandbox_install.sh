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
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

make_xray_archive() {
    local destination="${1:?archive destination required}"
    local behavior="${2:?behavior required}"
    local temp_dir script

    temp_dir="$(mktemp -d)"
    script="$temp_dir/xray"
    if [[ "$behavior" == pass ]]; then
        printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == run && "$2" == -test ]]' >"$script"
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
    sed 's/^HY2_TLS_MODE=.*/HY2_TLS_MODE=external-ca/' \
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

test_sandbox_install_commits_all_resources() {
    local temp_dir root archive journal pin
    temp_dir="$(mktemp -d)"
    root="$temp_dir/root"
    archive="$temp_dir/xray.zip"
    mkdir -m 0700 -- "$root"
    make_xray_archive "$archive" pass
    prepare_sandbox_inputs "$temp_dir"
    PNM_SANDBOX_XRAY_ARCHIVE="$archive"
    pnm_sandbox_install "$root" || { rm -rf -- "$temp_dir"; return 1; }
    journal="$PNM_STATE_DIR/transactions/sandbox-test/journal.tsv"
    [[ -f "$root/usr/local/etc/xray/config.json" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ -f "$root/etc/hysteria/config.yaml" && -f "$root/etc/hysteria/tls/server.key" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ -f "$root/etc/systemd/system/xray.service" && -f "$root/etc/systemd/system/hysteria-server.service" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ ! -e "$root/.pnm-staging" ]] || { rm -rf -- "$temp_dir"; return 1; }
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
    assert_not_contains "$(<"$journal")" $'COMMIT\t'
    assert_contains "$(<"$journal")" $'RESTORED\t'
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

run_test 'sandbox install commits Core, TLS, config, and units' test_sandbox_install_commits_all_resources
run_test 'sandbox validation failure compensates all written files' test_sandbox_install_rolls_back_after_validation_failure
run_test 'sandbox install imports external TLS and rewrites pin' test_sandbox_install_imports_external_tls_and_rewrites_pin
finish_tests
