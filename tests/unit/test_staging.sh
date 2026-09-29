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
# shellcheck source=../../adapters/assets.sh
source "$PNM_ADAPTER_DIR/assets.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_hysteria_binary_stage_is_private_and_executable() {
    local temp_dir source staged mode
    temp_dir="$(mktemp -d)"
    source="$temp_dir/source"
    printf 'hysteria binary fixture' >"$source"
    staged="$(pnm_asset_stage_hysteria_binary "$source" "$temp_dir/staging")" || { rm -rf -- "$temp_dir"; return 1; }
    mode="$(stat -c '%a' "$staged")"
    rm -rf -- "$temp_dir"
    assert_eq 755 "$mode"
}

test_xray_zip_stage_rejects_traversal() {
    local temp_dir archive rc
    temp_dir="$(mktemp -d)"
    archive="$temp_dir/malicious.zip"
    python3 - "$archive" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("../escape", "bad")
    archive.writestr("xray", "binary")
PY
    if pnm_asset_stage_xray_zip "$archive" "$temp_dir/staging" >/dev/null 2>&1; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 78 "$rc"
}

test_xray_zip_stage_accepts_safe_archive() {
    local temp_dir input archive staged
    temp_dir="$(mktemp -d)"
    input="$temp_dir/xray"
    archive="$temp_dir/xray.zip"
    printf 'xray binary fixture' >"$input"
    (cd "$temp_dir" && zip -q -j "$archive" xray)
    staged="$(pnm_asset_stage_xray_zip "$archive" "$temp_dir/staging")" || { rm -rf -- "$temp_dir"; return 1; }
    [[ -f "$staged" && -x "$staged" ]]
    rm -rf -- "$temp_dir"
}

run_test 'Hysteria2 binary staging sets executable mode' test_hysteria_binary_stage_is_private_and_executable
run_test 'Xray ZIP staging rejects traversal members' test_xray_zip_stage_rejects_traversal
run_test 'Xray ZIP staging accepts a safe archive' test_xray_zip_stage_accepts_safe_archive
finish_tests
