#!/usr/bin/env bash
# Stop hook: the deterministic lane-stop gate (autonomy #535 member 3) plus the
# operator STOP-notification (member 4).
#
# "A lane that stops itself before its goal is met is a bug" is otherwise only a
# prompt admonition. This hook fires on every stop attempt of an opted-in
# autonomous lane and structurally intercepts it: unless completion is EXPLICITLY
# signaled, the first stop attempt is blocked with a re-injected completion
# self-check (converting a silent premature stop into "keep going or declare
# done"), and a lane that still stops after that one nudge is treated as a
# genuine down-lane — allowed to stop (never wedged) and the operator is alerted.
#
# SCOPE — this gate mechanizes ONE clause of the autonomous-pipeline reminder
# (reference/autonomous-pipeline-reminder.md): end the turn only on completion or
# a genuine block. It performs no content classification of the final message
# beyond the literal sentinel check below, so it cannot tell a blocked-on-user
# stop from a lazy one — both get the same single nudge. Every other clause of
# that reminder is carried by instruction alone; a shell hook cannot judge
# whether a final paragraph describes an action or reports one.
#
# DEFAULT-OFF. A Stop-blocking hook that engaged by default would wedge every
# interactive user's stop, so the gate is inert unless a session explicitly opts
# in. Every other exit path allows the stop.
#
# FAIL-OPEN. Unlike a PreToolUse guard (which fails closed to deny), a Stop gate
# that fails closed would trap a lane it cannot evaluate. On unreadable stdin,
# missing jq, or a non-Stop event it allows the stop. An unreadable or malformed
# TRUSTED CONFIG source likewise contributes no verdict — the default (off)
# applies — but an enablement claimed only on the untrusted env channel gets a
# visible once-per-session notice rather than a silent disengage.
#
# CONFIG IS READ FROM TRUSTED SOURCES ONLY (#1784). The gate previously read
# `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_*` straight off the environment —
# channel B of docs/conventions/hook-config-delivery, whose unset case a watched
# repository's own `.claude/settings.json` `env` block owns. A gate whose
# enablement (or sentinel, or marker path) the watched repository controls is
# not a gate. Per-key resolution is now, in precedence order:
#
#   1. managed settings (fixed root-owned paths + managed-settings.d drop-ins);
#   2. the per-session ARM RECORD: the claude-ops lane launcher arms a lane at
#      launch via this plugin's hooks/lane-stop-gate-arm.sh, which writes a
#      record under the plugin's own install-derived data directory; the session
#      carries only a random record id through the `lane_stop_gate_arm_id`
#      userConfig option. The env-delivered id is a capability POINTER, never
#      authority: it is shape-validated, looked up only in the install-derived
#      store, claimed by the first session that presents it through an exclusive
#      create so concurrent presenters cannot both win (a different session
#      replaying the same id is refused), and TTL-bounded — it lives for the
#      claiming session's whole life (every /loop cycle's stop stays gated),
#      retired by TTL and the launcher's relaunch sweep, never by a single stop;
#   3. user settings.json, located only from this script's own install path;
#   4. the in-script defaults (enabled=false, sentinel=LANE-STOP-OK, no marker).
#
# The `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED/SENTINEL/MARKER` env mirrors
# are never read as values. ENABLED/ARM_ID presence is used ONLY to decide
# whether to evaluate at all and to surface the visible not-honored notice.
#
# Completion signal (either is sufficient, checked deterministically — a shell
# hook cannot re-run the /goal evaluator model):
#   - the exact sentinel token (default LANE-STOP-OK) in the agent's final
#     message, matched only when it stands alone on its own line, or
#   - the existence of the configured marker file (consumed on use, so a prior
#     run's leftover marker never authorizes a later run). Consumption is
#     recorded in this plugin's own data directory, not carried solely by the
#     file's deletion: an `rm` the hook is not permitted to perform must not
#     leave a file a later run reads as a live signal.
#
# Config (userConfig keys, delivered per the precedence above):
#   lane_stop_gate_enabled     opt a session in (default false)
#   lane_stop_gate_sentinel    completion token (default LANE-STOP-OK)
#   lane_stop_gate_marker      completion-marker file (absolute, or relative to
#                              the session cwd; default unset)
#   lane_stop_gate_arm_id      launcher-written arm-record id (never authority)

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=lane-notify.sh
source "$(dirname "${BASH_SOURCE[0]}")/lane-notify.sh"
# shellcheck source=lane-stop-gate-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lane-stop-gate-lib.sh"

