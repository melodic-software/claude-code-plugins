#!/usr/bin/env bash

set -uo pipefail
START=${EPOCHREALTIME:-}
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
case "$HOOK_DIR" in
/*) _gate_root="$HOOK_DIR/.." ;;
?:[/\\]*) _gate_root="${HOOK_DIR//\\//}/.." ;;
*) _gate_root=$(cd "$HOOK_DIR/.." 2>/dev/null && pwd) ;;
esac

gate_maybe_configured() {
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" ]] && return 0
  [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" ]] && return 0
  local rest marketplace name primary f
  if [[ -n "$_gate_root" && "$_gate_root" == */plugins/cache/*/*/* ]]; then
    rest="${_gate_root#*/plugins/cache/}"
    marketplace="${rest%%/*}"
    rest="${rest#*/}"
    name="${rest%%/*}"
    if [[ -n "$marketplace" && -n "$name" ]]; then
      f="${_gate_root%%/plugins/cache/*}/settings.json"
      [[ -f "$f" ]] && gate_file_mentions "$f" && return 0
    fi
  fi
  for primary in "/Library/Application Support/ClaudeCode/managed-settings.json" \
    "C:/Program Files/ClaudeCode/managed-settings.json" \
    "/etc/claude-code/managed-settings.json"; do
    [[ -f "$primary" ]] && gate_file_mentions "$primary" && return 0
    for f in "${primary%/*}/managed-settings.d"/*.json; do
      [[ -f "$f" ]] && gate_file_mentions "$f" && return 0
    done
  done
  return 1
}
gate_file_mentions() {
  local chunk=""
  while IFS= read -r -d '' chunk || [[ -n "$chunk" ]]; do
    [[ "$chunk" == *lane_stop_gate* ]] && return 0
  done 2>/dev/null <"$1"
  return 1
}
gate_maybe_configured || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=lane-notify.sh
source "$HOOK_DIR/lane-notify.sh"
# shellcheck source=lane-stop-gate-lib.sh
source "$HOOK_DIR/lane-stop-gate-lib.sh"
gate_resolve_anchor "$_gate_root" || true
[[ -n "$GATE_CONFIG_ROOT" ]] || gate_resolve_plugin_name "$_gate_root" || true

emit_tel() {
  local data='{"outcome":"'"$2"'","signal":"'"$3"'"}'
  hook::emit_telemetry "lane-stop-gate" "Stop" "$1" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

hook::buffer_stdin_to INPUT || exit 0

if ! command -v jq >/dev/null 2>&1; then
  # shellcheck disable=SC2034 # the model text is filled and dropped: user only on Stop
  JQ_MODEL="" JQ_USER=""
  if hook::prereq_notice_to JQ_MODEL JQ_USER jq "$INPUT" --label autonomy --no-path; then
    hook::emit_skip_notice "Stop" "" "$JQ_USER"
  fi
  exit 0
fi

chomp_nl() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
strip_cr() {
  local __v="${!1}"
  __v="${__v//$'\r'/}"
  printf -v "$1" '%s' "$__v"
}
GATE_PAYLOAD_FIELDS=()
{
  while IFS= read -r -d '' _gate_pf; do
    GATE_PAYLOAD_FIELDS+=("$_gate_pf")
  done < <(printf '%s' "$INPUT" | jq -j '
    [ (.hook_event_name // "" | tostring),
      (.session_id // "" | tostring),
      (.cwd // "" | tostring),
      (.stop_hook_active // false | tostring),
      (.last_assistant_message // "" | tostring)
    ] | map(split("\u0000") | join("")) | .[] | (., ([0] | implode))')
} 2>/dev/null
unset -v _gate_pf
EVENT="${GATE_PAYLOAD_FIELDS[0]-}"
SESSION_ID="${GATE_PAYLOAD_FIELDS[1]-}"
CWD="${GATE_PAYLOAD_FIELDS[2]-}"
STOP_ACTIVE="${GATE_PAYLOAD_FIELDS[3]-}"
LAST="${GATE_PAYLOAD_FIELDS[4]-}"
for _gate_field in EVENT SESSION_ID CWD STOP_ACTIVE; do
  strip_cr "$_gate_field"
  chomp_nl "$_gate_field"
done
unset -v _gate_field
chomp_nl LAST

[[ "$EVENT" == "Stop" ]] || exit 0

GATE_ARM_TTL_SECONDS=$((GATE_ARM_TTL_DAYS * 86400))
GATE_ARM_JSON=""

gate_arm_owned() {
  local claim="$1" me="${SESSION_ID//[$'\r\n']/}" owner=""
  [[ ! -e "$claim" || (-f "$claim" && ! -L "$claim") ]] || return 0
  if [[ -n "$me" ]] && (
    umask 077
    set -o noclobber
    printf '%s\n' "$me" >"$claim"
  ) 2>/dev/null; then
    return 0
  fi
  [[ -e "$claim" ]] || return 0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    IFS= read -r owner <"$claim" 2>/dev/null || true
    [[ -n "$owner" ]] && break
    sleep 0.02 2>/dev/null || true
  done
  [[ -n "$owner" ]] || return 0
  [[ -n "$me" && "$owner" == "$me" ]]
}

GATE_ARM_OPT_HAVE=(0 0 0)
GATE_ARM_OPT_VALUE=("" "" "")
gate_load_arm_record() {
  local id="${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" rec claim armed_at now claimed f i
  local -a fields=()
  [[ -n "$id" ]] || return 1
  gate_arm_record_path_to rec "$id" || return 1
  gate_arm_claim_path_to claim "$id" || return 1
  [[ -f "$rec" ]] || return 1
  {
    while IFS= read -r -d '' f; do
      chomp_nl f
      fields+=("$f")
    done < <(jq -j '
      [ (.armed_at // "" | tostring),
        (.session_id // "" | tostring),
        (.sentinel | if type == "string" then "v:" + . else "-" end),
        (.marker | if type == "string" then "v:" + . else "-" end),
        tojson ] | .[] | (., ([0] | implode))')
  } 2>/dev/null <"$rec"
  ((${#fields[@]} == 5)) || return 1
  armed_at="${fields[0]}"
  [[ "$armed_at" =~ ^[0-9]+$ ]] || return 1
  gate_epoch_seconds_to now
  if [[ -n "$now" ]] && ((now - armed_at > GATE_ARM_TTL_SECONDS)); then
    rm -f -- "$rec" "$claim" 2>/dev/null
    return 1
  fi
  claimed="${fields[1]}"
  if [[ -n "$claimed" ]]; then
    [[ -n "$SESSION_ID" && "$claimed" == "$SESSION_ID" ]] || return 1
  else
    gate_arm_owned "$claim" || return 1
  fi
  for i in 1 2; do
    [[ "${fields[i + 1]}" == v:* ]] || continue
    GATE_ARM_OPT_HAVE[i]=1
    GATE_ARM_OPT_VALUE[i]="${fields[i + 1]#v:}"
  done
  GATE_ARM_JSON="${fields[4]}"
}
gate_load_arm_record || true

GATE_OPTION_KEYS=(lane_stop_gate_enabled lane_stop_gate_sentinel lane_stop_gate_marker)
GATE_MANAGED_RESOLVED=0
GATE_USER_RESOLVED=0
GATE_USER_OPT_HAVE=(0 0 0)
GATE_USER_OPT_VALUE=("" "" "")
gate_option_to() {
  local __dest="$1" key="$2" i idx=-1 uf
  for i in "${!GATE_OPTION_KEYS[@]}"; do
    [[ "${GATE_OPTION_KEYS[i]}" == "$key" ]] && idx=$i
  done
  ((idx >= 0)) || return 1
  if ((!GATE_MANAGED_RESOLVED)); then
    GATE_MANAGED_RESOLVED=1
    gate_managed_options_to "${GATE_OPTION_KEYS[@]}" || true
  fi
  if ((GATE_MANAGED_OPT_HAVE[idx])); then
    printf -v "$__dest" '%s' "${GATE_MANAGED_OPT_VALUE[idx]}"
    return 0
  fi
  if [[ -n "$GATE_ARM_JSON" ]]; then
    if [[ "$key" == "lane_stop_gate_enabled" ]]; then
      printf -v "$__dest" 'true'
      return 0
    fi
    if ((GATE_ARM_OPT_HAVE[idx])); then
      printf -v "$__dest" '%s' "${GATE_ARM_OPT_VALUE[idx]}"
      return 0
    fi
  fi
  if ((!GATE_USER_RESOLVED)); then
    GATE_USER_RESOLVED=1
    if gate_user_settings_file_to uf && gate_settings_options_to "$uf" "${GATE_OPTION_KEYS[@]}"; then
      GATE_USER_OPT_HAVE=("${GATE_FILE_OPT_HAVE[@]}")
      GATE_USER_OPT_VALUE=("${GATE_FILE_OPT_VALUE[@]}")
    fi
  fi
  ((GATE_USER_OPT_HAVE[idx])) || return 1
  printf -v "$__dest" '%s' "${GATE_USER_OPT_VALUE[idx]}"
}

gate_option_to ENABLED lane_stop_gate_enabled || ENABLED=""
if [[ "$ENABLED" != "true" ]]; then
  if [[ -z "$ENABLED" ]]; then
    if [[ -n "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID:-}" && -z "$GATE_ARM_JSON" ]]; then
      if hook::notice_once "autonomy-lane-stop-gate-stale-arm" "$INPUT"; then
        hook::emit_skip_notice "Stop" "" \
          "autonomy: lane-stop gate off: no matching arm record (expired, claimed by another session, or cleaned up). Relaunch the lane through the harness-ops lane launcher."
      fi
    elif [[ "${CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED:-}" == "true" ]]; then
      if hook::notice_once "autonomy-lane-stop-gate-untrusted-enable" "$INPUT"; then
        hook::emit_skip_notice "Stop" "" \
          "autonomy: lane-stop gate off: enabled only on the environment channel, which it does not trust. Launch the lane through the harness-ops lane launcher."
      fi
    fi
  fi
  exit 0
fi

SIGNALED=0
SIGNAL="none"

gate_option_to SENTINEL lane_stop_gate_sentinel || SENTINEL=""
[[ -n "$SENTINEL" ]] || SENTINEL="LANE-STOP-OK"
SENTINEL_RE=""
for ((i = 0; i < ${#SENTINEL}; i++)); do
  c="${SENTINEL:i:1}"
  case "$c" in
  '[' | ']' | "\\" | '.' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '{' | '}' | '|' | '/') SENTINEL_RE+="\\$c" ;;
  *) SENTINEL_RE+="$c" ;;
  esac
done
SENTINEL_LINE_RE="(^|"$'\n'")[[:space:]]*${SENTINEL_RE}[[:space:]]*("$'\n'"|\$)"
if [[ "$LAST" =~ $SENTINEL_LINE_RE ]]; then
  SIGNALED=1
  SIGNAL="sentinel"
fi

marker_identity_to() {
  local __id=""
  # portability-ok: GNU-first of a dual-dialect ladder — the BSD `-f` spelling is
  # the next alternative, and a host with neither returns the empty identity this
  # function documents (#1784)
  { __id=$(stat -c '%Y %s' -- "$2"); } 2>/dev/null ||
    # portability-ok: BSD ladder rung paired with GNU `stat -c` above (#1784)
    { __id=$(stat -f '%m %z' -- "$2"); } 2>/dev/null ||
    __id=""
  printf -v "$1" '%s' "$__id"
}

marker_ledger_path_to() {
  local dir key
  gate_data_dir_to dir
  [[ -n "$dir" ]] || return 1
  { key=$(cksum); } < <(printf '%s' "$2") 2>/dev/null || return 1
  key="${key//[^[:digit:]]/}"
  [[ -n "$key" ]] || return 1
  printf -v "$1" '%s/consumed-markers/%s' "$dir" "$key"
}

marker_already_consumed() {
  local path="$1" ledger recorded_path="" recorded_id="" current
  marker_ledger_path_to ledger "$path" || return 1
  [[ -f "$ledger" ]] || return 1
  { IFS= read -r recorded_path && IFS= read -r recorded_id; } <"$ledger" 2>/dev/null
  [[ "$recorded_path" == "$path" ]] || return 1
  marker_identity_to current "$path"
  if [[ -n "$current" && -n "$recorded_id" && "$current" != "$recorded_id" ]]; then
    rm -f -- "$ledger" 2>/dev/null
    return 1
  fi
  return 0
}

marker_record_consumed() {
  local path="$1" ledger identity
  marker_ledger_path_to ledger "$path" || return 0
  mkdir -p -- "${ledger%/*}" 2>/dev/null || return 0
  marker_identity_to identity "$path"
  printf '%s\n%s\n' "$path" "$identity" >"$ledger" 2>/dev/null || true
}

gate_option_to MARKER lane_stop_gate_marker || MARKER=""
if [[ "$SIGNALED" -eq 0 && -n "$MARKER" ]]; then
  case "$MARKER" in
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    [[ -n "$CWD" ]] && MARKER="${CWD%/}/$MARKER"
    ;;
  esac
  if [[ -f "$MARKER" ]] && ! marker_already_consumed "$MARKER"; then
    SIGNALED=1
    SIGNAL="marker"
    rm -f -- "$MARKER" 2>/dev/null || true
    [[ -e "$MARKER" ]] && marker_record_consumed "$MARKER"
  fi
fi

if [[ "$SIGNALED" -eq 1 ]]; then
  emit_tel "ok" "completion-signaled" "$SIGNAL"
  exit 0
fi

if [[ "$STOP_ACTIVE" == "true" ]]; then
  BRANCH=""
  if [[ -n "$CWD" ]]; then
    { BRANCH=$(hook::git_untrusted -C "$CWD" branch --show-current); } 2>/dev/null || BRANCH=""
    BRANCH="${BRANCH//[[:cntrl:]]/}"
  fi
  LANE="${CWD##*/}"
  [[ -n "$BRANCH" ]] && LANE="$LANE ($BRANCH)"
  [[ -n "$LANE" ]] || LANE="unknown"
  lane::notify "Autonomy lane stopped" \
    "Lane $LANE stopped without signaling completion — it may be down, stuck, or waiting on you. Check it."
  emit_tel "ok" "stopped-after-nudge" "none"
  exit 0
fi

REASON="Lane-stop gate: this lane's completion is not signaled. A context estimate, turn count, status summary, offer to continue or a sense that enough was done is not completion; put status in the same message as your next action. Continue toward the lane's goal. If the goal is verifiably met, print ${SENTINEL} on its own line (or create the completion-marker file), then stop. If you need the operator, or the next step is destructive, irreversible or outward-facing and the lane prompt does not authorize it, say what blocks you and stop without the token; do not take that step. A second unsignaled stop alerts the operator."

emit_tel "blocked" "nudged" "none"
jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
