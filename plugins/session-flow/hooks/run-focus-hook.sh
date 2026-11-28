#!/usr/bin/env bash
set -uo pipefail

EVENT="${1:-}"
[[ -n "$EVENT" ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED:-}" != false ]] || exit 0
DATA="${CLAUDE_PLUGIN_DATA:-}"
if [[ "$EVENT" == PreCompact ]]; then
  case "${DATA##*/}" in
    session-flow | session-flow-*) [[ -d "$DATA/focus" ]] || exit 0 ;;
    *) ;;
  esac
fi

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOKS_DIR" != "${BASH_SOURCE[0]}" ]] || HOOKS_DIR=.
PLUGIN_ROOT="$HOOKS_DIR/.."

# shellcheck source=../lib/python-probe.sh
source "$PLUGIN_ROOT/lib/python-probe.sh" 2>/dev/null || exit 0
PY=""
python_probe::floor_interpreter_to PY
[[ -n "$PY" ]] || exit 0

FOCUS="$PLUGIN_ROOT/scripts/focus.py"
[[ -f "$FOCUS" ]] || exit 0

"$PY" -I "$FOCUS" hook "$EVENT" || true
exit 0
