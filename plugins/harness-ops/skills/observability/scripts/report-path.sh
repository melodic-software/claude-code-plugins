#!/usr/bin/env bash
# Exit: 0 on a derivation; 2 on a bad argument or an underivable state key.

set -uo pipefail

usage() {
  cat <<'EOF'
report-path.sh: resolve the keyed `--write` report path for /harness-ops:observability.

Prints ${CLAUDE_PLUGIN_DATA}/reports/<state-key>/claude-observability-<date>.md

Usage:
  report-path.sh [--root <path>] [--date YYYY-MM-DD] [--mkdir] [--explain] [--help]

  --root <path>  derive the key for that directory instead of the current one
  --date <date>  use that date instead of today
  --mkdir        create the parent directory before printing
  --explain      write the state-key rung and its inputs to stderr

Exit: 0 on a derivation; 2 on a bad argument or an underivable state key.
EOF
}

ROOT_ARG=""
DATE_ARG=""
DO_MKDIR=0
EXPLAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a path" >&2
      exit 2
    fi
    ROOT_ARG="$2"
    shift 2
    ;;
  --date)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --date needs a YYYY-MM-DD value" >&2
      exit 2
    fi
    DATE_ARG="$2"
    shift 2
    ;;
  --mkdir)
    DO_MKDIR=1
    shift
    ;;
  --explain)
    EXPLAIN=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

REPORT_DATE="${DATE_ARG:-$(date +%Y-%m-%d)}"
if [[ ! "$REPORT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: --date must be YYYY-MM-DD: $REPORT_DATE" >&2
  exit 2
fi

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE_KEY_SH="$PLUGIN_ROOT/lib/state-key.sh"

key_args=()
[[ -n "$ROOT_ARG" ]] && key_args+=(--root "$ROOT_ARG")
[[ $EXPLAIN -eq 1 ]] && key_args+=(--explain)

STATE_KEY="$(bash "$STATE_KEY_SH" "${key_args[@]+"${key_args[@]}"}")"
if [[ -z "$STATE_KEY" ]]; then
  echo "ERROR: could not derive a state key ($STATE_KEY_SH)" >&2
  exit 2
fi

seg="${CLAUDE_PLUGIN_DATA:-}"
seg="${seg%[/\\]}"
seg="${seg##*[/\\]}"
if [[ "$seg" == harness-ops || "$seg" == harness-ops-* ]]; then
  DATA_DIR="$CLAUDE_PLUGIN_DATA"
else
  DATA_DIR="$HOME/.claude/plugins/data/harness-ops"
fi
COMPONENT_DIR="$DATA_DIR/reports"
REPORT_DIR="$COMPONENT_DIR/$STATE_KEY"

for legacy in "$COMPONENT_DIR"/claude-observability-*.md; do
  [[ -f "$legacy" ]] || continue
  echo "NOTE: unkeyed leftover from an older layout, not read: $legacy" >&2
done

if [[ $DO_MKDIR -eq 1 ]]; then
  mkdir -p "$REPORT_DIR" || exit 2
fi

printf '%s/claude-observability-%s.md\n' "$REPORT_DIR" "$REPORT_DATE"
