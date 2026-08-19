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
# already reported — now gates the emit, and it decays only when the session
# returns to the BEST band (`smart`).
#
# A TARGET, NOT A DISTANCE. 0.7.0 expressed that decay as a fixed rank delta
# (an improvement of at least two ranks) and shipped a rule that could only
# ever fire from one band. The ladder is three ranks wide, so from
# `acceptable` the largest available improvement is ONE rank: the delta was
# unsatisfiable there, and a session that armed at `acceptable` could never
# re-arm — it stayed silent through every later relapse for the rest of its
# life, which is the #2220 defect inverted rather than fixed. A delta cannot
# work uniformly on a scale this short. The re-arm target is therefore a place
# on the ladder — its bottom — which every band can reach.
#
# The rule is a declared judgment default, like the bands themselves
# (reference/reader-contract.md records their provenance): reaching `smart`
# means the window genuinely emptied, while a dip that lands short of it is
# the edge oscillation described above and says nothing new. A `/clear` needs
# no rule at all: it starts a new session id, hence a new state file and a
# fresh baseline.
#
# THE PROPERTY THIS GUARANTEES: within one arming cycle each zone is announced
# at most once, and only a return to `smart` opens a new cycle — so a genuine
# recovery followed by a relapse re-injects exactly once for the band it
# relapses into, from ANY armed band, and a flap that never reaches `smart`
# stays silent however long it oscillates.
#
# THE RESIDUAL, STATED: at the `smart`/`acceptable` edge a flap and a full
# recovery are the SAME observation — `smart` is both the far side of that
# boundary and the bottom of the ladder — so a session oscillating there
# re-announces `acceptable` once per down-up cycle. Rank granularity cannot
# separate the two cases: this hook sees one word per observation, never the
# occupancy behind it (the resolver's contract is exactly one word, and band
# logic lives there and only there). Suppressing that residual needs either a
# numeric deadband below the band edge or a dwell requirement on the improved
# reading, and a dwell wide enough to absorb the flap would also silence the
# single-observation recovery this rule exists to honor.
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

# See the header. The armed rank rises to whatever this observation reports, and
# decays only on a return to the BEST band — a target on the ladder, not a
# distance along it.
BEST_RANK=0 # smart
next_armed_rank=$armed_rank
if ((new_rank > armed_rank || new_rank == BEST_RANK)); then
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
# THE GATE MOVES LAST, AND NEVER WITHOUT ITS COMPANION. Failing open silently is
# only safe while the notice SURVIVES the failure. `.armed` is the emit gate, so
# advancing it while the accompanying `.zone` write failed would exit without
# emitting AND suppress the next identical observation — the first warning lost
# though it was never reported. That is 0.7.0's ordering, and it was wrong: a
# stale gate is not the "safe survivor" when the notice it suppresses was never
# delivered. So `.zone` is written first and `.armed` only after it lands; if
# either fails, the gate has not moved and the session is still owed its
# injection, which the next observation issues.
umask 077
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
persist_failed=""
if ! printf '%s\n' "$zone" >"$STATE_FILE" 2>/dev/null; then
  persist_failed="zone"
elif ! printf '%s\n' "$(unrank "$next_armed_rank")" >"$ARMED_FILE" 2>/dev/null; then
  persist_failed="armed"
  # Roll the label back to what it said before, so the message the next
  # successful call emits names the zone the session was really in rather than
  # the one it is in now. Best-effort: if the rollback itself fails the label is
  # stale, which mislabels one message — never a lost or repeated notice,
  # because the gate did not move either way.
  if [[ -n "$last" ]]; then
    printf '%s\n' "$last" >"$STATE_FILE" 2>/dev/null || :
  else
    rm -f "$STATE_FILE" 2>/dev/null || :
  fi
fi
if [[ -n "$persist_failed" ]]; then
  hook::emit_telemetry "zone-crossing-inject" "$EVENT" "error" "$START_EPOCH" \
    '{"zone":"'"$zone"'","previous":"'"${last:-}"'","marker":"'"$persist_failed"'","reason":"state_persist_failed"}'
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
[[ -n "$degraded" ]] && zone_label="dumb (evidence-degraded: this session was compacted)"

# Model channel: the determination, then the counter-steer. No exit menu, no
# continuation router, no invitation to end the turn — see the header. The
# "crossed from the ${prev_label}" phrasing is pinned by the contract test
# (partial-write recovery asserts the true previous zone is named).
guidance="context-guard: this session crossed from the ${prev_label} into the ${zone_label} context zone. This is a measurement, not an instruction: real degradation shows up in your own output — drift, repetition, dropped constraints — never in a zone word. Do not volunteer to end the session, summarize, hand off, or trim your work on the strength of this reading; keep working the task in hand. Continuation is the operator's call — act on one when the operator asks, a mechanism gates on it, or your own output shows the degradation this reading cannot see."
if [[ "$zone" == "dumb" ]]; then
  guidance+=" The dumb zone also means compaction distance is short, on every model: write each expensive conclusion to a durable note as it stabilizes, so an unchosen compaction cannot take it."
fi

# Operator channel: the same crossing, plus the continuation menu that is the
# human's call to make. Menu-first and terse — the detail behind the bands
# lives in the plugin README, not on the status line. The "(if installed)"
# hedges stay, and option 3 keeps a manual alternative: context-guard installs
# standalone (see header), so a menu naming only session-flow leaves such an
# install no actionable path when state must survive.
operator="context-guard: context zone ${prev_label} → ${zone_label}. Response quality can degrade as context fills (bands tunable: zones.json). Continuation options, yours to choose: (1) continue — remaining work is small; (2) /clear — this context is disposable; (3) /session-flow:handoff (if installed) or a hand-written resume note, then /clear — state must survive; (4) /compact — last resort, at a phase boundary. Full router: /session-flow:workflow (if installed)."

hook::emit_channels "$EVENT" "$guidance" "$operator"
hook::emit_telemetry "zone-crossing-inject" "$EVENT" "ok" "$START_EPOCH" \
  '{"zone":"'"$zone"'","previous":"'"${last:-}"'","armed":"'"${armed:-}"'","injected":true}'
exit 0
