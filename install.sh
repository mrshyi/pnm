#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly PNM_DEFAULT_REPOSITORY='https://github.com/mrshyi/pnm'
readonly PNM_DEFAULT_REF='main'
readonly PNM_DEFAULT_INSTALL_ROOT='/usr/local/lib/pnm'
readonly PNM_DEFAULT_INSTALL_BIN='/usr/local/bin/pnm'

PNM_REPOSITORY="${PNM_REPOSITORY:-$PNM_DEFAULT_REPOSITORY}"
PNM_REF="${PNM_REF:-$PNM_DEFAULT_REF}"
PNM_INSTALL_ROOT="${PNM_INSTALL_ROOT:-$PNM_DEFAULT_INSTALL_ROOT}"
PNM_INSTALL_BIN="${PNM_INSTALL_BIN:-$PNM_DEFAULT_INSTALL_BIN}"

PNM_SOURCE_ROOT=''
PNM_SOURCE_TEMP=''
PNM_STAGE_DIR=''
PNM_WRAPPER_STAGE=''
PNM_OLD_ROOT=''
PNM_OLD_BIN=''

pnm_install_error() {
    printf 'pnm-install: %s\n' "$*" >&2
    exit 1
}

pnm_install_usage() {
    cat <<'EOF'
Usage: install.sh

Install the PNM CLI and runtime files into /usr/local/lib/pnm and expose
/usr/local/bin/pnm. When run outside a PNM source checkout, the installer
downloads the archive selected by PNM_REF.

Environment:
  PNM_REF              GitHub branch, tag, or commit (default: main)
  PNM_REPOSITORY       HTTPS repository URL (default: https://github.com/mrshyi/pnm)
  PNM_INSTALL_ROOT     Runtime installation path (default: /usr/local/lib/pnm)
  PNM_INSTALL_BIN      CLI path (default: /usr/local/bin/pnm)
EOF
}

pnm_install_cleanup() {
    if [[ -n "$PNM_WRAPPER_STAGE" && -e "$PNM_WRAPPER_STAGE" ]]; then
        rm -f -- "$PNM_WRAPPER_STAGE"
    fi
    if [[ -n "$PNM_STAGE_DIR" && -d "$PNM_STAGE_DIR" ]]; then
        rm -rf -- "$PNM_STAGE_DIR"
    fi
    if [[ -n "$PNM_SOURCE_TEMP" && -d "$PNM_SOURCE_TEMP" ]]; then
        rm -rf -- "$PNM_SOURCE_TEMP"
    fi
}
trap pnm_install_cleanup EXIT

pnm_install_require_root() {
    ((EUID == 0)) || pnm_install_error 'run this installer as root (for example: sudo bash install.sh)'
}

pnm_install_require_command() {
    command -v -- "$1" >/dev/null 2>&1 || pnm_install_error "required command is missing: $1"
}

pnm_install_validate_path() {
    local path="$1"

    [[ "$path" == /* && "$path" != / ]] || pnm_install_error "installation path must be an absolute non-root path: $path"
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || pnm_install_error 'installation paths must not contain newlines'
}

pnm_install_validate_ref() {
    [[ "$PNM_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || pnm_install_error 'PNM_REF contains unsupported characters'
    [[ "$PNM_REF" != /* && "$PNM_REF" != *'..'* && "$PNM_REF" != *'//'* ]] || pnm_install_error 'PNM_REF must be a simple branch, tag, or commit reference'
}

pnm_install_source_valid() {
    local root="$1"

    [[ -f "$root/bin/pnm" && -d "$root/lib" && -d "$root/adapters" && -f "$root/VERSION" ]]
}

pnm_install_download_source() {
    local archive_url archive_file candidate
    local -a roots=()

    pnm_install_require_command curl
    pnm_install_require_command tar
    [[ "$PNM_REPOSITORY" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$ ]] || pnm_install_error 'PNM_REPOSITORY must be a GitHub HTTPS repository URL'
    pnm_install_validate_ref

    PNM_SOURCE_TEMP="$(mktemp -d /tmp/pnm-install.XXXXXXXX)" || pnm_install_error 'cannot create a temporary directory'
    archive_file="$PNM_SOURCE_TEMP/source.tar.gz"
    archive_url="${PNM_REPOSITORY%/}/archive/${PNM_REF}.tar.gz"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        "$archive_url" --output "$archive_file" || pnm_install_error "failed to download $archive_url"
    tar --extract --gzip --file "$archive_file" --directory "$PNM_SOURCE_TEMP" || pnm_install_error 'downloaded source archive is invalid'

    for candidate in "$PNM_SOURCE_TEMP"/*; do
        [[ -d "$candidate" ]] && roots+=("$candidate")
    done
    ((${#roots[@]} == 1)) || pnm_install_error 'source archive must contain exactly one top-level directory'
    PNM_SOURCE_ROOT="${roots[0]}"
    pnm_install_source_valid "$PNM_SOURCE_ROOT" || pnm_install_error 'source archive does not contain a valid PNM checkout'
}

pnm_install_prepare_source() {
    local script_root

    script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    if pnm_install_source_valid "$script_root"; then
        PNM_SOURCE_ROOT="$script_root"
    else
        pnm_install_download_source
    fi
}

pnm_install_prepare_stage() {
    local install_parent bin_parent

    install_parent="$(dirname -- "$PNM_INSTALL_ROOT")"
    bin_parent="$(dirname -- "$PNM_INSTALL_BIN")"
    install -d -m 0755 -- "$install_parent" "$bin_parent"
    PNM_STAGE_DIR="$(mktemp -d "$install_parent/.pnm-install.XXXXXXXX")" || pnm_install_error 'cannot create the installation staging directory'
    chmod 0755 -- "$PNM_STAGE_DIR"
    cp -a -- "$PNM_SOURCE_ROOT/bin" "$PNM_SOURCE_ROOT/lib" "$PNM_SOURCE_ROOT/adapters" "$PNM_STAGE_DIR/"
    install -m 0644 -- "$PNM_SOURCE_ROOT/VERSION" "$PNM_STAGE_DIR/VERSION"

    PNM_WRAPPER_STAGE="$(mktemp "$bin_parent/.pnm-wrapper.XXXXXXXX")" || pnm_install_error 'cannot create the CLI staging file'
    chmod 0755 -- "$PNM_WRAPPER_STAGE"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        "exec $(printf '%q' "$PNM_INSTALL_ROOT/bin/pnm") \"\$@\"" >"$PNM_WRAPPER_STAGE"
}

pnm_install_rollback() {
    if [[ -n "$PNM_OLD_BIN" && -e "$PNM_OLD_BIN" && ! -e "$PNM_INSTALL_BIN" && ! -L "$PNM_INSTALL_BIN" ]]; then
        mv -- "$PNM_OLD_BIN" "$PNM_INSTALL_BIN" || true
    fi
    if [[ -n "$PNM_OLD_ROOT" && -e "$PNM_OLD_ROOT" && ! -e "$PNM_INSTALL_ROOT" && ! -L "$PNM_INSTALL_ROOT" ]]; then
        mv -- "$PNM_OLD_ROOT" "$PNM_INSTALL_ROOT" || true
    fi
}

pnm_install_commit() {
    PNM_OLD_ROOT="${PNM_INSTALL_ROOT}.previous.$$"
    PNM_OLD_BIN="${PNM_INSTALL_BIN}.previous.$$"
    [[ ! -e "$PNM_OLD_ROOT" && ! -L "$PNM_OLD_ROOT" ]] || pnm_install_error "temporary backup already exists: $PNM_OLD_ROOT"
    [[ ! -e "$PNM_OLD_BIN" && ! -L "$PNM_OLD_BIN" ]] || pnm_install_error "temporary backup already exists: $PNM_OLD_BIN"

    if [[ -e "$PNM_INSTALL_ROOT" || -L "$PNM_INSTALL_ROOT" ]]; then
        mv -- "$PNM_INSTALL_ROOT" "$PNM_OLD_ROOT" || pnm_install_error 'cannot move the existing PNM installation'
    else
        PNM_OLD_ROOT=''
    fi
    if [[ -e "$PNM_INSTALL_BIN" || -L "$PNM_INSTALL_BIN" ]]; then
        mv -- "$PNM_INSTALL_BIN" "$PNM_OLD_BIN" || { pnm_install_rollback; pnm_install_error 'cannot move the existing PNM CLI'; }
    else
        PNM_OLD_BIN=''
    fi

    if ! mv -- "$PNM_STAGE_DIR" "$PNM_INSTALL_ROOT"; then
        pnm_install_rollback
        pnm_install_error 'cannot activate the new PNM installation'
    fi
    PNM_STAGE_DIR=''
    if ! mv -- "$PNM_WRAPPER_STAGE" "$PNM_INSTALL_BIN"; then
        rm -rf -- "$PNM_INSTALL_ROOT"
        pnm_install_rollback
        pnm_install_error 'cannot activate the PNM CLI'
    fi
    PNM_WRAPPER_STAGE=''

    [[ -n "$PNM_OLD_ROOT" ]] && rm -rf -- "$PNM_OLD_ROOT"
    [[ -n "$PNM_OLD_BIN" ]] && rm -f -- "$PNM_OLD_BIN"
    PNM_OLD_ROOT=''
    PNM_OLD_BIN=''
}

main() {
    [[ "${1-}" != '--help' && "${1-}" != '-h' ]] || { pnm_install_usage; return 0; }
    (($# == 0)) || pnm_install_error 'unexpected arguments; use --help for usage'
    pnm_install_require_root
    pnm_install_validate_path "$PNM_INSTALL_ROOT"
    pnm_install_validate_path "$PNM_INSTALL_BIN"
    [[ "$PNM_INSTALL_ROOT" != "$PNM_INSTALL_BIN" ]] || pnm_install_error 'PNM_INSTALL_ROOT and PNM_INSTALL_BIN must be different paths'
    pnm_install_prepare_source
    pnm_install_prepare_stage
    pnm_install_commit
    printf 'Installed PNM %s\n' "$(<"$PNM_INSTALL_ROOT/VERSION")"
    printf 'CLI: %s\n' "$PNM_INSTALL_BIN"
    printf 'Next: sudo pnm install --apply --yes\n'
}

main "$@"
