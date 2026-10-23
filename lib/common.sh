#!/usr/bin/env bash

readonly PNM_EXIT_OK=0
readonly PNM_EXIT_WARN=1
readonly PNM_EXIT_FAIL=2
readonly PNM_EXIT_USAGE=64
readonly PNM_EXIT_UNAVAILABLE=69
readonly PNM_EXIT_SOFTWARE=70
readonly PNM_EXIT_CANTCREAT=73
readonly PNM_EXIT_NOPERM=77
readonly PNM_EXIT_CONFIG=78

# Validate every existing component before mkdir/chmod or a managed file write.
# This assumes protected parent directories; it is not an openat-based race lock.
pnm_validate_managed_path() {
    local path="${1:?absolute managed path required}" component current=''
    local -a components=()

    [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || return "$PNM_EXIT_CONFIG"
    IFS='/' read -r -a components <<<"$path"
    for component in "${components[@]}"; do
        [[ "$component" != '..' ]] || return "$PNM_EXIT_CONFIG"
        [[ -n "$component" && "$component" != '.' ]] || continue
        current+="/$component"
        [[ ! -L "$current" ]] || return "$PNM_EXIT_CONFIG"
    done
}

pnm_mkdir_mode() {
    local mode directory

    mode="${1:?directory mode required}"
    directory="${2:?directory required}"
    # Compare directory identity so aliases such as // and /tmp/.. are covered.
    [[ ! "$directory" -ef / ]] || return "$PNM_EXIT_CONFIG"
    pnm_validate_managed_path "$directory" || return $?
    mkdir -p -- "$directory" || return "$PNM_EXIT_CANTCREAT"
    chmod "$mode" -- "$directory"
}

PNM_CONFIG_DIR="${PNM_CONFIG_DIR:-/etc/pnm}"
PNM_STATE_DIR="${PNM_STATE_DIR:-/var/lib/pnm}"
PNM_LOCK_FILE="${PNM_LOCK_FILE:-/run/lock/pnm.lock}"
PNM_OS_RELEASE_FILE="${PNM_OS_RELEASE_FILE:-/etc/os-release}"
PNM_XRAY_CONFIG="${PNM_XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
PNM_HY2_CONFIG="${PNM_HY2_CONFIG:-/etc/hysteria/config.yaml}"
PNM_XRAY_BIN="${PNM_XRAY_BIN:-/usr/local/bin/xray}"
PNM_HY2_BIN="${PNM_HY2_BIN:-/usr/local/bin/hysteria}"

PNM_OUTPUT_MODE="text"
PNM_COLOR_MODE="auto"
PNM_QUIET=0
PNM_DEBUG=0
PNM_DRY_RUN=0
PNM_ASSUME_YES=0

declare -ag PNM_CLEANUP_PATHS=()

pnm_init_runtime() {
    umask 077
    trap 'pnm_runtime_exit $?' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

pnm_runtime_exit() {
    local rc="${1:-0}"
    trap - EXIT
    if (( ${PNM_APPLY_GATE_ACTIVE:-0} == 1 && ${PNM_TX_ACTIVE:-0} == 1 )) &&
        [[ "${PNM_TX_OPERATION:-}" == deployment ]] && declare -F pnm_apply_gate_fail >/dev/null 2>&1; then
        if (( ${PNM_TX_COMMITTED:-0} == 1 )); then
            PNM_DEPLOY_COMMITTED=1 PNM_APPLY_GATE_COMMITTED=1
            pnm_tx_close || true
            pnm_deploy_close || true
            pnm_apply_gate_close || true
            pnm_warn 'Deployment was already committed before process cleanup.'
            rc=0
        else
            ((rc != 0)) || rc="$PNM_EXIT_SOFTWARE"
            if pnm_apply_gate_fail "$rc"; then :; else rc=$?; fi
        fi
    elif (( ${PNM_TX_ACTIVE:-0} == 1 )) && [[ "${PNM_TX_OPERATION:-}" != deployment ]] &&
        declare -F pnm_tx_recover_on_exit >/dev/null 2>&1; then
        # Finish one recovery attempt before accepting another catchable signal.
        trap '' INT TERM
        if pnm_tx_recover_on_exit "$rc"; then :; else rc=$?; fi
    fi
    pnm_cleanup || pnm_warn 'Temporary cleanup failed; private staging files may remain.' >&2
    exit "$rc"
}

pnm_with_deployment_read_lock() {
    local function_name="${1:?read operation required}" rc=0
    shift
    pnm_lock_acquire shared || return $?
    if pnm_tx_assert_no_pending_deployment; then
        if "$function_name" "$@"; then :; else rc=$?; fi
    else
        rc=$?
    fi
    pnm_lock_release || rc="$PNM_EXIT_SOFTWARE"
    return "$rc"
}

pnm_cleanup() {
    local path rc=0

    for path in "${PNM_CLEANUP_PATHS[@]:-}"; do
        [[ -n "$path" ]] || continue
        case "$path" in
            /tmp/pnm.* | /run/pnm/*)
                if [[ -e "$path" || -L "$path" ]]; then
                    rm -rf -- "$path" || rc="$PNM_EXIT_SOFTWARE"
                fi
                ;;
            *)
                # Cleanup is intentionally fail-closed for unregistered roots.
                ;;
        esac
    done
    return "$rc"
}

pnm_register_cleanup_path() {
    local path="${1:?cleanup path required}"

    case "$path" in
        /tmp/pnm.* | /run/pnm/*)
            PNM_CLEANUP_PATHS+=("$path")
            ;;
        *)
            return "$PNM_EXIT_NOPERM"
            ;;
    esac
}

pnm_make_temp_dir() {
    local pnm_temp_root="${TMPDIR:-/tmp}" pnm_temp_output="${1-}" pnm_temp_directory pnm_temp_rc
    # Internal callers pass a scalar output name so registration happens in
    # their shell, not in a command substitution that loses cleanup state.
    [[ -z "$pnm_temp_output" || ( "$pnm_temp_output" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$pnm_temp_output" != pnm_temp_* ) ]] || return "$PNM_EXIT_CONFIG"
    pnm_validate_managed_path "$pnm_temp_root" || return $?
    pnm_temp_directory="$(mktemp -d -- "$pnm_temp_root/pnm.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    if chmod 0700 -- "$pnm_temp_directory"; then :; else
        rmdir -- "$pnm_temp_directory" || true
        return "$PNM_EXIT_NOPERM"
    fi
    if pnm_register_cleanup_path "$pnm_temp_directory"; then :; else
        pnm_temp_rc=$?
        rmdir -- "$pnm_temp_directory" || true
        return "$pnm_temp_rc"
    fi
    if [[ -n "$pnm_temp_output" ]]; then
        printf -v "$pnm_temp_output" '%s' "$pnm_temp_directory" || {
            rmdir -- "$pnm_temp_directory" || true
            return "$PNM_EXIT_CONFIG"
        }
    else
        printf '%s\n' "$pnm_temp_directory" || {
            pnm_temp_rc=$?
            rmdir -- "$pnm_temp_directory" || true
            return "$pnm_temp_rc"
        }
    fi
}

pnm_command_exists() {
    command -v -- "$1" >/dev/null 2>&1
}

pnm_require_root() {
    if ((EUID != 0)); then
        pnm_error "This command requires root privileges."
        return "$PNM_EXIT_NOPERM"
    fi
}

pnm_is_tty() {
    [[ -t 0 && -t 1 ]]
}

pnm_now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

pnm_one_line() {
    local value="${1-}"

    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\t'/ }"
    printf '%s' "$value"
}

pnm_read_version() {
    local version

    if [[ ! -r "$PNM_VERSION_FILE" ]]; then
        printf 'unknown\n'
        return 0
    fi

    IFS= read -r version <"$PNM_VERSION_FILE" || true
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9._-]+)?$ ]]; then
        printf '%s\n' "$version"
    else
        printf 'unknown\n'
    fi
}

pnm_is_configured() {
    [[ -f "$PNM_CONFIG_DIR/node.conf" ]]
}

pnm_capture() {
    local __target="${1:?target variable required}"
    shift
    local output rc

    if output="$({ "$@"; } 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    printf -v "$__target" '%s' "$output"
    return "$rc"
}

pnm_main() {
    local -a args=("$@")
    local command_name=""

    while ((${#args[@]} > 0)); do
        case "${args[0]}" in
            --json)
                PNM_OUTPUT_MODE="json"
                args=("${args[@]:1}")
                ;;
            --no-color)
                PNM_COLOR_MODE="never"
                args=("${args[@]:1}")
                ;;
            --quiet)
                PNM_QUIET=1
                args=("${args[@]:1}")
                ;;
            --debug)
                PNM_DEBUG=1
                args=("${args[@]:1}")
                ;;
            --dry-run)
                PNM_DRY_RUN=1
                args=("${args[@]:1}")
                ;;
            --yes)
                PNM_ASSUME_YES=1
                args=("${args[@]:1}")
                ;;
            -h | --help)
                pnm_print_help
                return "$PNM_EXIT_OK"
                ;;
            -V | --version)
                pnm_print_version
                return "$PNM_EXIT_OK"
                ;;
            --)
                args=("${args[@]:1}")
                break
                ;;
            -*)
                pnm_error "Unknown global option: ${args[0]}"
                return "$PNM_EXIT_USAGE"
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ "$PNM_OUTPUT_MODE" == "json" && "$PNM_QUIET" -eq 1 ]]; then
        pnm_error "--json and --quiet are mutually exclusive."
        return "$PNM_EXIT_USAGE"
    fi

    if ((${#args[@]} == 0)); then
        if pnm_is_tty; then
            pnm_menu
            return $?
        fi
        pnm_print_help
        return "$PNM_EXIT_USAGE"
    fi

    command_name="${args[0]}"
    args=("${args[@]:1}")

    case "$command_name" in
        help)
            if ((${#args[@]} > 1)); then
                pnm_error "Usage: pnm help [command]"
                return "$PNM_EXIT_USAGE"
            fi
            pnm_print_help "${args[0]-}"
            ;;
        version)
            ((${#args[@]} == 0)) || {
                pnm_error "Usage: pnm version"
                return "$PNM_EXIT_USAGE"
            }
            pnm_print_version
            ;;
        status)
            ((${#args[@]} == 0)) || {
                pnm_error "Usage: pnm [--json] status"
                return "$PNM_EXIT_USAGE"
            }
            pnm_status
            ;;
        check)
            ((${#args[@]} == 0)) || {
                pnm_error "Usage: pnm [--json|--quiet] check"
                return "$PNM_EXIT_USAGE"
            }
            pnm_check
            ;;
        node)
            pnm_node_command "${args[@]}"
            ;;
        install)
            pnm_install "${args[@]}"
            ;;
        restart | log | apply | update | rollback | backup | restore | uninstall)
            pnm_core_command "$command_name" "${args[@]}"
            ;;
        *)
            pnm_error "Unknown command: $command_name"
            return "$PNM_EXIT_USAGE"
            ;;
    esac
}
