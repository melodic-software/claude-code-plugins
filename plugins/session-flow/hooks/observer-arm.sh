#!/usr/bin/env bash
# SessionStart arming hook for the running-retro detached observer.
#
# OPT-IN and zero-config-safe: it no-ops unless CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED
# is "true", so installing session-flow does not change any consumer's behavior.
# When enabled it fire-and-forgets the detached tailer for the CURRENT session,
# which then outlives the session and (if analysis is on) runs the post-end
# running-retro checkpoint. SessionStart is context-only and cannot block, so the
# launch is safe by construction. Always exits 0.
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
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_MODEL    analysis model (default claude-haiku-4-5)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_BARE     pass --bare (default false; see reference/observer.md)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_IDLE_SECONDS      mtime-idle end threshold (default 900)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_POLL_SECONDS      poll interval (default 5)
#   CLAUDE_PLUGIN_OPTION_OBSERVER_MAX_SECONDS       hard lifetime safety valve (default 86400)

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED:-false}" == "true" ]] || exit 0
[[ "${CLAUDE_CODE_ENTRYPOINT:-}" == "cli" ]] || exit 0
[[ -z "${SESSION_FLOW_OBSERVER_ANALYSIS:-}" ]] || exit 0

INPUT="$(cat)"
# silent-skip-ok: opt-in arming hook — a missing prerequisite is a by-design
# no-op that preserves zero-config behavior; /session-flow:setup surfaces the
# absence on demand, and SessionStart output would fire this notice every start.
command -v jq >/dev/null 2>&1 || exit 0

SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // ""' 2>/dev/null)"
case "$SOURCE" in
startup | resume) ;;
*) exit 0 ;;
esac

AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)"
[[ -z "$AGENT_TYPE" ]] || exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)"
[[ -n "$TRANSCRIPT" && -n "$SESSION_ID" ]] || exit 0

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve memory_dir exactly as retro does (concern file -> default .work), reusing
# the shared parser rather than reimplementing it. Anchor a relative root to the
# project dir so the detached observer (which will not share this cwd) resolves it.
MEMORY_DIR="$(bash "$PLUGIN_ROOT/skills/retro/scripts/parse-concern-value.sh" \
  .claude/topic-docs.yaml memory_dir "" 2>/dev/null || true)"
MEMORY_DIR="${MEMORY_DIR:-.work}"
case "$MEMORY_DIR" in
/* | ?:*) ;;
*) MEMORY_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/$MEMORY_DIR" ;;
esac
LEDGER_DIR="$MEMORY_DIR/running-retros"

# Transient observations are machine-local plugin state, never the consumer repo.
WORK_DIR="${CLAUDE_PLUGIN_DATA:-${TEMP:-${TMPDIR:-/tmp}}}/session-flow-observer"

MODEL="${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_MODEL:-claude-haiku-4-5}"
IDLE="${CLAUDE_PLUGIN_OPTION_OBSERVER_IDLE_SECONDS:-900}"
POLL="${CLAUDE_PLUGIN_OPTION_OBSERVER_POLL_SECONDS:-5}"
MAX="${CLAUDE_PLUGIN_OPTION_OBSERVER_MAX_SECONDS:-86400}"

# Pick an interpreter that is actually Python 3.10+ (a bare `python` may be older).
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 &&
    "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$c"
    break
  fi
done
[[ -n "$PY" ]] || exit 0

ARM="$PLUGIN_ROOT/skills/running-retro/scripts/arm_observer.py"
[[ -f "$ARM" ]] || exit 0

args=(--transcript "$TRANSCRIPT" --work-dir "$WORK_DIR" --ledger-dir "$LEDGER_DIR"
  --session-id "$SESSION_ID" --plugin-root "$PLUGIN_ROOT" --model "$MODEL"
  --idle-seconds "$IDLE" --poll-seconds "$POLL" --max-seconds "$MAX")
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED:-true}" == "true" ]] && args+=(--analysis)
[[ "${CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_BARE:-false}" == "true" ]] && args+=(--bare)

# The launcher self-detaches the observer and returns immediately; run it in the
# foreground so the detached child is fully spawned before the hook exits.
"$PY" "$ARM" "${args[@]}" >/dev/null 2>&1 || true
exit 0
