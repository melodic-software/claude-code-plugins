#!/usr/bin/env bash
set -uo pipefail
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=session-log-lib.sh
source "$HOOK_DIR/session-log-lib.sh"
INPUT=$(cat)
[[ -n "$INPUT" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mapfile -t FIELDS < <(printf '%s' "$INPUT" | jq -r '
  if (.hook and .hook_event and (.duration_ms != null) and .status)
  then (.timestamp // ""), .hook_event, .hook, (.data.tool // ""),
       (.duration_ms | tostring), (.data.subject // .data.file // ""), .status,
       ((.session_id // .data.session_id // "") | tostring),
       (.data.changed | if . == true then "true" elif . == false then "false" else "" end)
  else empty end' 2>/dev/null | tr -d '\r')
[[ "${#FIELDS[@]}" -eq 9 ]] || exit 0

TS="${FIELDS[0]}"
EVENT="${FIELDS[1]}"
HOOK="${FIELDS[2]}"
TOOL="${FIELDS[3]}"
DURATION_MS="${FIELDS[4]}"
SUBJECT="${FIELDS[5]}"
STATUS="${FIELDS[6]}"
SESSION_ID="${FIELDS[7]}"
CHANGED="${FIELDS[8]}"

case "$STATUS" in
ok) STATUS_OUT=success EXIT_CODE=0 ;;
skipped) STATUS_OUT=skipped EXIT_CODE=0 ;;
blocked) STATUS_OUT=blocked EXIT_CODE=2 ;;
*) STATUS_OUT=error EXIT_CODE=2 ;;
esac

project_dir=""
hook::repo_root_to project_dir "${CLAUDE_PROJECT_DIR:-.}" || :
root=""
slog_root_to root "$project_dir"
[[ -n "$root" ]] || exit 0
slog_guard_ok "$root" "$project_dir" || exit 0

RUN_KEYS=(hook s "$HOOK" exit_code n "${EXIT_CODE}" subject s "$SUBJECT" tool s "$TOOL")
[[ -n "$CHANGED" ]] && RUN_KEYS+=(changed n "$CHANGED")

LINE=""
if [[ -n "$SESSION_ID" ]] && slog_valid_id "$SESSION_ID"; then
  [[ -d "$root/sessions" ]] || mkdir -p "$root/sessions" 2>/dev/null || exit 0
  slog_event_record_to LINE envelope "$TS" "$SESSION_ID" "$EVENT" "$STATUS_OUT" \
    "${DURATION_MS:-0}" "${RUN_KEYS[@]}"
  printf '%s\n' "$LINE" >>"$root/sessions/$SESSION_ID.jsonl" 2>/dev/null
  exit 0
fi

mkdir -p "$root" 2>/dev/null || exit 0
slog_event_record_to LINE envelope "$TS" "" "$EVENT" "$STATUS_OUT" \
  "${DURATION_MS:-0}" "${RUN_KEYS[@]}"
slog_append_capped "${root}/hook-events.jsonl" "$LINE" "${CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES:-}"

exit 0
