#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT"

fail=0

if rg -n '\beval\b|set[[:space:]]+-x|iptables[[:space:]]+-F|ip6tables[[:space:]]+-F|ufw[[:space:]]+reset' install.sh bin lib adapters; then
    printf 'Forbidden shell pattern detected.\n' >&2
    fail=1
fi

if rg -n 'source[[:space:]]+.*(/etc/pnm|node\.conf|versions\.conf|secrets)' install.sh bin lib adapters; then
    printf 'Data configuration must not be sourced.\n' >&2
    fail=1
fi

if rg -n 'curl[^\n]*\|[[:space:]]*(ba)?sh' install.sh bin lib adapters; then
    printf 'Unverified curl-to-shell pattern detected.\n' >&2
    fail=1
fi

exit "$fail"
