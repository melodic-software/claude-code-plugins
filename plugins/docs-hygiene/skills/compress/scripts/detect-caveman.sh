#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
detect-caveman.sh — caveman plugin availability facts for /compress.

Usage:
  detect-caveman.sh [--help]

Exit: always 0.

Reports available only when an enabled install matches marketplace id
caveman@caveman (or, if that exact id is absent, any other enabled
caveman@* marketplace match — reported as available with that id for
operator visibility; SKILL.md pins marketplace `caveman`).
EOF
}

emit() {
  printf 'Caveman backend: %s\nCaveman plugin id: %s\n' "$1" "$2"
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

if ! command -v claude >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  emit unknown none
  exit 0
fi

plugin_id="$(
  claude plugin list --json 2>/dev/null | jq -r '
    [.[] | select(.enabled == true) | select(.id | startswith("caveman@"))]
    | (map(select(.id == "caveman@caveman")) + .)
    | .[0].id // empty
  ' 2>/dev/null | tr -d '\r' | head -1
)"

if [[ -n "$plugin_id" ]]; then
  emit available "$plugin_id"
else
  emit absent none
fi
