#!/usr/bin/env bash
# Exit codes:
#   0  a line was emitted (either state)
#   3  invalid argument

set -uo pipefail

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
probe-lane-config.sh: report where the lane config resolves to and whether it exists.

Usage:
  probe-lane-config.sh

Prints one line: `<path> (<N> lanes)`, `<path> ( lanes)` when the count is unavailable,
or `absent (<path>)`. HARNESS_OPS_LANES_CONFIG overrides the path.

Exit codes:
  0  a line was emitted (either state)
  3  invalid argument
EOF
}

if (($#)); then
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1 (see --help)"
    exit 3
    ;;
  esac
fi

if [[ -n "${HARNESS_OPS_LANES_CONFIG:-}" ]]; then
  CONFIG="$HARNESS_OPS_LANES_CONFIG"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  ROOT="${ROOT:-$PWD}"
  CONFIG="$ROOT/.work/lanes/lanes.json"
  [[ ! -f "$CONFIG" && -f "$ROOT/.work/lanes.json" ]] && CONFIG="$ROOT/.work/lanes.json"
fi

if [[ -f "$CONFIG" ]]; then
  printf '%s (%s lanes)\n' "$CONFIG" "$(jq -r '(.lanes//[])|length' "$CONFIG" 2>/dev/null | tr -d '\r')"
else
  printf 'absent (%s) — author one (see context/config.md)\n' "$CONFIG"
fi
