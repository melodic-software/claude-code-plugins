#!/usr/bin/env bash
# Reference telemetry sink for claude-ops. Maps a hook-telemetry envelope (from
# ANY producer, per docs/conventions/hook-telemetry) into one JSONL line in
# .claude/observability/hook-events.jsonl — the shape the claude-observability
# skill reads ({ts, event, hook, tool, duration_ms, exit_code, subject, status}).
#
# Field mapping: ts<-timestamp, event<-hook_event, hook<-hook, tool<-data.tool,
# subject<-data.subject; status translates (ok->success) and exit_code derives
# from status (error/blocked->2, else 0), since the skill keys errors on it.
#
# Wire it by pointing HOOK_TELEMETRY_SINK at this script (relative path committed
# in settings.json is the portable, team-shared form):
#   "env": { "HOOK_TELEMETRY_SINK": "<path>/hook-telemetry-sink.sh" }
#
# Fire-and-forget: the producer execs this as a single command in a backgrounded
# subshell with stdout+stderr → /dev/null, so it MUST never crash and never write
# stdout. It reads one envelope on stdin and appends one event line.
#
# -e is intentionally omitted: this sink must never exit non-zero on a benign
# non-zero (e.g. jq returning empty). nounset guards typos; pipefail surfaces
# undetected pipe failures without aborting the process.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

INPUT=$(cat)
[[ -n "$INPUT" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Single jq parse + required-key guard. Emit one mapped field per line (nothing
# when a required envelope key is missing or the input is not valid JSON). One line
# per field — read via mapfile — so an empty field (e.g. tool) is preserved as
# an empty element rather than collapsed, which a tab-IFS `read` would do (tab is
# an IFS whitespace char, so consecutive tabs merge).
mapfile -t FIELDS < <(printf '%s' "$INPUT" | jq -r '
  if (.hook and .hook_event and (.duration_ms != null) and .status)
  then (.timestamp // ""), .hook_event, .hook, (.data.tool // ""),
       (.duration_ms | tostring), (.data.subject // ""), .status
  else empty end' 2>/dev/null | tr -d '\r')
[[ "${#FIELDS[@]}" -eq 7 ]] || exit 0

TS="${FIELDS[0]}"
EVENT="${FIELDS[1]}"
HOOK="${FIELDS[2]}"
TOOL="${FIELDS[3]}"
DURATION_MS="${FIELDS[4]}"
SUBJECT="${FIELDS[5]}"
STATUS="${FIELDS[6]}"

# Translate the envelope status to the record shape the skill reads. Known
# values pass through (ok → success); an unrecognized value is treated as a
# catch-all error, never a hard fail (forward-compat rule).
case "$STATUS" in
ok) STATUS_OUT=success ;;
error) STATUS_OUT=error ;;
skipped) STATUS_OUT=skipped ;;
blocked) STATUS_OUT=blocked ;;
*) STATUS_OUT=error ;;
esac

# Derive exit_code: the skill's error/failed-then-fixed analysis keys on
# exit_code != 0. A clean/no-op run is 0; error and blocked are non-clean (2).
case "$STATUS" in
error | blocked) EXIT_CODE=2 ;;
ok | skipped) EXIT_CODE=0 ;;
*) EXIT_CODE=2 ;;
esac

project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
log_dir="${project_dir%/}/.claude/observability"
mkdir -p "$log_dir" 2>/dev/null || exit 0

LINE=$(MSYS_NO_PATHCONV=1 jq -nc \
  --arg ts "$TS" \
  --arg event "$EVENT" \
  --arg hook "$HOOK" \
  --arg tool "$TOOL" \
  --argjson duration_ms "${DURATION_MS:-0}" \
  --argjson exit_code "${EXIT_CODE:-0}" \
  --arg subject "$SUBJECT" \
  --arg status "$STATUS_OUT" \
  '{ts: $ts, event: $event, hook: $hook, tool: $tool,
    duration_ms: $duration_ms, exit_code: $exit_code,
    subject: $subject, status: $status}' 2>/dev/null) || exit 0
[[ -n "$LINE" ]] || exit 0

hook::append_jsonl "${log_dir}/hook-events.jsonl" "$LINE"

exit 0
