#!/usr/bin/env bash
# Detect caveman plugin availability for /compress backend selection.
#
# Output:
#   Caveman backend: available|absent|unknown
#   Caveman plugin id: <id|none>
#
# Exit: always 0.
# set -e omitted — script must never abort; always exits 0 per contract.
set -uo pipefail

usage() {
  cat <<'EOF'
detect-caveman.sh — caveman plugin availability facts for /compress.

Usage:
  detect-caveman.sh [--help]

Exit: always 0.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

if ! command -v claude >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'Caveman backend: unknown\n'
  printf 'Caveman plugin id: none\n'
  exit 0
fi

plugin_id="$(claude plugin list --json 2>/dev/null | jq -r '.[] | select(.id | startswith("caveman@")) | .id' 2>/dev/null | head -1 | tr -d '\r')"

if [[ -n "$plugin_id" ]]; then
  printf 'Caveman backend: available\n'
  printf 'Caveman plugin id: %s\n' "$plugin_id"
else
  printf 'Caveman backend: absent\n'
  printf 'Caveman plugin id: none\n'
fi
