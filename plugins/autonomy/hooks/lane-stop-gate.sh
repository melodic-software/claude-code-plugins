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
# DEFAULT-OFF. A Stop-blocking hook that engaged by default would wedge every
# interactive user's stop, so the gate is inert unless a lane explicitly opts in
# via lane_stop_gate_enabled=true (set by the lane launcher for that session, or
# configured on the plugin). Every other exit path allows the stop.
#
# FAIL-OPEN. Unlike a PreToolUse guard (which fails closed to deny), a Stop gate
# that fails closed would trap a lane it cannot evaluate. On unreadable stdin,
# missing jq, or a non-Stop event it allows the stop.
#
# Completion signal (either is sufficient, checked deterministically — a shell
# hook cannot re-run the /goal evaluator model):
#   - the exact sentinel token (default LANE-STOP-OK) in the agent's final
#     message, matched only when it stands alone on its own line, or
#   - the existence of the marker file named by lane_stop_gate_marker (consumed
#     on use, so a prior run's leftover marker never authorizes a later run).
#     Consumption is recorded in this plugin's own data directory, not carried
#     solely by the file's deletion: an `rm` the hook is not permitted to
#     perform must not leave a file a later run reads as a live signal.
#
# Config (userConfig mirror):
#   CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true    opt this session in (default false)
#   CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL=<tok>  completion token (default LANE-STOP-OK)
#   CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER=<path>   completion-marker file (absolute, or
#                                                       relative to the session cwd; default unset)

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=lane-notify.sh
source "$(dirname "${BASH_SOURCE[0]}")/lane-notify.sh"

# Default-OFF opt-in (NOT hook::check_enabled, which defaults ON when unset).
[[ "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-false}" == "true" ]] || exit 0

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

# jq parses the payload. Absent → visible once-per-session notice, then allow the
# stop (fail-open). Stop supports additionalContext, so the notice reaches both
# the agent and the user.
hook::require_jq "Stop" "autonomy-lane-stop-gate" "$INPUT"

# Fire ONLY on a true top-level session stop. A subagent finishing is delivered
# as SubagentStop; guarding on the event name keeps a Task-tool worker's normal
# completion from ever tripping the lane gate, whichever way the platform routes
# the registration.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null | tr -d '\r')
[[ "$EVENT" == "Stop" ]] || exit 0

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
SENTINEL="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL:-LANE-STOP-OK}"
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
# lives under this plugin's own data directory, which the hook does own.

# This plugin's persistent data directory, derived from the hook's OWN location
# first. Claude Code lays a marketplace plugin out at
# <plugins>/cache/<marketplace>/<name>/<version> and persists its data at
# <plugins>/data/<id>, where <id> is "<name>@<marketplace>" with every character
# outside [A-Za-z0-9_-] replaced by "-" (plugins reference, "Persistent data
# directory"). The script's own path is a thing a watched repository cannot
# redirect; CLAUDE_PLUGIN_DATA is an environment value a repo settings.json
# `env` block reaches, so it is only the fallback — for a --plugin-dir checkout
# install whose root carries no plugins/cache marker.
gate_data_dir() {
  local root rest marketplace name id
  root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd) || root=""
  if [[ -n "$root" && "$root" == */plugins/cache/*/*/* ]]; then
    rest="${root#*/plugins/cache/}"
    marketplace="${rest%%/*}"
    rest="${rest#*/}"
    name="${rest%%/*}"
    if [[ -n "$marketplace" && -n "$name" ]]; then
      id="${name}@${marketplace}"
      printf '%s/plugins/data/%s' "${root%%/plugins/cache/*}" "${id//[^A-Za-z0-9_-]/-}"
      return 0
    fi
  fi
  printf '%s' "${CLAUDE_PLUGIN_DATA:-}"
}

# Identity of the file currently at <path>, as "<mtime> <size>", or "" when this
# host's `stat` reports neither. A recreated marker gets a new identity, so a
# consumption record can be told apart from a genuinely fresh signal.
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
# twice). A record whose file has since been recreated is stale and removed, so
# the fresh marker authorizes normally.
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
MARKER="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER:-}"
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

# Completion signaled → this is a legitimate stop. Allow it, silently.
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
