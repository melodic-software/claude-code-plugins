#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED:-false}" == "true" ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED:-true}" == "true" ]] || exit 0
[[ "${CLAUDE_CODE_ENTRYPOINT:-}" == "cli" ]] || exit 0
[[ -z "${SESSION_FLOW_OBSERVER_ANALYSIS:-}" ]] || exit 0

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

input_field() { printf '%s' "$INPUT" | jq -r ".$1 // \"\"" 2>/dev/null; }

case "$(input_field source)" in
startup | resume) ;;
*) exit 0 ;;
esac
[[ -z "$(input_field agent_type)" ]] || exit 0

TRANSCRIPT="$(input_field transcript_path)"
SESSION_ID="$(input_field session_id)"
[[ -n "$TRANSCRIPT" && -n "$SESSION_ID" ]] || exit 0

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
COMMON="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
[[ "$COMMON" == */.git ]] && PROJECT="${COMMON%/.git}"
LEDGER_DIR="$PROJECT/.work/running-retros"

WORK_DIR="${CLAUDE_PLUGIN_DATA:-${TEMP:-${TMPDIR:-/tmp}}}/session-flow-observer"

# shellcheck source=../lib/python-probe.sh
source "$PLUGIN_ROOT/lib/python-probe.sh"

PY=""
python_probe::floor_interpreter_to PY
[[ -n "$PY" ]] || exit 0

ARM="$PLUGIN_ROOT/skills/running-retro/scripts/arm_observer.py"
[[ -f "$ARM" ]] || exit 0

args=(--transcript "$TRANSCRIPT" --work-dir "$WORK_DIR" --ledger-dir "$LEDGER_DIR"
  --session-id "$SESSION_ID" --plugin-root "$PLUGIN_ROOT"
  --model "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_MODEL:-}"
  --effort "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_EFFORT:-}"
  --min-lines "${CLAUDE_PLUGIN_OPTION_OBSERVER_MIN_LINES:-}"
  --idle-seconds "${CLAUDE_PLUGIN_OPTION_OBSERVER_IDLE_SECONDS:-900}" --analysis)
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_BARE:-false}" == "true" ]] && args+=(--bare)

"$PY" "$ARM" "${args[@]}" >/dev/null 2>&1 || true
exit 0
