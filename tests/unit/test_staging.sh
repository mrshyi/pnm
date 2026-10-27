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
# shellcheck source=tests/unit/test_backup_archive.sh
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

hysteria_staging_preserves_occupied_destination() (
    local kind="$1" timing temp_dir destination
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf 'synthetic Core candidate' >"$temp_dir/source"
    printf 'foreign target' >"$temp_dir/sentinel"
    for timing in existing late; do
        mkdir -m 0700 "$temp_dir/$timing"
        destination="$temp_dir/$timing/hysteria"
        occupy_destination() {
            case "$kind" in
                file) printf 'foreign file' >"$destination" ;;
                directory) mkdir "$destination"; printf 'foreign contents' >"$destination/marker" ;;
                link) command ln -s -- "$temp_dir/sentinel" "$destination" ;;
            esac
        }
        if [[ "$timing" == existing ]]; then occupy_destination || return 1; fi
        install() {
            if [[ "$timing" == late ]]; then occupy_destination || return 1; fi
            command install "$@"
        }
        run_capture pnm_asset_stage_hysteria_binary "$temp_dir/source" "$temp_dir/$timing"
        unset -f install
        assert_eq "$PNM_EXIT_CANTCREAT" "$RUN_RC" || return 1
        assert_eq '' "$RUN_OUTPUT" || return 1
        case "$kind" in
            file) assert_eq 'foreign file' "$(<"$destination")" || return 1 ;;
            directory)
                assert_eq 'foreign contents' "$(<"$destination/marker")" || return 1
                assert_eq 1 "$(find "$destination" -mindepth 1 -maxdepth 1 | wc -l)" || return 1 ;;
            link) [[ -L "$destination" && "$(readlink -- "$destination")" == "$temp_dir/sentinel" ]] || return 1 ;;
        esac
        assert_eq 'foreign target' "$(<"$temp_dir/sentinel")" || return 1
        [[ -z "$(find "$temp_dir/$timing" -maxdepth 1 -name '.pnm-*' -print -quit)" ]] || return 1
    done
)

test_hysteria_staging_preserves_files() { hysteria_staging_preserves_occupied_destination file; }
test_hysteria_staging_preserves_directories() { hysteria_staging_preserves_occupied_destination directory; }
test_hysteria_staging_preserves_links() { hysteria_staging_preserves_occupied_destination link; }

test_hysteria_staging_copy_failure_leaves_no_binary() (
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    printf 'synthetic Core candidate' >"$temp_dir/source"
    install() { command install "$@" || return $?; return 23; }
    run_capture pnm_asset_stage_hysteria_binary "$temp_dir/source" "$temp_dir/staging"
    assert_eq "$PNM_EXIT_CANTCREAT" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    [[ -z "$(find "$temp_dir/staging" -mindepth 1 -print -quit)" ]]
)

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

test_xray_stage_rejects_nonzip_without_executable_publication() (
    local temp_dir archive output rc digest
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    archive="$temp_dir/invalid.zip"
    printf 'untrusted non-ZIP response' >"$archive"
    digest="$(sha256sum "$archive" | awk '{print $1}')"
    if output="$(pnm_asset_stage_xray_zip "$archive" "$temp_dir/staging" 2>/dev/null)"; then rc=0; else rc=$?; fi
    assert_eq 78 "$rc" || return 1
    assert_eq '' "$output" || return 1
    [[ ! -e "$temp_dir/staging/xray-extract/xray" ]] || return 1
    assert_eq "$digest" "$(sha256sum "$archive" | awk '{print $1}')"
)

