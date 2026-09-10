#!/usr/bin/env bash
# Reference telemetry sink for claude-ops. Maps a hook-telemetry envelope (from
# ANY producer, per docs/conventions/hook-telemetry) into one JSONL line under
# the log root (.observability/claude by default, project-relative; the
# session_event_log_dir option moves it).
#
# Both routes write ONE record shape — the hook event record session-log-lib.sh
# documents and formats (slog_event_record_to), `source: "envelope"`. The
# envelope's session id, read from the spine (`session_id`, which a
# contract-1.1 producer carries when its payload held a well-formed one and
# omits otherwise) and falling back to `data.session_id`, which the claude-ops
# audit hooks still send, decides the DESTINATION and nothing else:
#   * present and well-formed: appended to sessions/<session_id>.jsonl, beside
#     the per-session event log (session-event-log.sh). No lock: one file per
#     session removes the shared write.
#   * absent: appended to the shared hook-events.jsonl under the same root, the
#     file the observability skill has always read, under its lock. The record
#     is the same minus `session_id`, which these rows do not have.
#
# Field mapping: ts<-timestamp, hook_event_name<-hook_event, hook<-hook,
# tool<-data.tool, subject<-data.subject, changed<-data.changed (when a
# producer sends one); status translates (ok->success) and exit_code derives
# from status (error/blocked->2, else 0), since the skill keys errors on it.
#
# The root carries a self-ignoring .gitignore inside a checkout, healed on the
# first write when absent (session-log-lib.sh); a guard an operator changed is
# respected and the write refused.
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
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=session-log-lib.sh
source "$HOOK_DIR/session-log-lib.sh"
INPUT=$(cat)
[[ -n "$INPUT" ]] || exit 0
# silent-skip-ok: fire-and-forget sink — the producer discards stdout+stderr,
# so no notice channel exists; the producer side owns prerequisite visibility.
command -v jq >/dev/null 2>&1 || exit 0

# Single jq parse + required-key guard. Emit one mapped field per line (nothing
# when a required envelope key is missing or the input is not valid JSON). One line
# per field — read via mapfile — so an empty field (e.g. tool) is preserved as
# an empty element rather than collapsed, which a tab-IFS `read` would do (tab is
# an IFS whitespace char, so consecutive tabs merge).
mapfile -t FIELDS < <(printf '%s' "$INPUT" | jq -r '
  if (.hook and .hook_event and (.duration_ms != null) and .status)
  then (.timestamp // ""), .hook_event, .hook, (.data.tool // ""),
       (.duration_ms | tostring), (.data.subject // ""), .status,
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

# Translate the envelope status to the record shape the skill reads. Known
# values pass through (ok → success); an unrecognized value is treated as a
# catch-all error, never a hard fail (forward-compat rule).
#
# exit_code is derived from the SAME status in the same pass: the skill's
# error/failed-then-fixed analysis keys on exit_code != 0. A clean/no-op run is 0;
# error and blocked are non-clean (2).
case "$STATUS" in
ok)
  STATUS_OUT=success
  EXIT_CODE=0
  ;;
skipped)
  STATUS_OUT=skipped
  EXIT_CODE=0
  ;;
error)
  STATUS_OUT=error
  EXIT_CODE=2
  ;;
blocked)
  STATUS_OUT=blocked
  EXIT_CODE=2
  ;;
*)
  STATUS_OUT=error
  EXIT_CODE=2
  ;;
esac

project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
root=""
slog_root_to root "$project_dir"
[[ -n "$root" ]] || exit 0
slog_guard_ok "$root" "$project_dir" || exit 0

# One record, one formatter, both routes: the line differs only by the session
# id the spine carries, so the route decides the destination and nothing else.
# No second jq here — session-log-lib.sh builds and escapes the line from
# builtins, which is one process fewer per event on both routes.
RUN_KEYS=(hook s "$HOOK" exit_code n "${EXIT_CODE:-0}" subject s "$SUBJECT" tool s "$TOOL")
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
hook::append_jsonl "${root}/hook-events.jsonl" "$LINE"

exit 0
