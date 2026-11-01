#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT"

required_files=(
    VERSION README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md .gitignore Makefile install.sh bin/pnm
    lib/core-ops.sh lib/transaction.sh lib/lifecycle.sh docs/RELEASING.md
    .github/workflows/ci.yml
)
for required in "${required_files[@]}"; do
    [[ -f "$required" ]] || { printf 'missing release file: %s\n' "$required" >&2; exit 1; }
done

version="$(<VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9._-]+)?$ ]] || { printf 'invalid release version\n' >&2; exit 1; }
rg -Fq "## $version " CHANGELOG.md || { printf 'version missing from changelog\n' >&2; exit 1; }

if rg -n 'curl[^\n]*\|[[:space:]]*(ba)?sh|iptables[[:space:]]+-F|ip6tables[[:space:]]+-F|ufw[[:space:]]+reset|set[[:space:]]+-x|\beval\b' install.sh bin lib adapters; then
    printf 'forbidden release pattern detected\n' >&2
    exit 1
fi
if rg -n 'releases/download/latest|/latest(["/]|$)' bin lib adapters; then
    printf 'unfixed latest asset reference detected\n' >&2
    exit 1
fi
if rg -n 'tailscale[[:space:]]+(up|down|set|ssh|install|uninstall)' bin lib adapters; then
    printf 'PNM runtime must not operate Tailscale\n' >&2
    exit 1
fi

./tests/security-scan.sh
printf 'release-scan-ok version=%s\n' "$version"
