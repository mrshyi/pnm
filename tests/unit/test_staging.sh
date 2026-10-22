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
source <(sed -n '/^make_backup_archive() {$/,/^}$/p' "$TEST_ROOT/unit/test_backup_archive.sh")

stage_suite_root="$(mktemp -d)"
trap 'rm -rf -- "$stage_suite_root"' EXIT

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

test_temp_directory_output_stays_in_the_calling_shell() {
    local stage='' count rc output
    count="${#PNM_CLEANUP_PATHS[@]}"
    run_capture pnm_make_temp_dir stage
    rc="$RUN_RC" output="$RUN_OUTPUT"
    pnm_cleanup
    assert_eq 0 "$rc" || return 1
    assert_eq '' "$output" || return 1
    [[ "$stage" == /tmp/pnm.* ]] || return 1
    assert_eq "$((count + 1))" "${#PNM_CLEANUP_PATHS[@]}" || return 1
    [[ ! -e "$stage" ]] || return 1
    run_capture pnm_make_temp_dir
    stage="$RUN_OUTPUT"
    assert_eq 0 "$RUN_RC" || return 1
    [[ "$stage" == /tmp/pnm.* && -d "$stage" ]] || return 1
    pnm_cleanup || return 1
    [[ ! -e "$stage" ]]
}

test_restore_validation_failure_cleans_real_staging_on_exit() {
    local archive="$stage_suite_root/archive.tar.gz" marker="$stage_suite_root/stage.path" child="$stage_suite_root/restore-child.sh" stage_path remained
    make_backup_archive "$archive" valid || return 1
    cat >"$child" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
project=$1 archive=$2 marker=$3 private=$4
source "$project/lib/common.sh"
source "$project/lib/output.sh"
source "$project/lib/config.sh"
source "$project/lib/lock.sh"
source "$project/lib/transaction.sh"
source "$project/lib/core-ops.sh"
PNM_STATE_DIR="$private/state" PNM_LOCK_FILE="$private/lock"
pnm_require_root() { return 0; }
pnm_platform_supported() { return 0; }
stat() {
    if ((EUID != 0)) && [[ "$1" == -c && "$2" == '%a:%u' ]]; then
        command stat -c '%a:0' -- "$4"
    else
        command stat "$@"
    fi
}
pnm_core_restore_validate_staged() { printf '%s\n' "$1" >"$marker"; return 78; }
pnm_init_runtime
pnm_core_restore "$archive"
BASH
    run_capture env TMPDIR=/tmp bash "$child" "$PROJECT_ROOT" "$archive" "$marker" "$stage_suite_root"
    assert_eq 78 "$RUN_RC" || return 1
    stage_path="$(<"$marker")"
    remained=no
    if [[ -e "$stage_path" ]]; then
        remained=yes
        # Clean only our proven mktemp artifact after the red run. Never use
        # a marker path as an unchecked recursive-removal argument.
        [[ "$stage_path" == /tmp/pnm.* && "$(dirname -- "$stage_path")" == /tmp &&
            -d "$stage_path" && ! -L "$stage_path" && "$(stat -c '%a:%u' "$stage_path")" == "700:$EUID" ]] || return 1
        rm -rf -- "$stage_path"
    fi
    assert_eq no "$remained" 'restore candidate staging must be removed by the real EXIT cleanup'
}

test_failed_cleanup_registration_propagates_without_temp_leak() {
    local stage='' rc
    mkdir "$stage_suite_root/not-registered"
    TMPDIR="$stage_suite_root/not-registered" run_capture pnm_make_temp_dir stage
    rc="$RUN_RC"
    assert_eq 77 "$rc" || return 1
    assert_eq '' "$stage" || return 1
    [[ -z "$(find "$stage_suite_root/not-registered" -mindepth 1 -print -quit)" ]]
}

test_temp_output_target_cannot_be_an_expression() {
    local rc
    run_capture pnm_make_temp_dir 'stage[1]'
    rc="$RUN_RC"
    pnm_cleanup
    assert_eq 78 "$rc"
}

test_cleanup_is_idempotent_when_a_registered_directory_is_gone() {
    local stage='' rc
    pnm_make_temp_dir stage || return 1
    rmdir -- "$stage" || return 1
    if pnm_cleanup; then rc=0; else rc=$?; fi
    assert_eq 0 "$rc"
}

test_exit_cleanup_failure_does_not_replace_the_original_error() {
    local child="$stage_suite_root/cleanup-child.sh" marker="$stage_suite_root/cleanup.path" stage_path
    cat >"$child" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$1/lib/common.sh"
source "$1/lib/output.sh"
marker=$2
pnm_init_runtime
pnm_make_temp_dir stage
printf '%s\n' "$stage" >"$marker"
rm() { return 73; }
exit 78
BASH
    run_capture env TMPDIR=/tmp bash "$child" "$PROJECT_ROOT" "$marker"
    stage_path="$(<"$marker")"
    [[ "$stage_path" == /tmp/pnm.* && "$(dirname -- "$stage_path")" == /tmp &&
        -d "$stage_path" && ! -L "$stage_path" && "$(stat -c '%a:%u' "$stage_path")" == "700:$EUID" ]] || return 1
    rmdir -- "$stage_path" || return 1
    assert_eq 78 "$RUN_RC" || return 1
    assert_contains "$RUN_ERROR" 'Temporary cleanup failed'
}

test_stdout_failure_removes_the_new_directory() {
    local marker="$stage_suite_root/stdout.path" stage_path rc
    # Capture only the created path in a separate marker; stdout must really fail.
    if (pnm_register_cleanup_path() { printf '%s\n' "$1" >"$marker"; }; pnm_make_temp_dir >/dev/full 2>/dev/null); then rc=0; else rc=$?; fi
    stage_path="$(<"$marker")"
    if [[ -e "$stage_path" ]]; then
        [[ "$stage_path" == /tmp/pnm.* && "$(dirname -- "$stage_path")" == /tmp &&
            -d "$stage_path" && ! -L "$stage_path" && "$(stat -c '%a:%u' "$stage_path")" == "700:$EUID" ]] || return 1
        rmdir -- "$stage_path" || return 1
        printf '%s\n' 'failed stdout publication left its temporary directory' >&2
        return 1
    fi
    [[ "$rc" != 0 ]]
}

run_test 'stdout publication failure removes its temporary directory' test_stdout_failure_removes_the_new_directory
run_test 'Hysteria2 binary staging sets executable mode' test_hysteria_binary_stage_is_private_and_executable
run_test 'Xray ZIP staging rejects traversal members' test_xray_zip_stage_rejects_traversal
run_test 'Xray ZIP staging accepts a safe archive' test_xray_zip_stage_accepts_safe_archive
run_test 'temporary path output and cleanup registration stay in the caller' test_temp_directory_output_stays_in_the_calling_shell
run_test 'restore candidate rejection cleans its real temporary directory on EXIT' test_restore_validation_failure_cleans_real_staging_on_exit
run_test 'failed temporary cleanup registration propagates and removes the directory' test_failed_cleanup_registration_propagates_without_temp_leak
run_test 'temporary path output rejects expression targets' test_temp_output_target_cannot_be_an_expression
run_test 'temporary cleanup is idempotent for already-removed directories' test_cleanup_is_idempotent_when_a_registered_directory_is_gone
run_test 'EXIT cleanup failures do not mask the original command error' test_exit_cleanup_failure_does_not_replace_the_original_error
finish_tests
