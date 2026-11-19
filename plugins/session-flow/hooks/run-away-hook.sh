#!/usr/bin/env bash
set -uo pipefail

EVENT="${1:-}"
[[ -n "$EVENT" ]] || exit 0
DATA="${CLAUDE_PLUGIN_DATA:-}"
case "${DATA##*/}" in
  session-flow | session-flow-*) [[ -d "$DATA/away" ]] || exit 0 ;;
  *) ;;
esac

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 0

# shellcheck source=../lib/python-probe.sh
source "$PLUGIN_ROOT/lib/python-probe.sh" 2>/dev/null || exit 0
PY=""
python_probe::floor_interpreter_to PY
[[ -n "$PY" ]] || exit 0

AWAY="$PLUGIN_ROOT/scripts/away.py"
[[ -f "$AWAY" ]] || exit 0

"$PY" -I "$AWAY" hook "$EVENT" || true
exit 0
