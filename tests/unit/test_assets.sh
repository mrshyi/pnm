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
# shellcheck source=../../lib/assets.sh
source "$PNM_LIB_DIR/assets.sh"
# shellcheck source=../testlib.sh
source "$TEST_ROOT/testlib.sh"

test_asset_urls_are_pinned_by_core_and_version() (
    local machine asset architecture
    uname() { printf '%s\n' "$machine"; }
    for machine in x86_64 aarch64; do
        if [[ "$machine" == x86_64 ]]; then
            asset=Xray-linux-64.zip architecture=amd64
        else
            asset=Xray-linux-arm64-v8a.zip architecture=arm64
        fi
        assert_eq "$architecture" "$(pnm_arch)" || return 1
        assert_eq "https://github.com/XTLS/Xray-core/releases/download/v1.2.3/$asset" "$(pnm_asset_url xray v1.2.3)" || return 1
        assert_eq "https://github.com/apernet/hysteria/releases/download/app%2Fv2.3.4/hysteria-linux-$architecture" "$(pnm_asset_url hysteria2 v2.3.4)" || return 1
    done
    machine=armv7l
    run_capture pnm_asset_url xray v1.2.3
    assert_eq 78 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT"
)

test_asset_hash_verification() {
    local temp_dir asset digest rc
    temp_dir="$(mktemp -d)"
    asset="$temp_dir/asset"
    printf 'verified payload' >"$asset"
    digest="$(sha256sum "$asset" | awk '{print $1}')"
    pnm_asset_verify_file "$asset" "$digest" || return 1
    if pnm_asset_verify_file "$asset" "${digest/a/b}"; then rc=0; else rc=$?; fi
    rm -rf -- "$temp_dir"
    assert_eq 1 "$rc"
}

test_asset_hash_accepts_backslash_in_source_path() (
    local temp_dir asset digest
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    asset="$temp_dir/asset\\name"
    printf 'verified payload' >"$asset"
    digest="$(sha256sum <"$asset")"
    digest="${digest%% *}"
    pnm_asset_verify_file "$asset" "$digest" || return 1
    [[ "$(<"$asset")" == 'verified payload' ]]
)

test_asset_hash_query_failure_refuses_even_with_matching_output() (
    local temp_dir asset digest
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    asset="$temp_dir/asset"
    printf 'verified payload' >"$asset"
    digest="$(sha256sum <"$asset")"
    digest="${digest%% *}"
    sha256sum() { printf '%s  -\n' "$digest"; return 23; }
    set +o pipefail
    run_capture pnm_asset_verify_file "$asset" "$digest"
    assert_eq 1 "$RUN_RC"
)

test_assets_loads_approved_manifest_without_output() (
    PNM_CONFIG_DIR="$TEST_ROOT/fixtures/config-secrets"
    run_capture pnm_assets_load
    assert_eq 0 "$RUN_RC" || return 1
    assert_eq '' "$RUN_OUTPUT" || return 1
    assert_eq '' "$RUN_ERROR" || return 1
    assert_eq 6 "${#PNM_ASSET_VERSIONS[@]}" || return 1
    assert_eq v1.0.0 "${PNM_ASSET_VERSIONS[XRAY_VERSION]}" || return 1
    assert_eq aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "${PNM_ASSET_VERSIONS[XRAY_SHA256]}" || return 1
    assert_eq v2.0.0 "${PNM_ASSET_VERSIONS[HY2_VERSION]}" || return 1
    assert_eq bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "${PNM_ASSET_VERSIONS[HY2_SHA256]}"
)

test_verified_download_atomically_installs_payload() {
    local temp_dir fakebin destination digest rc
    temp_dir="$(mktemp -d)"
    fakebin="$temp_dir/bin"
    destination="$temp_dir/payload"
    mkdir -m 0700 -- "$fakebin"
    printf '%s\n' '#!/usr/bin/env bash' 'target=' 'while (($# > 0)); do' '  if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi' 'done' 'printf "verified payload" >"$target"' >"$fakebin/curl"
    chmod 0700 -- "$fakebin/curl"
    digest="$(printf 'verified payload' | sha256sum | awk '{print $1}')"
    if PATH="$fakebin:$PATH" pnm_asset_download_verified xray v1.2.3 "$digest" "$destination"; then rc=0; else rc=$?; fi
    [[ "$rc" == 0 && -f "$destination" ]] || { rm -rf -- "$temp_dir"; return 1; }
    [[ "$(<"$destination")" == 'verified payload' ]] || { rm -rf -- "$temp_dir"; return 1; }
    rm -rf -- "$temp_dir"
}

