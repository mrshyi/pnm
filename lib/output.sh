#!/usr/bin/env bash

PNM_COLOR_RED=''
PNM_COLOR_YELLOW=''
PNM_COLOR_GREEN=''
PNM_COLOR_BLUE=''
PNM_COLOR_RESET=''

pnm_init_colors() {
    if [[ "$PNM_COLOR_MODE" == "never" || "$PNM_OUTPUT_MODE" == "json" || ! -t 1 ]]; then
        return 0
    fi

    PNM_COLOR_RED=$'\033[31m'
    PNM_COLOR_YELLOW=$'\033[33m'
    PNM_COLOR_GREEN=$'\033[32m'
    PNM_COLOR_BLUE=$'\033[34m'
    PNM_COLOR_RESET=$'\033[0m'
}

pnm_info() {
    ((PNM_QUIET == 1)) && return 0
    printf '%s[INFO]%s %s\n' "$PNM_COLOR_BLUE" "$PNM_COLOR_RESET" "$(pnm_one_line "$*")"
}

pnm_warn() {
    ((PNM_QUIET == 1)) && return 0
    printf '%s[WARN]%s %s\n' "$PNM_COLOR_YELLOW" "$PNM_COLOR_RESET" "$(pnm_one_line "$*")"
}

pnm_success() {
    ((PNM_QUIET == 1)) && return 0
    printf '%s[OK]%s %s\n' "$PNM_COLOR_GREEN" "$PNM_COLOR_RESET" "$(pnm_one_line "$*")"
}

pnm_error() {
    printf '%s[ERROR]%s %s\n' "$PNM_COLOR_RED" "$PNM_COLOR_RESET" "$(pnm_one_line "$*")" >&2
}

pnm_debug() {
    ((PNM_DEBUG == 1)) || return 0
    printf '[DEBUG] %s\n' "$(pnm_one_line "$*")" >&2
}

pnm_json_escape() {
    local value="${1-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

pnm_json_string() {
    printf '"%s"' "$(pnm_json_escape "${1-}")"
}

pnm_print_version() {
    printf 'pnm %s\n' "$(pnm_read_version)"
}

pnm_print_help() {
    local command_name="${1-}"

    case "$command_name" in
        status)
            printf '%s\n' 'Usage: pnm [--json] status' '' 'Display read-only service, version, and listener status.'
            return 0
            ;;
        check)
            printf '%s\n' 'Usage: pnm [--json|--quiet] check' '' 'Run read-only policy and health checks. Exit: 0 PASS, 1 WARN, 2 FAIL.'
            return 0
            ;;
        install)
            printf '%s\n' 'Usage: pnm install [--dry-run]' '       pnm install --apply --yes' '' 'Install the approved Xray and Hysteria2 cores using the configured node state.'
            return 0
            ;;
        restart | log | apply | update | rollback | backup | restore | uninstall)
            pnm_core_print_help "$command_name"
            return 0
            ;;
        help | version | '')
            ;;
        *)
            pnm_error "No help is available for unknown command: $command_name"
            return "$PNM_EXIT_USAGE"
            ;;
    esac

    cat <<'EOF'
Proxy Node Manager (PNM)

Usage:
  pnm [global-options] <command> [command-options]

Implemented:
  help [command]       Show help
  version              Show PNM version
  status               Show Xray and Hysteria2 status
  check                Run read-only health and policy checks
  install              Install both approved proxy cores
  restart <core>       Restart xray or hy2
  log <core>           Read or follow one Core's systemd journal
  apply <core>         Render, validate, and transactionally apply one Core config
  update <core>        Install that Core's approved pinned version
  rollback <core>      Restore its saved previous binary
  backup [archive]     Create a mode-0600 backup containing a manifest
  restore <archive>    Validate and transactionally restore both Cores
  uninstall <core>     Back up, stop, and remove one Core (--yes required)

Global options:
  --json               Emit one JSON document
  --quiet              Suppress normal check output; use exit code only
  --dry-run            Render a no-write installation plan
  --yes                Confirm install or uninstall
  --no-color           Disable ANSI colors
  --debug              Emit non-secret diagnostics to stderr
  -h, --help           Show help
  -V, --version        Show version

Core scope:
  One VPS, Xray VLESS + REALITY TCP/443, Official Hysteria2 QUIC UDP/8443.
EOF
}

pnm_core_print_help() {
    case "$1" in
        restart) printf '%s\n' 'Usage: pnm restart <xray|hy2>' ;;
        log) printf '%s\n' 'Usage: pnm log <xray|hy2> [--lines N] [--follow]' ;;
        apply) printf '%s\n' 'Usage: pnm apply <xray|hy2>' ;;
        update) printf '%s\n' 'Usage: pnm update <xray|hy2> [--version V]' 'Version must match the approved entry in /etc/pnm/versions.conf.' ;;
        rollback) printf '%s\n' 'Usage: pnm rollback <xray|hy2>' ;;
        backup) printf '%s\n' 'Usage: pnm backup [archive-path]' 'Backups contain Secrets and use mode 0600.' ;;
        restore) printf '%s\n' 'Usage: pnm restore <backup.tar.gz>' ;;
        uninstall) printf '%s\n' 'Usage: pnm uninstall <xray|hy2> --yes' 'A secret-bearing backup is created before removal.' ;;
    esac
}
