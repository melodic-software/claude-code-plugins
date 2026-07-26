#!/usr/bin/env bash
# PreToolUse gate (matcher: Write|Edit|NotebookEdit|Agent|Workflow): in
# BLOCKING mode only, deny new mutating/spawning work once a session sits in
# a FRESH dumb-zone snapshot past a small grace budget.
#
# Posture contract (conforming to docs/conventions/hook-observability's
# gate-posture enum advisory | blocking):
#   - advisory (default): this gate is inert — guidance comes from the
#     advisory injection hook (zone-crossing-inject.sh).
#   - blocking: deny matched tool calls when ALL hold: the resolver returns
#     `dumb` from a fresh snapshot (staleness enforced inside the resolver),
#     AND the per-session grace budget is exhausted, AND the call is not
#     exempt. FAIL-OPEN everywhere else: `unknown` never blocks, a missing
#     prerequisite never blocks, resolver failure never blocks.
#
# NO-DEADLOCK EXEMPTIONS (why the matcher is what it is): the gate matches
# only mutating/spawning tools. Read-only tools, Bash, and Skill invocations
# never reach it, and Write/Edit targets whose path mentions "handoff" are
# exempted below — so a session told to stop can ALWAYS produce a durable
# handoff (the save-point machinery is reads + Bash + a handoff-path Write)
# and can always run the handoff skill itself.
#
# Grace budget: the first N matched calls after the session first resolves
# dumb are allowed (N = zone_gate_grace_calls userConfig, default 20), so an
# in-flight step can land before the gate closes. The counter resets when
# the session leaves the dumb zone.
#
# Kill switches: context_guard_hooks_enabled (whole hook set) and
# zone_hook_mode (this gate is active only when it equals "blocking"), read
# via their CLAUDE_PLUGIN_OPTION_* hook-process mirrors with in-script
# defaults (the userConfig `default` field is not delivered to hook
# processes — docs/conventions/hook-config-delivery, fact 3).

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=payload.sh
source "$(dirname "${BASH_SOURCE[0]}")/payload.sh"

hook::check_enabled "CONTEXT_GUARD_HOOKS"

MODE="${CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE:-advisory}"
# Pure inapplicability: the gate exists only in blocking mode; the advisory
# posture's visible surface is the injection hook.
[[ "$MODE" == "blocking" ]] || exit 0

START_EPOCH=${EPOCHREALTIME:-0}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../scripts/context-zone.sh"

# silent-skip-ok: no stdin payload → no session_id → fail-open (a gate that
# cannot identify its session must never block). Chunked reader: a large
# Write's tool_input rides in this payload, and a single bounded read timing
# out on it would fail the gate open for exactly the biggest writes.
INPUT=$(cg::read_payload) || exit 0
hook::require_jq "PreToolUse" "context-guard" "$INPUT"

SESSION=$(hook::jq_field "$INPUT" '.session_id') || exit 0
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME:-.}/.claude/context-guard}/state"
COUNT_FILE="$STATE_DIR/$SESSION.gate-count"

zone=$(bash "$RESOLVER" "$SESSION" 2>/dev/null) || zone="unknown"

# Evidence-degraded marker (reader contract): a compacted session is treated
# as dumb regardless of the resolved word — a post-compaction percentage
# resets downward while the context evidence is already gone, and without
# this override the marker would be write-only and compaction would disarm
# the gate the continuation router's own fallthrough recommends.
if [[ -n "${HOME:-}" && -e "$HOME/.claude/context-guard/context/$SESSION.compacted" ]]; then
  zone="dumb"
fi

if [[ "$zone" != "dumb" ]]; then
  # Fail-open on smart/acceptable/unknown — and leaving the dumb zone
  # (recovery, /clear into a new session, fresh snapshot) re-arms the grace
  # budget.
  rm -f "$COUNT_FILE" 2>/dev/null || true
  exit 0
fi

# Handoff-writing exemption: a Write/Edit/NotebookEdit whose target path
# mentions "handoff" is exactly the operation blocking mode exists to force —
# never gate it.
target=$(jq -r '(.tool_input.file_path // .tool_input.notebook_path // "")' <<<"$INPUT" 2>/dev/null) || target=""
shopt -s nocasematch
if [[ -n "$target" && "$target" == *handoff* ]]; then
  shopt -u nocasematch
  exit 0
fi
shopt -u nocasematch

GRACE="${CLAUDE_PLUGIN_OPTION_ZONE_GATE_GRACE_CALLS:-20}"
[[ "$GRACE" =~ ^[0-9]+$ ]] || GRACE=20

umask 077
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
count=0
[[ -r "$COUNT_FILE" ]] && count=$(tr -cd '0-9' <"$COUNT_FILE" 2>/dev/null | head -c 9)
[[ "$count" =~ ^[0-9]+$ ]] || count=0
count=$((count + 1))
printf '%s\n' "$count" >"$COUNT_FILE" 2>/dev/null || true

if ((count <= GRACE)); then
  exit 0
fi

TOOL=$(hook::jq_field "$INPUT" '.tool_name') || TOOL="tool"
reason="context-guard blocking mode: this session is in the dumb context zone (fresh snapshot) and the grace budget ($GRACE matched calls) is exhausted, so new $TOOL work is denied. Write a durable handoff now and resume in a fresh session: handoff-path writes, read-only tools, Bash, and Skill invocations all remain allowed — run /session-flow:handoff (if installed), or write a resume file whose path contains 'handoff'. Operators can soften this via the zone_hook_mode userConfig option (advisory)."
jq -n --arg reason "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
hook::emit_telemetry "zone-gate" "PreToolUse" "blocked" "$START_EPOCH" \
  '{"zone":"dumb","grace":'"$GRACE"',"calls_seen":'"$count"'}'
exit 0
