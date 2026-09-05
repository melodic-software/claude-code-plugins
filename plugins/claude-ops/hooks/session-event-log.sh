#!/usr/bin/env bash
# Per-session hook event log: one JSON line per hook event, appended to
# <root>/sessions/<session_id>.jsonl (root defaults to .observability/claude,
# project-relative). Registered on every documented event the generated
# registry marks observable (plugins/claude-ops/hooks/hook-events.registry.json;
# scripts/gen-hook-event-registry.sh writes the hooks.json rows).
#
# DEFAULT OFF. A consumer who has not set session_event_log_enabled pays the
# kill-switch read below and nothing else: no library is sourced and stdin is
# not read until the switch says so.
#
# This script sources session-log-lib.sh (a few functions, no process) and
# NOT hook-utils.sh: a producer that fires on every event cannot afford the
# 2,766-line library, which measured at more than the rest of the hook
# (docs/topics/hook-logging-pipeline, Brief Q15). What it gives up is the
# library's notice channel, so its quiet exits are data-driven (no session id,
# a filtered category, an uncontained root) and never a missing prerequisite:
# it needs no jq and no git.
#
# Every line carries the spine (ts, session_id, hook_event_name, status,
# duration_ms, source) plus whichever correlation keys the payload carries
# (prompt_id, tool_use_id, agent_id, traceparent) and, for events that carry a
# decision or a change, a small payload (tool_name, file_path, reason). Values
# are the payload's own JSON string bodies, re-emitted verbatim, so no escaping
# is re-derived here; ids are constrained to file-name-safe characters because
# session_id names the file.
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

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0

start=${EPOCHREALTIME:-}

# shellcheck source=session-log-lib.sh
source "${BASH_SOURCE[0]%/*}/session-log-lib.sh"

# --- bounded stdin read -------------------------------------------------------
idle="${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}"
[[ "$idle" =~ ^[0-9]+(\.[0-9]+)?$ ]] || idle=2
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
    tail="${buf##*[![:space:]]}"
    [[ "${buf%"$tail"}" == *'}' ]] && break
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
file_path="" reason="" cwd="" category="" root="" ts="" duration_ms=""
field_to() { # <var> <key>: the JSON string body of "<key>": "..." or ""
  if [[ "$buf" =~ \"$2\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
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
# by its last segment: an absolute path embeds the developer's username, which
# the observability privacy rules keep out of every record.
if [[ -n "$file_path" ]]; then
  if [[ "$file_path" == "$project/"* ]]; then
    file_path="${file_path#"$project"/}"
  else
    file_path="${file_path##*/}"
  fi
fi
slog_ts_to ts
slog_duration_ms_to duration_ms "$start"
line="{\"ts\":\"$ts\",\"session_id\":\"$session_id\",\"hook_event_name\":\"$event\""
line+=",\"category\":\"$category\",\"status\":\"ok\",\"source\":\"event-log\""
line+=",\"duration_ms\":${duration_ms:-null}"
for key in prompt_id tool_use_id agent_id tool_name file_path reason; do
  [[ -n "${!key}" ]] || continue
  [[ "$key" == prompt_id || "$key" == tool_use_id || "$key" == agent_id ]] && ! slog_valid_id "${!key}" && continue
  line+=",\"$key\":\"${!key}\""
done
[[ -n "${TRACEPARENT:-}" && "$TRACEPARENT" =~ ^[0-9a-f-]+$ ]] && line+=",\"traceparent\":\"$TRACEPARENT\""
line+="}"

printf '%s\n' "$line" >>"$root/sessions/$session_id.jsonl" 2>/dev/null
exit 0
