#!/usr/bin/env bash
# PostToolBatch + UserPromptSubmit hook: report a transition into a WORSE
# context zone ONCE; stay silent otherwise.
#
# TWO CHANNELS, TWO AUDIENCES — the split is load-bearing, not cosmetic.
# `systemMessage` renders to the operator; `additionalContext` lands in the
# model's context. The continuation menu (continue / clear / handoff / compact)
# is a HUMAN's choice and goes to the operator channel only. The model's channel
# carries the zone determination plus the counter-steer, and never an exit menu:
# a menu injected into model context manufactures the model's own initiative to
# stop, summarize, or hand off — the measurement decides only when to ask, while
# the model still decides whether to stop. That shape is a live finding under
# the instruction-audit catalog's I23 (claude-config, reference/criteria.md),
# whose Remediate clause prescribes exactly this: state the counter-steer
# plainly, and where the harness must surface a budget, pair it with a
# reassurance rather than with an exit menu.
#
# The counter-steer is stated INLINE rather than delegated to the `playbooks`
# doctrine that also carries it. Both plugins are independently installable with
# no dependency wiring, so a context-guard-only install would otherwise receive
# the zone word with nothing in context to interpret it against.
#
# The model channel states that continuation is the operator's CALL; it never
# states the operator has SEEN the menu. No documented hook behavior tells a
# hook whether an operator is present — `systemMessage` is documented only as a
# message shown to the user, with nothing said about non-interactive runs — so
# a delivery claim would be a fact this hook cannot know, in every mode rather
# than only headless ones. Emitting to an unread operator channel is harmless;
# telling the model a human has the menu when none does is not.
#
# Cadence contract: the session's zone is resolved from the plugin's
# own snapshot seam via scripts/context-zone.sh (the single band/combination
# authority — this hook never re-implements band logic). The last-seen zone
# is kept per session in a private state file; injection fires only when the
# rank worsens past the highest rank already REPORTED this session (smart →
# acceptable/dumb, acceptable → dumb, or a first observation already past
# smart). `unknown` is always silent and never updates state — no data is not
# a transition.
#
# HYSTERESIS (the armed rank). The bands are hard thresholds, and occupancy
# does not climb monotonically: tool results land and are released, so a
# session sitting near a boundary crosses it repeatedly. Comparing only
# against the LAST-SEEN zone made every re-crossing a fresh transition, so
# the ~1KB guidance block re-injected on each one, and an improvement in any
# amount silently re-armed the injection with nothing counting or capping the
# flap. A second marker — the ARMED rank, the worst zone this session has
# already reported — now gates the emit, and it decays only on an improvement
# of at least REARM_MARGIN ranks.
#
# The margin is a declared judgment default, like the bands themselves
# (reference/reader-contract.md records their provenance): a ONE-rank dip at a
# band edge is the oscillation described above and says nothing new, while a
# TWO-rank improvement — the full width of the ladder, dumb → smart — cannot
# be edge noise and means the window genuinely emptied. A `/clear` needs no
# margin at all: it starts a new session id, hence a new state file and a
# fresh baseline. So a zone is announced at most once per session unless the
# session really recovers, after which the ladder re-arms and the next
# worsening is reported normally.
#
# The last-seen zone is still tracked, separately: it is what the message and
# the recovery telemetry report as the previous zone, and it is not the emit
# gate.
#
# ADVISORY-ONLY: this hook only ever exits 0 and only ever emits context and a
# user-visible message. The blocking posture lives in the separate PreToolUse
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

# silent-skip-ok: with neither CLAUDE_PLUGIN_DATA nor HOME there is no
# resolvable state root, and a `.`-relative fallback would key the last-seen
# zone to whatever directory the hook happened to start in — the once-per-
# transition contract cannot hold against state that moves with the working
# directory, so the hook would re-inject on every cd. Same doctrine
# post-compact-mark.sh applies to its marker path.
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  STATE_DIR="$CLAUDE_PLUGIN_DATA/state"
elif [[ -n "${HOME:-}" ]]; then
  STATE_DIR="$HOME/.claude/context-guard/state"
else
  exit 0
fi
STATE_FILE="$STATE_DIR/$SESSION.zone"
ARMED_FILE="$STATE_DIR/$SESSION.armed"
last=""
[[ -r "$STATE_FILE" ]] && last=$(tr -cd '[:lower:]' <"$STATE_FILE" 2>/dev/null | head -c 16)
armed=""
[[ -r "$ARMED_FILE" ]] && armed=$(tr -cd '[:lower:]' <"$ARMED_FILE" 2>/dev/null | head -c 16)
# A SIBLING file, not a second line in the existing one: `last` is read with
# `tr -cd '[:lower:]'`, which strips the newline too, so a two-line state file
# would fuse into "dumbacceptable" and rank as smart. Sessions already running
# when this version lands have a `.zone` file and no `.armed` file; seeding the
# armed rank from the last-seen zone reproduces the pre-hysteresis decision for
# exactly one call, after which the marker latches normally. No migration step
# and no state-format version are needed for that.
[[ -n "$armed" ]] || armed="$last"