xray_staging_observation_failure_refuses_candidate() (
    local behavior="$1" expected_rc="$2" temp_dir archive digest
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    archive="$temp_dir/asset.zip"
    printf 'safe synthetic Xray asset\n' >"$temp_dir/xray" || return 1
    (cd "$temp_dir" && zip -q -j asset.zip xray) || return 1
    digest="$(sha256sum "$archive" | awk '{print $1}')"
    unzip() {
        if [[ "$1" == -Z1 ]]; then
            case "$behavior" in
                listing-failed-with-member) printf 'xray\n'; return 23 ;;
                listing-failed-empty) return 23 ;;
                listing-empty-success) return 0 ;;
            esac
        else
            printf 'called\n' >"$temp_dir/extraction-called"
        fi
        command unzip "$@"
    }
    if [[ "$behavior" == chmod-failed ]]; then
        chmod() {
            if [[ "$1" == 0755 && "${!#}" == */xray-extract/xray ]]; then return 1; fi
            command chmod "$@"
        }
    fi
    run_capture pnm_asset_stage_xray_zip "$archive" "$temp_dir/staging"
    assert_eq "$expected_rc" "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    assert_eq "$digest" "$(sha256sum "$archive" | awk '{print $1}')" || return 1
    if [[ "$behavior" == chmod-failed ]]; then
        [[ -f "$temp_dir/extraction-called" && ! -x "$temp_dir/staging/xray-extract/xray" ]]
    else
        [[ ! -e "$temp_dir/extraction-called" && ! -e "$temp_dir/staging/xray-extract/xray" ]]
    fi
)

test_failed_xray_listing_with_output_refuses_before_extraction() { xray_staging_observation_failure_refuses_candidate listing-failed-with-member 78; }
test_failed_empty_xray_listing_refuses_before_extraction() { xray_staging_observation_failure_refuses_candidate listing-failed-empty 78; }
test_successful_empty_xray_listing_refuses_before_extraction() { xray_staging_observation_failure_refuses_candidate listing-empty-success 78; }
test_xray_candidate_permission_failure_refuses_its_path() { xray_staging_observation_failure_refuses_candidate chmod-failed 77; }

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
    if ((EUID != 0)) && [[ "$1" == -c && "$2" == '%a:%u:%d:%i' ]]; then
        command stat -c '%a:0:%d:%i' -- "$4"
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
run_test 'Hysteria2 staging preserves existing and late files' test_hysteria_staging_preserves_files
run_test 'Hysteria2 staging refuses existing and late directories' test_hysteria_staging_preserves_directories
run_test 'Hysteria2 staging preserves existing and late links and targets' test_hysteria_staging_preserves_links
run_test 'Hysteria2 staging removes an incompletely copied private candidate' test_hysteria_staging_copy_failure_leaves_no_binary
run_test 'Xray ZIP staging rejects traversal members' test_xray_zip_stage_rejects_traversal
run_test 'Xray ZIP staging accepts a safe archive' test_xray_zip_stage_accepts_safe_archive
run_test 'non-ZIP response refuses without executable publication or input changes' test_xray_stage_rejects_nonzip_without_executable_publication
run_test 'failed ZIP listing with valid-looking output stops before extraction' test_failed_xray_listing_with_output_refuses_before_extraction
run_test 'failed empty ZIP listing stops before extraction' test_failed_empty_xray_listing_refuses_before_extraction
run_test 'successful empty ZIP listing cannot authorize extraction' test_successful_empty_xray_listing_refuses_before_extraction
run_test 'failed Xray executable mode setup suppresses the candidate path' test_xray_candidate_permission_failure_refuses_its_path
run_test 'temporary path output and cleanup registration stay in the caller' test_temp_directory_output_stays_in_the_calling_shell
run_test 'restore candidate rejection cleans its real temporary directory on EXIT' test_restore_validation_failure_cleans_real_staging_on_exit
run_test 'failed temporary cleanup registration propagates and removes the directory' test_failed_cleanup_registration_propagates_without_temp_leak
run_test 'temporary path output rejects expression targets' test_temp_output_target_cannot_be_an_expression
run_test 'temporary cleanup is idempotent for already-removed directories' test_cleanup_is_idempotent_when_a_registered_directory_is_gone
run_test 'EXIT cleanup failures do not mask the original command error' test_exit_cleanup_failure_does_not_replace_the_original_error
finish_tests
