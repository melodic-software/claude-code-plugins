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

Reports available only when an enabled install matches marketplace id
caveman@caveman (or, if that exact id is absent, any other enabled
caveman@* marketplace match — reported as available with that id for
operator visibility; SKILL.md pins marketplace `caveman`).
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

# Prefer the pinned marketplace identity; require enabled=true across scopes.
# Disabled installs must not report available (skills of disabled plugins are
# not loaded). Empirically `claude plugin list --json` carries id + enabled.
json="$(claude plugin list --json 2>/dev/null || true)"
plugin_id="$(
  printf '%s' "$json" | jq -r '
    [.[] | select(.enabled == true) | select(.id | startswith("caveman@"))]
    | (map(select(.id == "caveman@caveman")) + .)
    | .[0].id // empty
  ' 2>/dev/null | head -1 | tr -d '\r'
)"

if [[ -n "$plugin_id" ]]; then
  printf 'Caveman backend: available\n'
  printf 'Caveman plugin id: %s\n' "$plugin_id"
else
  printf 'Caveman backend: absent\n'
  printf 'Caveman plugin id: none\n'
fi
