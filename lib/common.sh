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

pnm_mkdir_mode() {
    local mode directory

    mode="${1:?directory mode required}"
    directory="${2:?directory required}"
    mkdir -p -- "$directory" && chmod "$mode" -- "$directory"
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
    trap 'pnm_cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

pnm_cleanup() {
    local path

    for path in "${PNM_CLEANUP_PATHS[@]:-}"; do
        [[ -n "$path" ]] || continue
        case "$path" in
            /tmp/pnm.* | /run/pnm/*)
                [[ -e "$path" ]] && rm -rf -- "$path"
                ;;
            *)
                # Cleanup is intentionally fail-closed for unregistered roots.
                ;;
        esac
    done
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
    local temp_root="${TMPDIR:-/tmp}"
    local temp_dir

    temp_dir="$(mktemp -d -- "$temp_root/pnm.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    chmod 0700 -- "$temp_dir"
    pnm_register_cleanup_path "$temp_dir"
    printf '%s\n' "$temp_dir"
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
