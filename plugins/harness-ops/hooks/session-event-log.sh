#!/usr/bin/env bash
# Per-session hook event log: one JSON line per hook event, appended to
# <root>/sessions/<session_id>.jsonl (root defaults to .observability/claude,
# project-relative). The plugin's hooks module (register.ts) runs it through
# exec-bash.mjs on every documented event the generated registry marks
# observable (plugins/harness-ops/hooks/hook-events.registry.json), with the
# event's payload on stdin and the plugin's options as CLAUDE_PLUGIN_OPTION_*.
#
# DEFAULT OFF. With the option off the module hooks nothing, so this script
# never starts. The read below is what a direct invocation pays: no library is
# sourced and stdin is not read until it says so.
#
# This script sources session-log-lib.sh (a few functions, no process) and
# NOT hook-utils.sh: a producer that fires on every event cannot afford the
# 2,766-line library, which measured at more than the rest of the hook.
# What it gives up is the
# library's notice channel, so its quiet exits are data-driven (no session id,
# a filtered category, an uncontained root) and never a missing prerequisite:
# it needs no jq and no git.
#
# Every line is one hook event record in the key set session-log-lib.sh
# documents and formats (slog_event_record_to): the spine, `category`,
# `effort`, and whichever correlation keys the payload carries (prompt_id,
# tool_use_id, agent_id, traceparent) plus, for events that carry a decision or
# a change, a small payload (tool_name, file_path, reason), and the top-level
# metadata keys session-log-lib.sh allowlists. Strings pass as the payload's
# own JSON string bodies, re-emitted verbatim, so no escaping is re-derived
# here; ids are constrained to file-name-safe characters because session_id
# names the file.
#
# stdin is read in bounded slices the way hook::buffer_stdin does, without
# sourcing it: a Win32 pipe delivers EOF late, so a read that waits for EOF
# waits out its timeout on every event. Only the first 64 KB matter (every
# spine key precedes tool_input in the payload), so the read stops at that cap,
# at EOF, at a `}` tail after a quiet slice, or after one whole idle bound.
#
# Kill switch: CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED (default false).
# Category filter: CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES.
# Root: CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR (default .observability/claude).
# Content fields: CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT (default false).

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0

start=${EPOCHREALTIME:-}

# With content fields on, the 64 KB read cap and every length below count
# bytes: under a UTF-8 locale `read -N` and `${#}` count characters, and a
# multibyte prompt would pass the cap several times over. Off, rows carry no
# content and the read is left as it was.
content=false
[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT:-false}" == "true" ]] && content=true && LC_ALL=C

# shellcheck source=session-log-lib.sh
source "${BASH_SOURCE[0]%/*}/session-log-lib.sh"

