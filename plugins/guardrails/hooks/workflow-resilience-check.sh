#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED:-false}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary workflow-resilience-check PreToolUse open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; empty
# or timed-out stdin skips this advisory hook. Buffering does not require jq
# (hook::buffer_stdin's own JSON-completeness check is jq-optional), so it
# runs before the jq gate below — hook::require jq needs the buffered input
# for its once per session and agent notice scoping.
hook::buffer_stdin_to INPUT || exit 0

# jq parses the tool payload and builds the additionalContext JSON.
# hook::require jq fails OPEN (this hook never blocks) but makes the degraded
# state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session and agent — see docs/contracts/hook-observability/.
hook::require jq "PreToolUse" guardrails "$INPUT"

# Both payload fields in ONE jq process (hook::jq_fields): a jq spawn is fork()
# emulation on Windows Git Bash. A missing jq or an unparsable payload exits 0;
# hook::require jq above has already made the degraded state visible once per
# session and agent.
hook::jq_fields "$INPUT" '.tool_input.script' '.tool_input.scriptPath' || exit 0
SCRIPT="${HOOK_JQ_FIELDS[0]}"
SCRIPT_PATH="${HOOK_JQ_FIELDS[1]}"

if [[ -z "$SCRIPT" && -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT=$(tr -d '\r' <"$SCRIPT_PATH" 2>/dev/null)
fi
[[ -n "$SCRIPT" ]] || exit 0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local findings_json="$1"
  local data
  data=$(jq -n --argjson findings "$findings_json" '{tool:"",file:"",findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "workflow-resilience-check" "PreToolUse" "ok" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

if ! grep -qE 'parallel\(|pipeline\(' < <(printf '%s' "$SCRIPT") ||
  grep -qE 'inWaves|inWavesPipeline|agentRetry' < <(printf '%s' "$SCRIPT"); then
  emit_tel '[]'
  exit 0
fi

FINDING="This Workflow script fans out with parallel()/pipeline() with no wave cap or retry wrapper (none of inWaves, inWavesPipeline, agentRetry); a wide fan-out can hit 529 overload errors. The workflow-authoring skill covers caps and retries. Claude Code's own 529 retry backoff ceiling is set by CLAUDE_CODE_OVERLOADED_RETRY_MAX_DELAY_MS; use it beside caps and retries, not in place of them. Its default and range are at https://code.claude.com/docs/en/errors#tune-retry-behavior"
hook::emit_channels PreToolUse "$FINDING" ""
FINDINGS_JSON=$(jq -n --arg f "$FINDING" '[$f]' 2>/dev/null) || FINDINGS_JSON='[]'
emit_tel "$FINDINGS_JSON"

exit 0