rank() {
  case "$1" in
  acceptable) printf '1' ;;
  dumb) printf '2' ;;
  *) printf '0' ;; # smart, or no prior observation (baseline)
  esac
}
unrank() {
  case "$1" in
  2) printf 'dumb' ;;
  1) printf 'acceptable' ;;
  *) printf 'smart' ;;
  esac
}
new_rank=$(rank "$zone")
armed_rank=$(rank "$armed")

# See the header. The armed rank rises to whatever this observation reports and
# falls only on an improvement at least this wide.
REARM_MARGIN=2
next_armed_rank=$armed_rank
if ((new_rank > armed_rank || armed_rank - new_rank >= REARM_MARGIN)); then
  next_armed_rank=$new_rank
fi

# Persist both markers regardless of direction — owner-only, atomic enough for
# a single-writer-per-session file. A write failure (full or newly read-only
# filesystem) must fail OPEN SILENTLY: proceeding past it would compare this
# turn's zone against the same stale markers again on the next call, re-emitting
# the ~1KB guidance block every subsequent PostToolBatch/UserPromptSubmit
# instead of once per transition — which is the very defect the armed rank
# exists to bound. "Silent" means neither channel emits — the failure itself is
# still surfaced to operators as telemetry, never swallowed twice.
#
# The ARMED file is written FIRST. If only one of the two lands, the safe
# survivor is the one that suppresses: a stale `.armed` at worst withholds a
# repeat notice, while a stale `.zone` only mislabels the "previous" zone in a
# message. Writing the gate first means a partial failure can never leave the
# gate open against a marker that already moved.
umask 077
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
if ! printf '%s\n' "$(unrank "$next_armed_rank")" >"$ARMED_FILE" 2>/dev/null ||
  ! printf '%s\n' "$zone" >"$STATE_FILE" 2>/dev/null; then
  hook::emit_telemetry "zone-crossing-inject" "$EVENT" "error" "$START_EPOCH" \
    '{"zone":"'"$zone"'","previous":"'"${last:-}"'","reason":"state_persist_failed"}'
  exit 0
fi

((new_rank > armed_rank)) || {
  # Nothing worse than this session has already reported. Three shapes reach
  # here and only the first two are worth telemetry: a genuine recovery (rank
  # drop), a re-crossing the armed rank suppressed (the flap this gate exists
  # for), and an unchanged zone, which is not an event.
  if [[ -n "$last" && "$zone" != "$last" ]]; then
    hook::emit_telemetry "zone-crossing-inject" "$EVENT" "ok" "$START_EPOCH" \
      '{"zone":"'"$zone"'","previous":"'"$last"'","armed":"'"$armed"'","injected":false}'
  fi
  exit 0
}

prev_label="${last:-unobserved}"
zone_label="$zone"
[[ -n "$degraded" ]] && zone_label="dumb (evidence-degraded: this session was compacted, so its context evidence is already lossy regardless of the snapshot's numbers)"

# Model channel: the determination, then the counter-steer. No exit menu, no
# continuation router, no invitation to end the turn — see the header.
guidance="context-guard: this session crossed from the ${prev_label} into the ${zone_label} context zone (snapshot seam, conservative-min over percentage and token bands). This is a measurement reported to you, not an instruction and not a decay signal: degradation shows up in your own output — drift, repetition, dropped constraints — never in a zone word. Do not volunteer to end the session, start a new one, summarize, hand off, or trim your work on the strength of this reading; keep working the task in hand. Continuation is the operator's call, and nothing here is being asked of you. Act on a continuation when the operator asks for one, when a mechanism gates on it, or when your own output shows the degradation this reading cannot see."
if [[ "$zone" == "dumb" ]]; then
  guidance+=" The dumb zone additionally means compaction distance is short, which is true regardless of model: write every expensive conclusion to a durable note as it stabilizes rather than at session end, so an unchosen compaction cannot take it."
fi

# Operator channel: the same crossing, plus the continuation menu that is the
# human's call to make.
operator="context-guard: this session crossed from the ${prev_label} into the ${zone_label} context zone (snapshot seam, conservative-min over percentage and token bands). On many models response quality degrades as context occupancy grows; onset varies by model — some vendor model guides state consistency through the full window — and the bands are tunable defaults (zones.json). Compaction distance shrinks regardless of model. Continuation options, yours to choose: (1) continue in-session if the remaining work is small or simple enough for degraded context; (2) /clear if this session's context is disposable; (3) write a durable handoff then /clear if state must survive — /session-flow:handoff (if that plugin is installed; otherwise write a resume file by hand before clearing); (4) /compact only at a phase boundary, as a last resort. For the full continuation router, /session-flow:workflow (if installed)."

hook::emit_channels "$EVENT" "$guidance" "$operator"
hook::emit_telemetry "zone-crossing-inject" "$EVENT" "ok" "$START_EPOCH" \
  '{"zone":"'"$zone"'","previous":"'"${last:-}"'","armed":"'"${armed:-}"'","injected":true}'
exit 0