# --- bounded stdin read -------------------------------------------------------
# The same rejection rules hook::resolve_read_timeout_to applies to this
# variable, restated because this producer does not source the library. An
# unusable value is a silent disable, not a tuning mistake: `read -t 0`
# returns at once having consumed nothing, a fractional value is a usage error
# on a Bash before 4.0 (integer-only -t), and a positive value under 10 µs
# returns before the payload's bytes arrive. Each falls back to the default.
idle="${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}"
if ! [[ "$idle" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$idle" =~ ^0+(\.0+)?$ ]] ||
  { [[ "$idle" == *.* ]] && ((BASH_VERSINFO[0] < 4)); }; then
  idle=2
elif [[ "$idle" =~ ^([0-9]+)(\.([0-9]+))?$ ]]; then
  whole="${BASH_REMATCH[1]}"
  frac="${BASH_REMATCH[3]:-}000000"
  ((10#$whole * 1000000 + 10#${frac:0:6} < 10)) && idle=2
fi
# Four slices per idle bound when this shell takes a fractional -t (Bash 4+),
# so a stall is declared within a quarter-bound of the configured interval; one
# whole-bound slice otherwise.
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
  ((rc > 128)) || break # EOF (rc 1) or a read error: what we hold is what there is
  if [[ -n "$chunk" ]]; then
    quiet=0
    # A slice that timed out holding data is the late-EOF shape: the payload
    # is here and the pipe is not closing. Stop early only when what we hold
    # looks like the WHOLE payload: it ends in `}`, it carries the event name
    # (the key every fire must have), and its braces balance. A writer that
    # paused after a nested `}` (tool_input closed, tool_use_id still to come)
    # fails the balance test and the loop keeps reading to the idle bound; a
    # brace inside a string can only delay the stop, never force it early on
    # its own.
    tail="${buf##*[![:space:]]}"
    body="${buf%"$tail"}"
    if [[ "$body" == *'}' && "$buf" == *'"hook_event_name"'* ]]; then
      # The brace characters come from variables: a literal `}` inside the
      # bracket class ends the `${...}` expansion early (bash parses the
      # expansion's closing brace before the pattern), so `[^}]` written out
      # is not the class it looks like.
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

# --- spine and payload ----------------------------------------------------------
# First match wins; every spine key is a top-level key that precedes tool_input,
# so it is found before any user content could carry the same text.
# shellcheck disable=SC2034  # the payload keys are read through ${!key} below
session_id="" event="" prompt_id="" tool_use_id="" agent_id="" tool_name=""
# shellcheck disable=SC2034
file_path="" reason="" cwd="" category="" root="" ts="" duration_ms="" line=""
field_to() { # <var> <key> [<haystack var>]: the JSON string body of "<key>": "..." or ""
  local field__in="$buf"
  (($# > 2)) && field__in="${!3}"
  if [[ "$field__in" =~ \"$2\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
    printf -v "$1" '%s' "${BASH_REMATCH[1]}"
  else
    printf -v "$1" '%s' ""
  fi
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

# --- top-level metadata and effort ----------------------------------------------
# The allowlisted keys and `effort` are read only from the payload's top-level
# members: inside tool_input, tool_calls, background_tasks or an elicitation's
# content, a key of the same name holds content or another object's value.
# `top` is the run of scalar members (and the flat effort object) from the
# opening brace up to the first nested value, plus the run of scalar members
# after the last one up to the closing brace. A member inside a nested value
# is in neither run: the nested value's own `}` or `]` breaks both. Each run is
# one anchored regex, so the 64 KB read cap bounds the work.
str='"([^"\\]|\\.)*"'
num='-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?'
effort_obj='"effort"[[:space:]]*:[[:space:]]*\{[[:space:]]*"level"[[:space:]]*:[[:space:]]*'"$str"'[[:space:]]*\}'
member="[[:space:]]*(${str}[[:space:]]*:[[:space:]]*($str|$num|true|false|null)|$effort_obj)[[:space:]]*"
top=""
lead=0
[[ "$buf" =~ ^[[:space:]]*\{(($member,)*) ]] && top="${BASH_REMATCH[1]}" && lead=${#BASH_REMATCH[0]}
[[ "$buf" =~ ((,$member)*)\}[[:space:]]*$ ]] && top+="${BASH_REMATCH[1]}"

# effort (D33): an event in SLOG_EFFORT_NA_EVENTS never carries a level, so
# `n/a`. Otherwise the payload's top-level effort.level, accepted when the
# payload holds that one "effort" object; Claude Code sets a hook's
# $CLAUDE_EFFORT from that same field, so the payload wins over a value the
# hook merely inherited. $CLAUDE_EFFORT fills in only when the payload has no
# effort object; else `unset`.
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

# scalar_to <var> <key>: the JSON boolean or number of a top-level "<key>", or "".
scalar_to() {
  if [[ "$top" =~ \"$2\"[[:space:]]*:[[:space:]]*(true|false|-?[0-9]+(\.[0-9]+)?)[[:space:]]*(,|$) ]]; then
    printf -v "$1" '%s' "${BASH_REMATCH[1]}"
  else
    printf -v "$1" '%s' ""
  fi
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

# --- content (session_event_log_content, default off) ----------------------------
# The top-level content strings in SLOG_EVENT_LOG_CONTENT, recorded only when
# the option is exactly true. `error` is tool
# output on PostToolUseFailure; on StopFailure it is the metadata enum above.
# A content string still open where the 64 KB read cap fell is the member right
# after the leading scalar run: its captured prefix is cut back to whole JSON
# escapes and whole UTF-8 characters and recorded with `<key>_truncated: true`.
# Only that position is provably top-level in a cut buffer; a field the cap
# fell inside after a nested value is not recorded. Any row whose payload hit
# the cap carries `content_truncated: true`, so a dropped field is never silent.
if [[ "$content" == true ]]; then
  open_key="" open_val=""
  if [[ "${buf:lead}" =~ ^[[:space:]]*\"([a-z_]+)\"[[:space:]]*:[[:space:]]*\"(.*)$ ]]; then
    open_key="${BASH_REMATCH[1]}"
    open_val="${BASH_REMATCH[2]}"
    if [[ "$open_val" =~ ^(([^\"\\]|\\[^u]|\\u[0-9A-Fa-f]{4})*)\\?(u[0-9A-Fa-f]{0,3})?$ ]]; then
      open_val="${BASH_REMATCH[1]}"
      # A UTF-8 lead byte whose continuation bytes were cut off, matched byte
      # by byte under the byte locale set above (the regex has to sit in a
      # variable: quoted text in `=~` is literal).
      cut_char=$'([\xc2-\xdf]|[\xe0-\xef][\x80-\xbf]?|[\xf0-\xf4][\x80-\xbf]{0,2})$'
      [[ "$open_val" =~ $cut_char ]] && open_val="${open_val:0:${#open_val}-${#BASH_REMATCH[1]}}"
    else
      open_key="" # the string closes: a whole member, read from `top` below
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

# --- root and guard ------------------------------------------------------------
project="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$project" ]] || project="$cwd"
[[ -n "$project" ]] || exit 0
slog_root_to root "$project"
[[ -n "$root" ]] || exit 0
slog_guard_ok "$root" "$project" || exit 0
[[ -d "$root/sessions" ]] || mkdir -p "$root/sessions" 2>/dev/null || exit 0

# --- the line -------------------------------------------------------------------
# A file path is recorded repo-relative when it sits under the project, else
# by its last segment, so the record does not say where else on the machine
# the session read or wrote. The session's own location keys (cwd,
# transcript_path, scratchpad_dir and the other allowlisted paths) are recorded
# as the payload's raw absolute values.
if [[ -n "$file_path" ]]; then
  if [[ "$file_path" == "$project/"* ]]; then
    file_path="${file_path#"$project"/}"
  else
    # Last segment after either separator: a Windows path arrives with `\\`
    # (JSON-escaped backslashes) and no `/` at all, and stripping on `/` alone
    # would keep the whole path, username included.
    file_path="${file_path##*[/\\]}"
  fi
fi
slog_ts_to ts
slog_duration_ms_to duration_ms "$start"
# `category` and the ids are drawn from validated vocabularies, so they pass as
# decoded strings; tool_name, file_path and reason are the payload's own JSON
# string bodies and pass as bodies (type `b`), which is what keeps this hook
# from re-deriving an escape it has no jq to check.
extras=(category s "$category" effort s "$effort")
for key in prompt_id tool_use_id agent_id tool_name file_path reason; do
  [[ -n "${!key}" ]] || continue
  if [[ "$key" == prompt_id || "$key" == tool_use_id || "$key" == agent_id ]]; then
    slog_valid_id "${!key}" || continue
    extras+=("$key" s "${!key}")
  else
    extras+=("$key" b "${!key}")
  fi
done
[[ -n "${TRACEPARENT:-}" && "$TRACEPARENT" =~ ^[0-9a-f-]+$ ]] && extras+=(traceparent s "$TRACEPARENT")
extras+=(${meta[@]+"${meta[@]}"})
slog_event_record_to line event-log "$ts" "$session_id" "$event" ok "$duration_ms" "${extras[@]}"

# With content on, every row takes the lock (see slog_append).
lock=""
[[ "$content" == true ]] && lock=lock
slog_append "$root/sessions/$session_id.jsonl" "$line" "$lock"
exit 0
