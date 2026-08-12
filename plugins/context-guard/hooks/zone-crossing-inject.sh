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
# already reported — now gates the emit.
#
# WHAT MAKES THE ARMED RANK DECAY: a sustained improvement, measured in
# CONSECUTIVE OBSERVATIONS, not in ranks. A fixed rank-delta cannot work
# uniformly on a three-rung ladder and must not be used here: requiring two
# ranks is satisfiable only from `dumb`, so a session armed at `acceptable`
# could never decay at all — full recovery to `smart` and relapse would stay
# silent for the rest of the session, however many times it happened. That is
# this issue's own defect inverted (never re-inject instead of always
# re-inject), and it is why the rule counts time rather than distance.
#
# So: any observation strictly better than the armed rank extends a streak;
# returning to the armed rank breaks it; REARM_DWELL consecutive better
# observations decay the armed rank to what is actually being observed. The
# same rule holds at every band, because a streak is expressible from any rung
# while a two-rank drop is not.
#
# REARM_DWELL is a declared judgment default, like the bands themselves
# (reference/reader-contract.md records their provenance) — nothing here is
# doc- or benchmark-derived. The reasoning: a band-edge oscillation resolves
# within a single observation, as one batch's results land and are released, so
# one better observation is exactly what noise looks like and cannot be allowed
# to re-arm. Three consecutive better observations span more than a full
# PostToolBatch/UserPromptSubmit cycle, which a session alternating across the
# edge turn by turn never accumulates. A `/clear` needs no dwell at all: it
# starts a new session id, hence a new state file and a fresh baseline.
#
# Net contract: a zone is announced at most once per session unless the session
# holds a genuine improvement, after which the ladder re-arms and the next
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
# A SIBLING file, not a second line in the existing one: `last` is read with
# `tr -cd '[:lower:]'`, which strips the newline too, so a two-line `.zone`
# would fuse into "dumbacceptable" and rank as smart. The armed marker holds
# TWO fields — "<zone-word> <better-streak>" — and is parsed field-wise rather
# than through that filter, so it carries the dwell counter without inheriting
# the fusing problem.
#
# Both fields are validated against their own vocabulary. Anything else — an
# empty file, a truncated one, a hand-edited one — falls through to the seeding
# rule below rather than ranking as `smart` and silently disarming the gate.
armed=""
streak=0
if [[ -r "$ARMED_FILE" ]]; then
  read -r armed_word armed_streak _ <"$ARMED_FILE" 2>/dev/null || true
  [[ "${armed_word:-}" =~ ^(smart|acceptable|dumb)$ ]] && armed="$armed_word"
  [[ "${armed_streak:-}" =~ ^[0-9]{1,3}$ ]] && streak="$armed_streak"
fi
# Sessions already running when this version lands have a `.zone` file and no
# `.armed` file; seeding the armed rank from the last-seen zone reproduces the
# pre-hysteresis decision for exactly one call, after which the marker latches
# normally. No migration step and no state-format version are needed for that.
if [[ -z "$armed" ]]; then
  armed="$last"
  streak=0
fi

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

# See the header. The armed rank rises immediately to whatever this observation
# reports, and falls only after REARM_DWELL CONSECUTIVE observations strictly
# better than it — never on a rank distance, which a three-rung ladder cannot
# express uniformly.
REARM_DWELL=3
next_armed_rank=$armed_rank
next_streak=$streak
if ((new_rank > armed_rank)); then
  # A worsening past everything already reported: arm here and start over.
  next_armed_rank=$new_rank
  next_streak=0
elif ((new_rank < armed_rank)); then
  next_streak=$((streak + 1))
  if ((next_streak >= REARM_DWELL)); then
    next_armed_rank=$new_rank
    next_streak=0
  fi
else
  # Back at the armed rank: the improvement did not hold, so the streak that
  # would have re-armed the ladder is broken. This is the flap, and breaking
  # the streak here is what keeps an oscillation from accumulating a dwell one
  # observation at a time.
  next_streak=0
fi

# Persist both markers regardless of direction — owner-only. A write failure
# (full or newly read-only filesystem) must fail OPEN SILENTLY: proceeding past
# it would compare this turn's zone against the same stale markers again on the
# next call, re-emitting the ~1KB guidance block every subsequent
# PostToolBatch/UserPromptSubmit instead of once per transition — which is the
# very defect the armed rank exists to bound. "Silent" means neither channel
# emits — the failure itself is still surfaced to operators as telemetry, never
# swallowed twice.
#
# THE GATE ADVANCES LAST, AND ONLY ALL-OR-NOTHING. The armed marker is what
# suppresses a future injection, so leaving it advanced on a turn that emitted
# NOTHING destroys the warning permanently: the next identical observation is no
# longer worse than the armed rank, and the operator never hears about the zone
# at all. That is strictly worse than the repeat this hook is otherwise tuned to
# avoid, so the ordering is the reverse of the intuitive one — `.zone`, which
# only labels the "previous" zone in a message, is written first, and `.armed`
# is installed afterwards. If either step fails, the gate is left exactly where
# it was and the same observation is free to emit on a later call.
#
# `.armed` is installed by RENAME rather than written in place, because a plain
# `>` truncates before it writes: a failure partway through would leave an empty
# marker, which parses as no marker, which seeds from `.zone` — by then already
# updated to the current zone — and suppresses the very warning this ordering
# exists to protect. A rename is atomic, so the marker is only ever its old
# value or its new one.
umask 077
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
persist_failed=""
printf '%s\n' "$zone" >"$STATE_FILE" 2>/dev/null || persist_failed=1
if [[ -z "$persist_failed" ]]; then
  armed_tmp="$ARMED_FILE.$$"
  if printf '%s %d\n' "$(unrank "$next_armed_rank")" "$next_streak" >"$armed_tmp" 2>/dev/null; then
    mv -f "$armed_tmp" "$ARMED_FILE" 2>/dev/null || persist_failed=1
  else
    persist_failed=1
  fi
  [[ -n "$persist_failed" ]] && rm -f "$armed_tmp" 2>/dev/null
fi
if [[ -n "$persist_failed" ]]; then
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
