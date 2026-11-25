#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0

start=${EPOCHREALTIME:-}

content=false
[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT:-false}" == "true" ]] && content=true && LC_ALL=C

# shellcheck source=session-log-lib.sh
source "${BASH_SOURCE[0]%/*}/session-log-lib.sh"

idle="${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}"
if ! [[ "$idle" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$idle" =~ ^0+(\.0+)?$ ]] ||
  { [[ "$idle" == *.* ]] && ((BASH_VERSINFO[0] < 4)); }; then
  idle=2
elif [[ "$idle" =~ ^([0-9]+)(\.([0-9]+))?$ ]]; then
  whole="${BASH_REMATCH[1]}"
  frac="${BASH_REMATCH[3]:-}000000"
  ((10#$whole * 1000000 + 10#${frac:0:6} < 10)) && idle=2
fi
slices=1
slice="$idle"
if ((BASH_VERSINFO[0] >= 4)); then
  whole="${idle%%.*}"
  frac="${idle#"$whole"}"
  frac="${frac#.}000"
  micros=$((10#$whole * 1000 + 10#${frac:0:3}))
  if ((micros >= 4)); then
    printf -v slice '%d.%03d' "$((micros / 4 / 1000))" "$((micros / 4 % 1000))"
    slices=4
  fi
fi
read_opts=(-r -t "$slice")
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
  read_opts+=(-N 4096)
else
  read_opts+=(-d '')
fi
buf=""
quiet=0
while :; do
  chunk=""
  rc=0
  # shellcheck disable=SC2162 # -r is in read_opts
  IFS= read "${read_opts[@]}" chunk || rc=$?
  buf+="$chunk"
  ((${#buf} >= 65536)) && break
  if ((rc == 0)); then
    [[ -n "$chunk" ]] || break
    quiet=0
    continue
  fi
  ((rc > 128)) || break
  if [[ -n "$chunk" ]]; then
    quiet=0
    tail="${buf##*[![:space:]]}"
    body="${buf%"$tail"}"
    if [[ "$body" == *'}' && "$buf" == *'"hook_event_name"'* ]]; then
      ob='{'
      cb='}'
      open="${body//[^$ob]/}"
      close="${body//[^$cb]/}"
      ((${#open} == ${#close})) && break
    fi
    continue
  fi
  quiet=$((quiet + 1))
  ((quiet >= slices)) && break
done
[[ -n "$buf" ]] || exit 0

# shellcheck disable=SC2034  # the payload keys are read through ${!key} below
session_id="" event="" prompt_id="" tool_use_id="" agent_id="" tool_name=""
# shellcheck disable=SC2034
file_path="" reason="" cwd="" category="" root="" ts="" duration_ms="" line=""
field_to() {
  local field__in="$buf"
  (($# > 2)) && field__in="${!3}"
  printf -v "$1" '%s' ""
  [[ "$field__in" =~ \"$2\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
  return 0
}
field_to session_id session_id
field_to event hook_event_name
[[ -n "$session_id" && -n "$event" ]] || exit 0
slog_valid_id "$session_id" || exit 0
[[ "$event" =~ ^[A-Za-z]+$ ]] || exit 0

slog_category_to category "$event"
slog_category_enabled "$category" || exit 0

field_to prompt_id prompt_id
field_to tool_use_id tool_use_id
field_to agent_id agent_id
field_to tool_name tool_name
field_to file_path file_path
field_to reason reason
field_to cwd cwd

str='"([^"\\]|\\.)*"'
num='-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?'
effort_obj='"effort"[[:space:]]*:[[:space:]]*\{[[:space:]]*"level"[[:space:]]*:[[:space:]]*'"$str"'[[:space:]]*\}'
member="[[:space:]]*(${str}[[:space:]]*:[[:space:]]*($str|$num|true|false|null)|$effort_obj)[[:space:]]*"
top=""
lead=0
[[ "$buf" =~ ^[[:space:]]*\{(($member,)*) ]] && top="${BASH_REMATCH[1]}" && lead=${#BASH_REMATCH[0]}
[[ "$buf" =~ ((,$member)*)\}[[:space:]]*$ ]] && top+="${BASH_REMATCH[1]}"

effort="unset"
levels=" low medium high xhigh max "
if [[ " $SLOG_EFFORT_NA_EVENTS " == *" $event "* ]]; then
  effort=n/a
elif [[ "$top" =~ \"effort\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"level\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]]; then
  level="${BASH_REMATCH[1]}"
  if [[ "$levels" == *" $level "* ]] &&
    ! [[ "$buf" =~ \"effort\"[[:space:]]*:[[:space:]]*\{.*\"effort\"[[:space:]]*:[[:space:]]*\{ ]]; then
    effort="$level"
  fi
elif [[ -n "${CLAUDE_EFFORT:-}" && "$levels" == *" $CLAUDE_EFFORT "* ]]; then
  effort="$CLAUDE_EFFORT"
fi

scalar_to() {
  printf -v "$1" '%s' ""
  [[ "$top" =~ \"$2\"[[:space:]]*:[[:space:]]*(true|false|-?[0-9]+(\.[0-9]+)?)[[:space:]]*(,|$) ]] && printf -v "$1" '%s' "${BASH_REMATCH[1]}"
  return 0
}
meta=()
for entry in $SLOG_EVENT_LOG_STRINGS; do
  key="${entry%@*}"
  [[ "$entry" == "$key" || "${entry#*@}" == "$event" ]] || continue
  [[ "$top" == *"\"$key\""* ]] || continue
  field_to value "$key" top
  [[ -n "$value" ]] && meta+=("$key" b "$value")
done
for key in $SLOG_EVENT_LOG_SCALARS; do
  [[ "$top" == *"\"$key\""* ]] || continue
  scalar_to value "$key"
  [[ -n "$value" ]] && meta+=("$key" n "$value")
done

if [[ "$content" == true ]]; then
  open_key="" open_val=""
  if [[ "${buf:lead}" =~ ^[[:space:]]*\"([a-z_]+)\"[[:space:]]*:[[:space:]]*\"(.*)$ ]]; then
    open_key="${BASH_REMATCH[1]}"
    open_val="${BASH_REMATCH[2]}"
    if [[ "$open_val" =~ ^(([^\"\\]|\\[^u]|\\u[0-9A-Fa-f]{4})*)\\?(u[0-9A-Fa-f]{0,3})?$ ]]; then
      open_val="${BASH_REMATCH[1]}"
      cut_char=$'([\xc2-\xdf]|[\xe0-\xef][\x80-\xbf]?|[\xf0-\xf4][\x80-\xbf]{0,2})$'
      [[ "$open_val" =~ $cut_char ]] && open_val="${open_val:0:${#open_val}-${#BASH_REMATCH[1]}}"
    else
      open_key=""
    fi
  fi
  for entry in $SLOG_EVENT_LOG_CONTENT; do
    key="${entry%@*}"
    [[ "$entry" == "$key" || "${entry#*@}" == "$event" ]] || continue
    if [[ "$key" == "$open_key" ]]; then
      meta+=("$key" b "$open_val" "${key}_truncated" n true)
      continue
    fi
    [[ "$top" == *"\"$key\""* ]] || continue
    field_to value "$key" top
    [[ -n "$value" ]] && meta+=("$key" b "$value")
  done
  ((${#buf} >= 65536)) && meta+=(content_truncated n true)
fi

project="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$project" ]] || project="$cwd"
[[ -n "$project" ]] || exit 0
slog_root_to root "$project"
[[ -n "$root" ]] || exit 0
slog_guard_ok "$root" "$project" || exit 0
[[ -d "$root/sessions" ]] || mkdir -p "$root/sessions" 2>/dev/null || exit 0

if [[ -n "$file_path" ]]; then
  if [[ "$file_path" == "$project/"* ]]; then
    file_path="${file_path#"$project"/}"
  else
    file_path="${file_path##*[/\\]}"
  fi
fi
slog_ts_to ts
slog_duration_ms_to duration_ms "$start"
extras=(category s "$category" effort s "$effort")
for key in prompt_id tool_use_id agent_id; do
  [[ -n "${!key}" ]] && slog_valid_id "${!key}" && extras+=("$key" s "${!key}")
done
for key in tool_name file_path reason; do
  [[ -n "${!key}" ]] && extras+=("$key" b "${!key}")
done
[[ -n "${TRACEPARENT:-}" && "$TRACEPARENT" =~ ^[0-9a-f-]+$ ]] && extras+=(traceparent s "$TRACEPARENT")
extras+=(${meta[@]+"${meta[@]}"})
slog_event_record_to line event-log "$ts" "$session_id" "$event" ok "$duration_ms" "${extras[@]}"

lock=""
[[ "$content" == true ]] && lock=lock
slog_append "$root/sessions/$session_id.jsonl" "$line" "$lock"
exit 0
