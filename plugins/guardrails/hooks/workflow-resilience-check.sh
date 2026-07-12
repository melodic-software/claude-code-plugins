#!/usr/bin/env bash
# PreToolUse hook: advisory burst-resilience check for the Workflow tool.
# Triggered on Workflow tool calls (inline `script:` or saved `scriptPath`).
#
# NON-BLOCKING (advisory): exits 0 always. Emits additionalContext with the
# resilience checklist when the script fans out (parallel()/pipeline()) WITHOUT
# any wave-cap throttle (inWaves/inWavesPipeline) or retry wrapper (agentRetry).
# A bare fan-out launches up to the agent cap at once; sustained wide Opus
# fan-out trips server-side 529 (a 27-item Opus pipeline lost 22/27 agents this
# way). Closes the inline-authoring gap that no file glob can reach.
#
# Kill switch: HOOK_WORKFLOW_RESILIENCE_CHECK_ENABLED=false

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "WORKFLOW_RESILIENCE_CHECK"

# jq parses the tool payload and builds the additionalContext JSON. Fail OPEN
# when it is absent, but make the degraded state visible rather than silently
# disabling the advisory (this hook never blocks either way).
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/workflow-resilience-check: jq not found on PATH — advisory disabled (install jq to enable)." >&2
  exit 0
fi

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op).
INPUT=$(cat)
SCRIPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.script // empty' 2>/dev/null | tr -d '\r')
SCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.scriptPath // empty' 2>/dev/null | tr -d '\r')

# Saved-engine / resume path passes scriptPath (no inline script) — read the
# file so the same check covers saved scripts too. Absent both → nothing to do.
if [[ -z "$SCRIPT" && -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT=$(tr -d '\r' <"$SCRIPT_PATH" 2>/dev/null)
fi
[[ -n "$SCRIPT" ]] || exit 0

# Does the script fan out at all? No fan-out → no burst risk → stay quiet.
grep -qE 'parallel\(|pipeline\(' <<<"$SCRIPT" || exit 0

# Already applies a throttle helper or a retry wrapper → author has the
# resilience primitives; stay quiet.
if grep -qE 'inWaves|inWavesPipeline|agentRetry' <<<"$SCRIPT"; then
  exit 0
fi

# Fan-out with zero resilience primitives → advisory (never blocks the run).
hook::emit_additional_context PreToolUse "Workflow resilience (advisory): this script calls parallel()/pipeline() with no wave-cap throttle (inWaves/inWavesPipeline) and no retry wrapper (agentRetry). A bare fan-out over many items launches up to the agent cap at once; sustained wide Opus fan-out trips server-side 529 (a 27-item Opus pipeline lost 22/27 agents this way). Before relying on this run, apply burst-resilience practices: wave-cap (<=5 Opus, <=12 Sonnet via inWaves; chunk large-item pipelines via inWavesPipeline), wrap dispatches in agentRetry + .filter(Boolean), and on partial failure re-run ONLY the failed subset (resumeFromRunId or a fresh narrow run) — never blind-re-run the whole script. Ignore if this fan-out is over a small fixed set."

exit 0
