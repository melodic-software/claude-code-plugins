#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED:-}" != false ]] || exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOKS_DIR" != "${BASH_SOURCE[0]}" ]] || HOOKS_DIR=.
PLUGIN_ROOT="$HOOKS_DIR/.."

# shellcheck source=../lib/python-probe.sh
source "$PLUGIN_ROOT/lib/python-probe.sh" 2>/dev/null || exit 0
PY=""
python_probe::floor_interpreter_to PY
[[ -n "$PY" ]] || exit 0

HOOK="$PLUGIN_ROOT/scripts/resume_hook.py"
[[ -f "$HOOK" ]] || exit 0

"$PY" -I "$HOOK" hook UserPromptSubmit || true
exit 0