asset_failure_preserves_publication_boundary() (
    local curl_rc="$1" expected_rc="$2" temp_dir fakebin destination digest rc
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    fakebin="$temp_dir/bin"
    destination="$temp_dir/payload"
    mkdir -m 0700 -- "$fakebin"
    printf 'preserve unrelated file' >"$temp_dir/sentinel"
    cat >"$fakebin/curl" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
target=''
while (($# > 0)); do
    if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi
done
[[ -n "$target" ]]
printf 'partial unverified asset' >"$target"
printf '%s\n' "$PNM_TEST_CURL_RC" >"$PNM_TEST_CURL_RECEIPT"
exit "$PNM_TEST_CURL_RC"
BASH
    chmod 0700 -- "$fakebin/curl"
    digest="$(printf '%064d' 0)"
    if PNM_TEST_CURL_RC="$curl_rc" PNM_TEST_CURL_RECEIPT="$temp_dir/attempt" PATH="$fakebin:$PATH" \
        pnm_asset_download_verified xray v1.2.3 "$digest" "$destination"; then rc=0; else rc=$?; fi
    assert_eq "$curl_rc" "$(<"$temp_dir/attempt")" || return 1
    assert_eq "$expected_rc" "$rc" || return 1
    assert_eq 'preserve unrelated file' "$(<"$temp_dir/sentinel")" || return 1
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
    ! compgen -G "$temp_dir/.pnm-asset.*" >/dev/null
)

test_failed_download_removes_partial_candidate() {
    asset_failure_preserves_publication_boundary 22 69
}

test_checksum_refusal_removes_unverified_candidate() {
    asset_failure_preserves_publication_boundary 0 78
}

asset_publication_failure_is_private_and_nonclobbering() (
    local behavior="$1" expected_rc="$2" temp_dir destination digest core
    temp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temp_dir"' EXIT
    mkdir -m 0700 "$temp_dir/bin" || return 1
    cat >"$temp_dir/bin/curl" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
target=''
while (($# > 0)); do
    if [[ "$1" == --output ]]; then target="$2"; shift 2; else shift; fi
done
printf 'called\n' >"$PNM_TEST_ASSET_RECEIPT"
printf 'verified payload' >"$target"
case "$PNM_TEST_ASSET_BEHAVIOR" in
    raced-file) printf 'foreign payload' >"$PNM_TEST_ASSET_DESTINATION" ;;
    raced-directory) mkdir "$PNM_TEST_ASSET_DESTINATION"; printf 'foreign payload' >"$PNM_TEST_ASSET_DESTINATION/sentinel" ;;
    raced-link) ln -s "$PNM_TEST_ASSET_SENTINEL" "$PNM_TEST_ASSET_DESTINATION" ;;
esac
BASH
    chmod 0700 "$temp_dir/bin/curl" || return 1
    digest="$(printf 'verified payload' | sha256sum | awk '{print $1}')"
    if [[ "$behavior" == chmod-failure ]]; then chmod() { return 1; }; fi
    for core in xray hysteria2; do
        mkdir -m 0700 "$temp_dir/$core" || return 1
        destination="$temp_dir/$core/payload"
        printf 'foreign payload' >"$temp_dir/$core/sentinel"
        if [[ "$behavior" == existing-dangling-link ]]; then
            ln -s "$temp_dir/$core/missing" "$destination" || return 1
        fi
        PNM_TEST_ASSET_BEHAVIOR="$behavior" PNM_TEST_ASSET_DESTINATION="$destination" \
            PNM_TEST_ASSET_SENTINEL="$temp_dir/$core/sentinel" PNM_TEST_ASSET_RECEIPT="$temp_dir/$core/called" \
            PATH="$temp_dir/bin:$PATH" run_capture pnm_asset_download_verified "$core" v1.2.3 "$digest" "$destination"
        assert_eq "$expected_rc" "$RUN_RC" || return 1
        assert_eq 'foreign payload' "$(<"$temp_dir/$core/sentinel")" || return 1
        case "$behavior" in
            existing-dangling-link)
                [[ -L "$destination" && ! -e "$destination" && ! -e "$temp_dir/$core/called" ]] || return 1 ;;
            raced-file) assert_eq 'foreign payload' "$(<"$destination")" || return 1 ;;
            raced-directory) assert_eq 'foreign payload' "$(<"$destination/sentinel")" || return 1 ;;
            raced-link) assert_eq "$temp_dir/$core/sentinel" "$(readlink "$destination")" || return 1 ;;
            chmod-failure) [[ ! -e "$destination" && ! -L "$destination" ]] || return 1 ;;
        esac
        [[ -z "$(find "$temp_dir/$core" -name '.pnm-asset.*' -print -quit)" ]] || return 1
    done
)

test_existing_dangling_asset_link_refuses_before_download() { asset_publication_failure_is_private_and_nonclobbering existing-dangling-link 73; }
test_asset_publication_preserves_raced_file() { asset_publication_failure_is_private_and_nonclobbering raced-file 73; }
test_asset_publication_does_not_move_into_raced_directory() { asset_publication_failure_is_private_and_nonclobbering raced-directory 73; }
test_asset_publication_preserves_raced_link() { asset_publication_failure_is_private_and_nonclobbering raced-link 73; }
test_asset_permission_failure_refuses_publication() { asset_publication_failure_is_private_and_nonclobbering chmod-failure 77; }

run_test 'asset URLs are fixed by Core and version' test_asset_urls_are_pinned_by_core_and_version
run_test 'asset SHA-256 verification fails closed' test_asset_hash_verification
run_test 'asset verification accepts literal backslashes in Linux paths' test_asset_hash_accepts_backslash_in_source_path
run_test 'failed hash queries refuse matching output without depending on pipefail' test_asset_hash_query_failure_refuses_even_with_matching_output
run_test 'approved asset loading retains both Core pins without output' test_assets_loads_approved_manifest_without_output
run_test 'verified download atomically installs the payload' test_verified_download_atomically_installs_payload
run_test 'failed download removes its partial candidate without publication' test_failed_download_removes_partial_candidate
run_test 'checksum refusal removes its unverified candidate without publication' test_checksum_refusal_removes_unverified_candidate
run_test 'dangling destination links refuse before downloading either Core asset' test_existing_dangling_asset_link_refuses_before_download
run_test 'publication refuses raced files without replacing them or retaining candidates' test_asset_publication_preserves_raced_file
run_test 'publication cannot move a Core candidate into a raced directory' test_asset_publication_does_not_move_into_raced_directory
run_test 'publication preserves raced symlinks and their targets' test_asset_publication_preserves_raced_link
run_test 'candidate chmod failure refuses publication and removes the private candidate' test_asset_permission_failure_refuses_publication
finish_tests
