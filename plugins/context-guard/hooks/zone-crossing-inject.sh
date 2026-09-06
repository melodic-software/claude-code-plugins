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

# SPAWN DISCIPLINE (PostToolBatch fires on every tool batch, so every process
# here is paid on the critical path of every batch). The hook directory comes
# from parameter expansion rather than `dirname`, which this file needs three
# times (two sources plus the resolver path) and would therefore cost three
# processes before a single line of work. The `.` fallback reproduces dirname's
# own answer for a bare, slash-free invocation; hooks.json always passes an
# absolute path.
#
# REDIRECTION PLACEMENT, and why it is a spawn-count rule rather than a style
# one. Bash normally elides the extra fork inside `$(...)` and execs the command
# directly in the substitution's subshell — but only when that command carries
# no redirection of its own. `2>/dev/null`, `<<<`, and a pipeline each defeat
# the elision, so every one of them written INSIDE a substitution silently
# doubles that call site's process cost. Hoisting them onto an enclosing
# `{ ...; }` group restores the elision: the same stream is redirected, stdout
# is still captured, and the command's exit status still propagates. Every
# `$( )` on this hook's path therefore holds a bare simple command, with its
# redirections on the group.
#
# The group move itself is behaviour-neutral. The payload pass below also
# swapped a `printf | jq` pipe for a `<<<` here-string, and that one is NOT
# free on large payloads — read the note at that call site before treating this
# rewrite as pure saving.
#
# That distinction is invisible to the xtrace budget test at the bottom of
# zone-crossing-inject.test.sh, which counts commands in COMMAND POSITION: a
# fork that never execs never reaches one. The strace-based counterpart there
# is what holds this rule, and #3520 is the regression it was added for.
CG_DIR=${BASH_SOURCE[0]%/*}
[[ "$CG_DIR" == "${BASH_SOURCE[0]}" ]] && CG_DIR=.
# shellcheck source=hook-utils.sh
source "$CG_DIR/hook-utils.sh"
# shellcheck source=payload.sh
source "$CG_DIR/payload.sh"

hook::check_enabled "CONTEXT_GUARD_HOOKS"

START_EPOCH=${EPOCHREALTIME:-0}
# Not absolutized through `cd … && pwd`: this path is only ever handed to
# `bash`, which resolves it against the same working directory the hook started
# in, and the hook never changes directory. The `..` segment was already there.
RESOLVER="$CG_DIR/../scripts/context-zone.sh"

# silent-skip-ok: without a stdin payload there is no session_id to key the
# snapshot seam — nothing this hook could resolve or say. Chunked reader:
# PostToolBatch payloads carry every serialized tool result and routinely
# exceed what a single bounded read survives on Windows pipes.
#
# The `_to` form assigns INPUT in this process. `INPUT=$(cg::read_payload)`
# forked a subshell to capture output the reader had already assembled in a
# variable — a whole process, on a host where one costs hundreds of
# milliseconds, spent moving a string between two copies of the same shell.
INPUT=""
cg::read_payload_to INPUT || exit 0

# ONE jq for the whole payload rather than one per field. hook::jq_field spawns
# a jq per call and this hook needs two fields; the payload is read once and
# both fields come back as two lines in a FIXED ORDER (event, then session). An
# absent field yields an empty line, which is what a per-field `// empty` plus
# non-empty test yields too. `gsub("\r";"")` is carried over from
# hook::jq_field for the Windows carriage-return case.
#
# Not regex-extracted: a PostToolBatch payload carries every serialized tool
# result, so a pattern for these fields would be matching against tool output
# rather than against the envelope. post-compact-mark.sh's regex path is safe
# for its own payload shape; this one keeps jq as the parser.
#
# REDIRECTIONS GO ON THE GROUP, NOT INSIDE THE SUBSTITUTION — see the
# REDIRECTION PLACEMENT note at the top of this file. `printf '%s' "$INPUT" |
# jq` cost three process creations to run one jq: the subshell the substitution
# opens, a child for the pipeline's left-hand side (a `printf` BUILTIN — a whole
# process to hand over a string this shell already holds), and the child that
# becomes jq. Hoisting `<<<` and `2>/dev/null` onto the enclosing group leaves
# jq a bare simple command inside the substitution, and the extraction costs
# one process instead of three.
#
# What jq sees is unchanged: the group's stderr redirect suppresses exactly what
# jq's own did, the substitution still captures stdout, a nonzero jq status still
# propagates out of the group, and jq parses JSON, so the newline `<<<` appends
# changes nothing.
#
# ONE THING DOES CHANGE, and it is disclosed rather than buried. `<<<` is not a
# pipe. Bash 5.1+ delivers a here-string through a pipe only while it fits in
# the pipe buffer; at or above 64KiB it spills the string to a temp file
# (`/tmp/sh-thd.*`, measured here: 60,000 bytes stays in the pipe, 65,536 opens
# the file) and hands jq that fd. The `printf | jq` form this replaced never
# touched disk at any size. Output is byte-identical either way, but a
# PostToolBatch payload carrying every serialized tool result routinely clears
# 64KiB, so a large fire now writes and reads a temp file it did not before.
# That is a real cost on the very hosts this change is for: #3508's Windows
# machines run Defender real-time protection, which scans temp-file writes, and
# the 0.4.8 measurement in the plugin README already attributes 22.0 s on that
# platform to it. The trade taken is one guaranteed process creation per fire
# against disk I/O on the fires that exceed the buffer; the README's hook-cost
# section states it. Feeding the hook's stdin straight to jq would avoid both,
# but that means giving up payload.sh's bounded drain loop — see the note there.
{ FIELDS=$(jq -r '(.hook_event_name // ""), (.session_id // "") | gsub("\r";"")'); } 2>/dev/null <<<"$INPUT"
# jq writes CRLF line endings on this host, and command substitution strips only
# the TRAILING one, so with two lines the separator's carriage return survives
# into the split and would ride along on the event name. The single-field helper
# never saw this because its one and only line ending was the trailing one.
# gsub above has already removed any CR belonging to a field's value, so nothing
# left here is anything but jq's own terminators.
FIELDS=${FIELDS//$'\r'/}
EVENT=${FIELDS%%$'\n'*}
SESSION=${FIELDS#*$'\n'}
# No newline in FIELDS means jq emitted at most one line, so there is no
# session field to take, and the expansion above would otherwise hand back the
# event name.
[[ "$SESSION" != "$FIELDS" ]] || SESSION=""
[[ -n "$EVENT" ]] || EVENT="PostToolBatch"
hook::require_jq "$EVENT" "context-guard" "$INPUT"

[[ -n "$SESSION" ]] || exit 0
# Same character class the tee/resolver enforce — also path containment for
# the state file below.
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

# Stderr redirected on the GROUP, not inside the substitution: the resolver is
# one process, and `$(bash … 2>/dev/null)` billed two for it. Same suppression
# (the resolver's zones.json notices stay hidden from this caller, as before),
# same captured word, and `||` still sees the resolver's status.
{ zone=$(bash "$RESOLVER" "$SESSION"); } 2>/dev/null || zone="unknown"

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
# `$(<file)` plus parameter expansion instead of `tr -cd | head -c`, which cost
# two processes per marker and four per fire. Same result on every input this
# hook can see: `$(<f)` strips trailing newlines and keeps embedded ones, so a
# corrupt two-line file still fuses exactly as the pipeline fused it (the
# sibling-file note below depends on that). The class stays [:lower:] rather
# than a-z so it remains locale-independent, and the 16-character truncation is
# byte-identical to `head -c 16` once the content is lowercase-only.
# The stderr redirect sits on the group, NOT inside the substitution: a file
# removed between the -r test and the read makes bash print its own "No such
# file" on the hook's stderr, which the old `2>/dev/null` on the pipeline
# swallowed. `$(<file 2>/dev/null)` cannot take its place, because a second
# redirection turns the fast-path read back into a null command and the
# marker reads as empty on every fire.
last=""
zone_on_disk=""
if [[ -r "$STATE_FILE" ]]; then
  { last=$(<"$STATE_FILE"); } 2>/dev/null || last=""
  # The raw bytes, before normalization. The write block compares the new
  # value against these, so a marker in a legacy format is still rewritten in
  # the current one even when its normalized zone is unchanged.
  zone_on_disk="$last"
  last=${last//[^[:lower:]]/}
  last=${last:0:16}
fi
armed=""
armed_on_disk=""
if [[ -r "$ARMED_FILE" ]]; then
  { armed=$(<"$ARMED_FILE"); } 2>/dev/null || armed=""
  armed_on_disk="$armed"
  armed=${armed//[^[:lower:]]/}
  armed=${armed:0:16}
fi
# A SIBLING file, not a second line in the existing one: `last` is read with
# `tr -cd '[:lower:]'`, which strips the newline too, so a two-line state file
# would fuse into "dumbacceptable" and rank as smart. Sessions already running
# when this version lands have a `.zone` file and no `.armed` file; seeding the
# armed rank from the last-seen zone reproduces the pre-hysteresis decision for
# exactly one call, after which the marker latches normally. No migration step
# and no state-format version are needed for that.
[[ -n "$armed" ]] || armed="$last"

# Both set REPLY rather than printing their answer: a command substitution
# forks a subshell, and the ladder is walked on every fire of a hook that runs
# once per tool batch.
rank() {
  case "$1" in
  acceptable) REPLY=1 ;;
  dumb) REPLY=2 ;;
  *) REPLY=0 ;; # smart, or no prior observation (baseline)
  esac
}
unrank() {
  case "$1" in
  2) REPLY=dumb ;;
  1) REPLY=acceptable ;;
  *) REPLY=smart ;;
  esac
}
rank "$zone"
new_rank=$REPLY
rank "$armed"
armed_rank=$REPLY

# See the header. The armed rank rises to whatever this observation reports, and
# decays only on a return to the BEST band — a target on the ladder, not a
# distance along it.
BEST_RANK=0 # smart
next_armed_rank=$armed_rank
if ((new_rank > armed_rank || new_rank == BEST_RANK)); then
  next_armed_rank=$new_rank
fi
unrank "$next_armed_rank"
next_armed=$REPLY

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
# The state directory exists on every fire after the session's first, so the
# guard pays the process once per session instead of once per tool batch.
# `mkdir -p` on an existing directory exits 0 anyway, so no outcome changes.
[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
# A marker whose on-disk value already matches is not rewritten. This hook
# fires once per UserPromptSubmit and once per PostToolBatch, so a three-batch
# turn that stays in one zone fired four times and rewrote both files four
# times to the values they already held. `zone_on_disk` and `armed_on_disk`
# are the raw reads before normalization, so an absent marker and a marker in
# a legacy format both still get written. Everything below is unchanged:
# `.zone` moves first, `.armed` only after it lands, and a failed `.armed`
# write rolls `.zone` back only if this fire was the one that moved it.
persist_failed=""
wrote_zone=""
if [[ "$zone" != "$zone_on_disk" ]]; then
  if printf '%s\n' "$zone" >"$STATE_FILE" 2>/dev/null; then
    wrote_zone=1
  else
    persist_failed="zone"
  fi
fi
if [[ -z "$persist_failed" && "$next_armed" != "$armed_on_disk" ]] &&
  ! printf '%s\n' "$next_armed" >"$ARMED_FILE" 2>/dev/null; then
  persist_failed="armed"
  # Roll the label back to what it said before, so the message the next
  # successful call emits names the zone the session was really in rather than
  # the one it is in now. Best-effort: if the rollback itself fails the label is
  # stale, which mislabels one message — never a lost or repeated notice,
  # because the gate did not move either way.
  if [[ -n "$wrote_zone" ]]; then
    if [[ -n "$last" ]]; then
      printf '%s\n' "$last" >"$STATE_FILE" 2>/dev/null || :
    else
      rm -f "$STATE_FILE" 2>/dev/null || :
    fi
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
