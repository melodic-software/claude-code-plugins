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
#   - the existence of the marker file named by lane_stop_gate_marker.
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

# Has completion been explicitly signaled?
SIGNALED=0

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
  if printf '%s' "$LAST" | grep -qE "^[[:space:]]*${SENTINEL_RE}[[:space:]]*$"; then
    SIGNALED=1
  fi
fi

# Signal 2 — the completion-marker file. Absolute path used as-is; a relative
# path resolves against the session cwd from the payload.
MARKER="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER:-}"
if [[ "$SIGNALED" -eq 0 && -n "$MARKER" ]]; then
  case "$MARKER" in
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')
    [[ -n "$CWD" ]] && MARKER="${CWD%/}/$MARKER"
    ;;
  esac
  [[ -f "$MARKER" ]] && SIGNALED=1
fi

# Completion signaled → this is a legitimate stop. Allow it, silently.
if [[ "$SIGNALED" -eq 1 ]]; then
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
  exit 0
fi

# First stop attempt without a completion signal → block once and re-inject the
# completion self-check. This directly counters the fabricated-context-percentage
# premature-stop failure (#576/#577): a self-estimated "~50% context" is not a
# completion condition. Emitted as the documented Stop stdout decision.
REASON="Autonomy lane-stop gate: you attempted to stop, but this lane's completion condition is not yet signaled. A lane that stops itself before its stated goal is met is a bug. Do NOT stop on a self-estimated context percentage, a turn count, or a vague sense that enough was done — none of those is completion. Either (1) continue working toward the lane's stated goal, or (2) if the goal is genuinely and verifiably met, declare completion by emitting the exact token ${SENTINEL} on its own line (or by creating the configured completion-marker file), then stop. This is your one automated nudge; if you stop again without signaling completion, the operator will be alerted that the lane went down."

jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
