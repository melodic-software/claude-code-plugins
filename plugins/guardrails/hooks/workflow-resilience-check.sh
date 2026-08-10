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
# Opt-in switch: workflow_resilience_check_enabled userConfig option.
# DEFAULT OFF since 0.20.0: the #2021 hook-surface classification found this
# is a behavioral-class context injector — two greps and a fixed checklist that
# asserts nothing the model cannot derive — and PLUGIN-PHILOSOPHY.md's
# instruction-economy evidence gate ablates that class config-off first (the
# script stays; a consumer opts back in by setting the option to true).

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

# Explicit opt-in (NOT hook::check_enabled, whose unset-var fallback is "true"):
# an unset switch must read as the plugin.json default, which is false.
[[ "${CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED:-false}" == "true" ]] || exit 0

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; empty
# or timed-out stdin skips this advisory hook. Buffering does not require jq
# (hook::buffer_stdin's own JSON-completeness check is jq-optional), so it
# runs before the jq gate below — hook::require_jq needs the buffered input
# for its once-per-session notice scoping.
INPUT=$(hook::buffer_stdin) || exit 0

# jq parses the tool payload and builds the additionalContext JSON.
# hook::require_jq fails OPEN (this hook never blocks) but makes the degraded
# state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-workflow-resilience-check" "$INPUT"

SCRIPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.script // empty' 2>/dev/null | tr -d '\r')
SCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.scriptPath // empty' 2>/dev/null | tr -d '\r')

# Saved-engine / resume path passes scriptPath (no inline script) — read the
# file so the same check covers saved scripts too. Absent both → nothing to
# check (pure inapplicability, not a meaningful outcome) → no telemetry.
if [[ -z "$SCRIPT" && -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT=$(tr -d '\r' <"$SCRIPT_PATH" 2>/dev/null)
fi
[[ -n "$SCRIPT" ]] || exit 0

# Telemetry for a meaningful outcome (a check ran and returned a result) —
# gated on a wired sink so the unwired default path spawns no telemetry-only
# subprocess. Status is always "ok": this hook is advisory and never blocks;
# the outcome (no-fan-out / already-resilient / advisory-finding) rides in
# data.findings, matching cli-flag-verify's sibling shape.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local findings_json="$1"
  local data
  data=$(jq -n --argjson findings "$findings_json" '{tool:"",file:"",findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "workflow-resilience-check" "PreToolUse" "ok" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Does the script fan out at all? No fan-out → no burst risk → checked, clean.
#
# Both greps below take $SCRIPT through PROCESS SUBSTITUTION, never `<<<`. An
# inline Workflow `script:` (or a scriptPath file read above) is unbounded
# agent-authored content, and a here-string of 65536-65663 bytes deadlocks bash
# outright — see lib/path-detection/hardcoded-path-patterns.sh for the mechanism.
# This hook is advisory and never blocks, so the cost is not a lost verdict, but
# a hang still wedges the Workflow call until the harness cancels at the hook
# timeout. `printf | grep -q` is not the alternative: `grep -q` early-exits and
# SIGPIPEs printf, and under the `set -uo pipefail` above the pipeline reports
# 141 — which the `if !` here would read as "no fan-out".
if ! grep -qE 'parallel\(|pipeline\(' < <(printf '%s' "$SCRIPT"); then
  emit_tel '[]'
  exit 0
fi

# Already applies a throttle helper or a retry wrapper → author has the
# resilience primitives; checked, clean.
if grep -qE 'inWaves|inWavesPipeline|agentRetry' < <(printf '%s' "$SCRIPT"); then
  emit_tel '[]'
  exit 0
fi

# Fan-out with zero resilience primitives → advisory (never blocks the run).
FINDING="Workflow resilience (advisory): this script calls parallel()/pipeline() with no wave-cap throttle (inWaves/inWavesPipeline) and no retry wrapper (agentRetry). A bare fan-out over many items launches up to the agent cap at once; sustained wide Opus fan-out trips server-side 529 (a 27-item Opus pipeline lost 22/27 agents this way). Before relying on this run, apply burst-resilience practices: wave-cap (<=5 Opus, <=12 Sonnet via inWaves; chunk large-item pipelines via inWavesPipeline), wrap dispatches in agentRetry + .filter(Boolean), and on partial failure re-run ONLY the failed subset (resumeFromRunId or a fresh narrow run) — never blind-re-run the whole script. Ignore if this fan-out is over a small fixed set."
hook::emit_additional_context PreToolUse "$FINDING"
FINDINGS_JSON=$(jq -n --arg f "$FINDING" '[$f]' 2>/dev/null) || FINDINGS_JSON='[]'
emit_tel "$FINDINGS_JSON"

exit 0
