#!/usr/bin/env bash
set -uo pipefail

EVENT="${1:-}"
[[ -n "$EVENT" ]] || exit 0
shift

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --plugin-root)
    [[ -n "${2:-}" ]] && PLUGIN_ROOT="$2"
    shift 2 || break
    ;;
  *) shift ;;
  esac
done

# shellcheck source=../lib/python-probe.sh
source "$PLUGIN_ROOT/lib/python-probe.sh" 2>/dev/null || exit 0
PY=""
python_probe::floor_interpreter_to PY
[[ -n "$PY" ]] || exit 0

AWAY="$PLUGIN_ROOT/scripts/away.py"
[[ -f "$AWAY" ]] || exit 0

"$PY" -I "$AWAY" hook "$EVENT" --plugin-root "$PLUGIN_ROOT" || true
exit 0
