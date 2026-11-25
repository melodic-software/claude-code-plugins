#!/usr/bin/env bash
# SessionStart arming hook for the running-retro detached observer.
#
# OPT-IN and zero-config-safe: it no-ops unless CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED
# is "true", so installing session-flow does not change any consumer's behavior.
# When enabled it fire-and-forgets the detached tailer for the CURRENT session,
# which then outlives the session and (if analysis is on) runs the post-end
# running-retro checkpoint. We treat SessionStart as unable to block, so the
# launch is safe by construction. Always exits 0. Event semantics and the stdin
# `source` and `agent_type` fields: https://code.claude.com/docs/en/hooks#sessionstart
# and #sessionstart-input.
#
# Self-arm guard (never observe the observer's own analysis run, subagents, or
# forked/background helpers):
#   - CLAUDE_CODE_ENTRYPOINT must be "cli" (a real interactive session; the
#     headless `-p` analysis run reports "sdk-cli");
#   - SESSION_FLOW_OBSERVER_ANALYSIS must be unset (set by the analysis run);
#   - stdin `agent_type` must be absent (present inside a subagent / --agent run);
#   - stdin `source` must be startup or resume (skip clear / compact / fork).
#
# Config (consumer settings `env`, via userConfig; all optional):
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED           master opt-in (default false)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED  post-end analysis (default true)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_MODEL    analysis model (unset: plugin.json userConfig default)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_EFFORT   analysis effort (unset: plugin.json userConfig default)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_BARE     pass --bare (default false; see reference/observer.md)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_MIN_LINES         skip analysis below this many lines (unset: plugin.json userConfig default)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_IDLE_SECONDS      mtime-idle end threshold (default 900)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_POLL_SECONDS      poll interval (default 5)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_MAX_SECONDS       hard lifetime safety valve (default 86400)

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED:-false}" == "true" ]] || exit 0
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

LEDGER_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.work/running-retros"

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
  --idle-seconds "${CLAUDE_PLUGIN_OPTION_OBSERVER_IDLE_SECONDS:-900}"
  --poll-seconds "${CLAUDE_PLUGIN_OPTION_OBSERVER_POLL_SECONDS:-5}"
  --max-seconds "${CLAUDE_PLUGIN_OPTION_OBSERVER_MAX_SECONDS:-86400}")
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED:-true}" == "true" ]] && args+=(--analysis)
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_BARE:-false}" == "true" ]] && args+=(--bare)

"$PY" "$ARM" "${args[@]}" >/dev/null 2>&1 || true
exit 0