gate_resolve_install "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || true

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on an older host it is empty and hook::emit_telemetry skips fail-open.
START=${EPOCHREALTIME:-}

# emit_tel <status> <outcome> <signal> — fire-and-forget telemetry for an
# EVALUATED gate outcome (hook-telemetry convention; no-op unless the consumer
# sets HOOK_TELEMETRY_SINK). Only the three evaluated outcomes emit; the
# fail-open/skip exits stay silent — they are pre-evaluation, and emitting on
# every interactive default-off stop would be noise, not signal. The payload is
# a closed fixed vocabulary by design: never the sentinel value, the marker
# path, the cwd, or the branch, so the envelope cannot leak the completion
# token or lane-identifying paths into the sink.
emit_tel() {
  local data
  data=$(jq -nc --arg outcome "$2" --arg signal "$3" \
    '{outcome:$outcome,signal:$signal}' 2>/dev/null) || return 0
  hook::emit_telemetry "lane-stop-gate" "Stop" "$1" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Buffer stdin. Empty (rc 1) or timed-out (rc 2) → allow the stop (fail-open: a
# gate that cannot read the payload must not trap the lane).
INPUT=$(hook::buffer_stdin) || exit 0

# jq-free pre-filter: is the gate plausibly configured anywhere this host could
# honor — or at least CLAIMED, which must produce the visible notice below
# rather than silence? Sessions with no gate footprint at all (the interactive
# default) exit here, before the jq gate, so a jq-less machine never sees a
# lane-stop-gate notice for a session that never opted in. The env presence
# tests grant no authority: a hit only routes into evaluation, where the
# trusted sources decide.
gate_maybe_configured() {
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" ]] && return 0
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" ]] && return 0
  local f
  if f=$(gate_user_settings_file) && [[ -f "$f" ]]; then
    grep -q lane_stop_gate "$f" 2>/dev/null && return 0
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    grep -q lane_stop_gate "$f" 2>/dev/null && return 0
  done < <(gate_managed_settings_files)
  return 1
}
gate_maybe_configured || exit 0

# jq parses the payload and the trusted config. Absent → visible once-per-session
# notice, then allow the stop (fail-open). Stop supports additionalContext, so
# the notice reaches both the agent and the user.
hook::require_jq "Stop" "autonomy-lane-stop-gate" "$INPUT"

# Fire ONLY on a true top-level session stop. A subagent finishing is delivered
# as SubagentStop; guarding on the event name keeps a Task-tool worker's normal
# completion from ever tripping the lane gate, whichever way the platform routes
# the registration.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null | tr -d '\r')
[[ "$EVENT" == "Stop" ]] || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')

# --- Arm record ---------------------------------------------------------------
# Load (and claim) the arm record named by the env-carried id, if any. Success
# sets GATE_ARM_JSON and means: this session was armed by the operator-side
# launcher. TTL keeps a crashed lane's record from outliving its usefulness; the
# session claim makes a replayed id (e.g. one a lane leaked and a repo env block
# later serves to a different session) worthless.
GATE_ARM_TTL_SECONDS=$((7 * 86400))
GATE_ARM_JSON=""

# Does this session own the record whose claim sidecar is <claim path>?
#
# The claim is an EXCLUSIVE CREATE — `set -o noclobber` on a `>` redirection,
# i.e. open with O_CREAT|O_EXCL — the same primitive statusline-tee.sh uses for
# its snapshot write, extended from a process-unique name to mutual exclusion on
# a contended one. Read-then-write of the record itself cannot decide this:
# two Stop invocations presenting the same fresh id both read it unclaimed, both
# write, and the last rename wins, so BOTH honor the arm for that event while
# the loser — possibly the legitimate lane — is refused on every later stop.
# flock is not used: it is absent on macOS, the reason statusline-tee.sh already
# records for avoiding it.
#
# FAIL DIRECTION, unchanged: a store this hook cannot write leaves no claim file
# at all and the arm is HONORED. Being gated is never the harm here; the harm is
# a legitimate lane silently losing its gate. Two more reads share that
# direction — the existence recheck that tells "another session claimed it"
# apart from "an unwritable store" is itself racy, and a claim that exists but
# yields no owner honors as well. Read in the instant between the exclusive
# create and its write, that costs one extra gated stop and the binding that
# lands still names one session. Durably ownerless — a create that won whose
# write never landed — or a durably unwritable store honors every presenter for
# as long as it lasts: the same unbounded over-gating a failed claim write
# already produced before this change, in the same direction. An extra nudge,
# never an ungated lane.
#
# The comparison runs on a newline-stripped session id so the value written and
# the value read back are the same shape whatever the payload carried.
gate_arm_owned() {
  local claim="$1" me="${SESSION_ID//[$'\r\n']/}" owner=""
  if [[ -n "$me" ]] && (
    umask 077
    set -o noclobber
    printf '%s\n' "$me" >"$claim"
  ) 2>/dev/null; then
    return 0
  fi
  [[ -e "$claim" ]] || return 0
  # `|| true`, never `|| owner=""`: read reports failure on a final line with no
  # newline yet still assigns it, and clearing that would discard a real owner.
  IFS= read -r owner <"$claim" 2>/dev/null || true
  [[ -n "$owner" ]] || return 0
  [[ -n "$me" && "$owner" == "$me" ]]
}

gate_load_arm_record() {
  local id="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" rec claim json armed_at now claimed
  [[ -n "$id" ]] || return 1
  rec=$(gate_arm_record_path "$id") || return 1
  claim=$(gate_arm_claim_path "$id") || return 1
  [[ -f "$rec" ]] || return 1
  json=$(jq -ec '.' <"$rec" 2>/dev/null) || return 1
  armed_at=$(printf '%s' "$json" | jq -r '.armed_at // empty' 2>/dev/null)
  [[ "$armed_at" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s 2>/dev/null) || now=""
  if [[ -n "$now" ]] && ((now - armed_at > GATE_ARM_TTL_SECONDS)); then
    rm -f -- "$rec" "$claim" 2>/dev/null
    return 1
  fi
  # Compatibility read: a record claimed before the sidecar existed carries its
  # owner in the record itself and has no claim file. That field stays
  # authoritative so an upgrade cannot let a second session claim a record
  # already bound to a live lane; nothing writes it any more.
  claimed=$(printf '%s' "$json" | jq -r '.session_id // empty' 2>/dev/null)
  if [[ -n "$claimed" ]]; then
    [[ -n "$SESSION_ID" && "$claimed" == "$SESSION_ID" ]] || return 1
  else
    gate_arm_owned "$claim" || return 1
  fi
  # Assigned only past the ownership verdict: an unowned record contributes no
  # config, which is what keeps a replaying session from being honored at all.
  GATE_ARM_JSON="$json"
}
gate_load_arm_record || true

# The arm record is NOT consumed on a stop. A lane is one session across many
# /loop cycles (claude-ops lanes/context/refresh.md), and each cycle ends in a
# Stop the gate must still guard; deleting the record on the first
# completion-signaled or post-nudge stop would silently disarm every later
# cycle. The record instead lives for the claiming session — bound to it by the
# session-id claim above, so no other session can use it — and is retired by its
# TTL (checked on load) plus the launcher's own `find -mtime` sweep at the next
# relaunch.

# Per-key resolution: managed ▷ arm record ▷ user settings ▷ caller default
# (return 1). An armed session IS enabled; its record may also carry the
# sentinel and marker the launcher captured from the lane's config.
gate_option() {
  local key="$1" v
  if v=$(gate_managed_option "$key"); then
    printf '%s' "$v"
    return 0
  fi
  if [[ -n "$GATE_ARM_JSON" ]]; then
    if [[ "$key" == "lane_stop_gate_enabled" ]]; then
      printf 'true'
      return 0
    fi
    v=$(printf '%s' "$GATE_ARM_JSON" | jq -r --arg k "${key#lane_stop_gate_}" \
      '.[$k] | if type == "string" then "v:" + . else empty end' 2>/dev/null)
    if [[ "$v" == v:* ]]; then
      printf '%s' "${v#v:}"
      return 0
    fi
  fi
  local uf
  uf=$(gate_user_settings_file) || return 1
  gate_settings_option "$uf" "$key"
}

ENABLED=$(gate_option lane_stop_gate_enabled) || ENABLED=""
if [[ "$ENABLED" != "true" ]]; then
  # No trusted source says "on". A trusted explicit false stays silent — that is
  # a configured verdict, not a claim the gate declined to honor. The two ways a
  # gate a lane EXPECTED can end up off get distinct, accurate once-per-session
  # notices instead of a silent disengage:
  if [[ -z "$ENABLED" ]]; then
    if [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" && -z "$GATE_ARM_JSON" ]]; then
      # An arm id reached the hook, but no valid record backs it — spent,
      # TTL-expired, claimed by a different session, or malformed. This is the
      # legitimately-armed-then-stale case; do NOT blame a repo env block.
      if hook::notice_once "autonomy-lane-stop-gate-stale-arm" "$INPUT"; then
        hook::emit_skip_notice "Stop" \
          "autonomy lane-stop gate: this session carries an arm id but no matching arm record is present (it may have expired, been claimed by another session, or been cleaned up), so the gate stays off (#1784). Relaunch the lane through the claude-ops lane launcher to re-arm it."
      fi
    elif [[ "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" == "true" ]]; then
      # Enablement claimed on the untrusted env channel with no arm id at all —
      # a pre-0.12.0 launcher still delivering over --settings/env, or a repo
      # env block attempting the pre-#1784 attack. Surfacing it beats silence.
      if hook::notice_once "autonomy-lane-stop-gate-untrusted-enable" "$INPUT"; then
        hook::emit_skip_notice "Stop" \
          "autonomy lane-stop gate: enablement was claimed on the environment channel only — no managed/user setting configures it and no arm record matches — so the gate stays off (#1784). A lane launched expecting the gate needs the current claude-ops lane launcher (which arms it at launch); a repository cannot opt sessions in via its own settings.json env block."
      fi
    fi
  fi
  exit 0
fi

# Has completion been explicitly signaled? SIGNAL records which channel fired
# (telemetry vocabulary: sentinel | marker | none — never the token itself).
SIGNALED=0
SIGNAL="none"

# Signal 1 — the sentinel token in the agent's final message. Matched only when
# the token stands alone on its own line (surrounding whitespace allowed), which
# is exactly the "emit the exact token ... on its own line" instruction the block
# reason gives. Requiring a dedicated line — not merely a standalone word — means
# a message that only mentions or negates the token inline (e.g. "I should not
# emit LANE-STOP-OK yet") does not authorize the stop.
# An empty configured sentinel falls back to the default rather than silencing
# the token channel: emptiness is not a documented way to disable it, and the
# block reason below would otherwise instruct the agent to emit an empty token.
SENTINEL=$(gate_option lane_stop_gate_sentinel) || SENTINEL=""
[[ -n "$SENTINEL" ]] || SENTINEL="LANE-STOP-OK"
if [[ -n "$SENTINEL" ]]; then
  LAST=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
  # Escape any regex metacharacters in the (configurable) sentinel before use.
  SENTINEL_RE=$(printf '%s' "$SENTINEL" | sed 's/[][\.^$*+?(){}|/]/\\&/g')
  # Here-string, NOT `printf | grep -q`: under pipefail, grep -q exits on the
  # first match, and when a long message continues past the pipe buffer the
  # producer takes SIGPIPE — the pipeline then reads as false and a genuinely
  # signaled completion would be blocked. A here-string has no pipeline, so an
  # early match can never be lost.
  if grep -qE "^[[:space:]]*${SENTINEL_RE}[[:space:]]*$" <<<"$LAST"; then
    SIGNALED=1
    SIGNAL="sentinel"
  fi
fi

# --- Marker consumption ledger ------------------------------------------------
# One marker, one authorized stop. Deleting the marker is the tidy-up, NOT the
# latch: the marker lives in the watched checkout, which the hook may not be
# permitted to write, and a delete the OS refuses would otherwise leave a file
# that satisfies `[[ -f ]]` on a later, unrelated lane run — the cross-run
# bypass consuming the marker exists to close. The durable record therefore
# lives under this plugin's own data directory (gate_data_dir: install-derived
# first, CLAUDE_PLUGIN_DATA fallback only on an unanchored install). The
# fallback reaches nothing but THIS ledger — enablement and the arm record use
# the install-anchored gate_trusted_data_dir — and the marker it gates is an
# agent-writable declaration in the checkout anyway; see gate_data_dir in the
# lib for why a redirected/unwritable fallback degrades to the documented
# "deletion is the only latch" behavior rather than opening a new hole.

# Identity of the file currently at <path>, as "<mtime> <size>", or "" when this
# host's `stat` reports neither. Used to tell a recreated marker apart from the
# consumed one — BEST-EFFORT, and deliberately coarse. Both dialects' portable
# mtime is whole-second, so a marker recreated at the same size within the same
# second (an empty `touch`-style marker is the realistic case) is
# indistinguishable, and stays latched until the marker's NEXT write lands in a
# different second — an mtime does not advance on its own, so the clock passing
# the second is not what clears it. Sub-second and inode spellings would narrow
# that window but are GNU-only, and this identity feeds a GATE: the coarse read
# costs one skipped completion signal, while a wrong "recreated" verdict costs
# the unearned second authorization the ledger exists to prevent. A withheld
# stop is the correct failure direction, so the portable spelling stands.
marker_identity() {
  # portability-ok: GNU-first of a dual-dialect ladder — the BSD `-f` spelling is
  # the next alternative, and a host with neither returns the empty identity this
  # function documents (#1784)
  stat -c '%Y %s' -- "$1" 2>/dev/null ||
    stat -f '%m %z' -- "$1" 2>/dev/null ||
    printf ''
}

# Ledger path for a marker path. cksum keys the file name (POSIX, present where
# md5sum is not); the recorded path is re-checked on read, so a cksum collision
# costs a miss, never a wrong verdict.
marker_ledger_path() {
  local dir key
  dir=$(gate_data_dir)
  [[ -n "$dir" ]] || return 1
  key=$(printf '%s' "$1" | cksum 2>/dev/null | tr -cd '0-9') || return 1
  [[ -n "$key" ]] || return 1
  printf '%s/consumed-markers/%s' "$dir" "$key"
}

# Has the file now at <path> already authorized a stop? True when a ledger entry
# names this exact path AND the file has not changed since (or this host cannot
# tell, in which case a marker whose deletion failed stays consumed — the strict
# direction for a gate: it withholds authorization rather than granting it
# twice). A record whose file now reads as a different one is stale and removed,
# so the fresh marker authorizes normally — within the identity read's
# documented coarseness above.
marker_already_consumed() {
  local path="$1" ledger recorded_path="" recorded_id="" current
  ledger=$(marker_ledger_path "$path") || return 1
  [[ -f "$ledger" ]] || return 1
  { IFS= read -r recorded_path && IFS= read -r recorded_id; } <"$ledger" 2>/dev/null
  [[ "$recorded_path" == "$path" ]] || return 1
  current=$(marker_identity "$path")
  if [[ -n "$current" && -n "$recorded_id" && "$current" != "$recorded_id" ]]; then
    rm -f -- "$ledger" 2>/dev/null
    return 1
  fi
  return 0
}

# Record that the file at <path> has authorized a stop: its path on line 1, its
# identity on line 2. Best-effort — a data directory this hook cannot write
# leaves the deletion as the only latch, which is the behavior that predates
# this ledger.
marker_record_consumed() {
  local path="$1" ledger
  ledger=$(marker_ledger_path "$path") || return 0
  mkdir -p -- "$(dirname -- "$ledger")" 2>/dev/null || return 0
  printf '%s\n%s\n' "$path" "$(marker_identity "$path")" >"$ledger" 2>/dev/null || true
}

# Signal 2 — the completion-marker file. Absolute path used as-is; a relative
# path resolves against the session cwd from the payload. A marker already
# consumed by an earlier stop is not a signal, however long it survives on
# disk. On use it is deleted AND — when the delete did not take — recorded, so
# the next run reads the same verdict the delete was meant to produce.
MARKER=$(gate_option lane_stop_gate_marker) || MARKER=""
if [[ "$SIGNALED" -eq 0 && -n "$MARKER" ]]; then
  case "$MARKER" in
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')
    [[ -n "$CWD" ]] && MARKER="${CWD%/}/$MARKER"
    ;;
  esac
  if [[ -f "$MARKER" ]] && ! marker_already_consumed "$MARKER"; then
    SIGNALED=1
    SIGNAL="marker"
    rm -f -- "$MARKER" 2>/dev/null || true
    # The record is written only when the file survived the delete: a marker
    # that is gone cannot resurrect, and an empty ledger is one less thing to
    # keep correct.
    [[ -e "$MARKER" ]] && marker_record_consumed "$MARKER"
  fi
fi

# Completion signaled → this is a legitimate stop. Allow it, silently. The arm
# record is NOT consumed here — the session may /loop into another cycle whose
# stop must still be gated (see the load block).
if [[ "$SIGNALED" -eq 1 ]]; then
  emit_tel "ok" "completion-signaled" "$SIGNAL"
  exit 0
fi

STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)

# Already nudged once this stop cluster (stop_hook_active), yet the lane still
# stops without signaling completion → a genuine down/stuck lane. Alert the
# operator (member 4) and ALLOW the stop — blocking again risks a runaway loop,
# and Claude Code hard-caps consecutive Stop blocks regardless. The one bounded
# structural nudge is the mechanism; the notification is the fail-safe handoff.
if [[ "$STOP_ACTIVE" == "true" ]]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')
  BRANCH=""
  [[ -n "$CWD" ]] && BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null | tr -d '\000-\037')
  LANE="${CWD##*/}"
  [[ -n "$BRANCH" ]] && LANE="$LANE ($BRANCH)"
  [[ -n "$LANE" ]] || LANE="unknown"
  lane::notify "Autonomy lane stopped" \
    "Lane $LANE stopped without signaling completion — it may be down or stuck. Check it."
  emit_tel "ok" "stopped-after-nudge" "none"
  exit 0
fi

# First stop attempt without a completion signal → block once and re-inject the
# completion self-check. This directly counters the fabricated-context-percentage
# premature-stop failure (#576/#577): a self-estimated "~50% context" is not a
# completion condition. Emitted as the documented Stop stdout decision.
REASON="Autonomy lane-stop gate: you attempted to stop, but this lane's completion condition is not yet signaled. A lane that stops itself before its stated goal is met is a bug. Do NOT stop on a self-estimated context percentage, a turn count, or a vague sense that enough was done — none of those is completion. Either (1) continue working toward the lane's stated goal, or (2) if the goal is genuinely and verifiably met, declare completion by emitting the exact token ${SENTINEL} on its own line (or by creating the configured completion-marker file), then stop. This is your one automated nudge; if you stop again without signaling completion, the operator will be alerted that the lane went down."

emit_tel "blocked" "nudged" "none"
jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
