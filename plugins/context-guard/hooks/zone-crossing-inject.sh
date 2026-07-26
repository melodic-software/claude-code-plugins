#!/usr/bin/env bash
# PostToolBatch + UserPromptSubmit hook: inject continuation guidance ONCE per
# transition into a WORSE context zone; stay silent otherwise.
#
# Cadence contract: the session's zone is resolved from the plugin's
# own snapshot seam via scripts/context-zone.sh (the single band/combination
# authority — this hook never re-implements band logic). The last-seen zone
# is kept per session in a private state file; injection fires only when the
# rank worsens (smart → acceptable/dumb, acceptable → dumb, or a first
# observation already past smart). `unknown` is always silent and never
# updates state — no data is not a transition. Improvements update state
# silently so a later relapse injects again.
#
# ADVISORY-ONLY: this hook only ever exits 0 and only ever emits
# additionalContext. The blocking posture lives in the separate PreToolUse
# gate (zone-gate.sh). PostToolBatch fires once per parallel tool batch
# before the next model call — one injection point per model turn, no
# per-tool dedupe needed; UserPromptSubmit covers turns that begin without a
# prior batch (fresh prompt after idle).
#
# State root: ${CLAUDE_PLUGIN_DATA} (plugin-private runtime state, NOT part
# of the reader contract seam), falling back to ~/.claude/context-guard/state
# when the harness doesn't export it.
#
# Kill switch: context_guard_hooks_enabled userConfig boolean, read via the
# CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED hook-process mirror.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=payload.sh
source "$(dirname "${BASH_SOURCE[0]}")/payload.sh"

hook::check_enabled "CONTEXT_GUARD_HOOKS"

START_EPOCH=${EPOCHREALTIME:-0}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../scripts/context-zone.sh"

# silent-skip-ok: without a stdin payload there is no session_id to key the
# snapshot seam — nothing this hook could resolve or say. Chunked reader:
# PostToolBatch payloads carry every serialized tool result and routinely
# exceed what a single bounded read survives on Windows pipes.
INPUT=$(cg::read_payload) || exit 0

EVENT=$(hook::jq_field "$INPUT" '.hook_event_name') || EVENT="PostToolBatch"
hook::require_jq "$EVENT" "context-guard" "$INPUT"

SESSION=$(hook::jq_field "$INPUT" '.session_id') || exit 0
# Same character class the tee/resolver enforce — also path containment for
# the state file below.
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

zone=$(bash "$RESOLVER" "$SESSION" 2>/dev/null) || zone="unknown"

# Evidence-degraded marker (reader contract): a compacted session is treated
# as dumb regardless of the resolved word — including a green post-compaction
# reading and including unknown, because the marker IS data even when the
# snapshot has none.
degraded=""
if [[ -n "${HOME:-}" && -e "$HOME/.claude/context-guard/context/$SESSION.compacted" ]]; then
  degraded="yes"
  zone="dumb"
fi

# Silent on unknown, and state is left untouched: absence of data is not a
# transition, and a later real reading must compare against the last REAL one.
[[ "$zone" == "smart" || "$zone" == "acceptable" || "$zone" == "dumb" ]] || exit 0

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME:-.}/.claude/context-guard}/state"
STATE_FILE="$STATE_DIR/$SESSION.zone"
last=""
[[ -r "$STATE_FILE" ]] && last=$(tr -cd '[:lower:]' <"$STATE_FILE" 2>/dev/null | head -c 16)

rank() {
  case "$1" in
  acceptable) printf '1' ;;
  dumb) printf '2' ;;
  *) printf '0' ;; # smart, or no prior observation (baseline)
  esac
}
new_rank=$(rank "$zone")
last_rank=$(rank "$last")

# Persist the current zone regardless of direction (improvements update
# silently) — owner-only, atomic enough for a single-writer-per-session file.
umask 077
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
printf '%s\n' "$zone" >"$STATE_FILE" 2>/dev/null || true

((new_rank > last_rank)) || {
  # No worsening. A recovery (rank drop) is still a meaningful outcome for
  # telemetry; an unchanged zone is not.
  if [[ -n "$last" && "$zone" != "$last" ]]; then
    hook::emit_telemetry "zone-crossing-inject" "$EVENT" "ok" "$START_EPOCH" \
      '{"zone":"'"$zone"'","previous":"'"$last"'","injected":false}'
  fi
  exit 0
}

prev_label="${last:-unobserved}"
zone_label="$zone"
[[ -n "$degraded" ]] && zone_label="dumb (evidence-degraded: this session was compacted, so its context evidence is already lossy regardless of the snapshot's numbers)"
guidance="context-guard: this session crossed from the ${prev_label} into the ${zone_label} context zone (snapshot seam, conservative-min over percentage and token bands). Response quality degrades as context occupancy grows. Prefer finishing the current step, then choose the continuation mechanism deliberately: (1) continue in-session only if the remaining work is small or simple enough for degraded context; (2) /clear if this session's context is disposable; (3) write a durable handoff then /clear if state must survive — run /session-flow:handoff (if that plugin is installed; otherwise write a resume file by hand before clearing); (4) /compact only at a phase boundary, as a last resort. For the full continuation router, run /session-flow:workflow (if installed)."
if [[ "$zone" == "dumb" ]]; then
  guidance+=" The dumb zone means degradation is likely already measurable: avoid starting new complex work in this window."
fi

hook::emit_channels "$EVENT" "$guidance" ""
hook::emit_telemetry "zone-crossing-inject" "$EVENT" "ok" "$START_EPOCH" \
  '{"zone":"'"$zone"'","previous":"'"${last:-}"'","injected":true}'
exit 0
