#!/usr/bin/env bash

set -uo pipefail
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

[[ "${CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED:-true}" == "true" ]] || exit 0

_hfa_on_exit() {
  local rc=$?
  trap - EXIT
  ((rc == 0)) && return 0
  echo "plugin-diagnostics hook-failure-audit: did not run (status ${rc}); fail-open" >&2
  builtin exit 0
}
trap _hfa_on_exit EXIT

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT '.transcript_path' '.session_id' || exit 0

if ! command -v jq >/dev/null 2>&1; then
  # shellcheck disable=SC2034 # the model text is filled and dropped: user only on Stop
  JQ_MODEL="" JQ_USER=""
  if hook::prereq_notice_to JQ_MODEL JQ_USER jq "$INPUT" --label plugin-diagnostics --no-path; then
    hook::emit_skip_notice Stop "" "$JQ_USER"
  fi
  exit 0
fi

((${#HOOK_JQ_FIELDS[@]} == 2)) || exit 0
TRANSCRIPT="${HOOK_JQ_FIELDS[0]}"
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || exit 0
SESSION="${HOOK_JQ_FIELDS[1]}"
[[ -n "$SESSION" ]] || SESSION="no-session"
SESSION_ID=""
[[ "$SESSION" != "no-session" && "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]] && SESSION_ID="$SESSION"
SESSION="${SESSION//[^A-Za-z0-9_-]/-}"

HAVE_MAPFILE=0
((BASH_VERSINFO[0] >= 4)) && HAVE_MAPFILE=1

MARKER_DIR=""
CURSOR_FILE=""
CURSOR=0
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  MARKER_DIR="${CLAUDE_PLUGIN_DATA}/hook-failure-audit"
  if [[ -d "$MARKER_DIR" ]] || mkdir -p "$MARKER_DIR" 2>/dev/null; then
    CURSOR_FILE="$MARKER_DIR/${SESSION}.cursor"
    CURSOR_BYTES=""
    CURSOR_PATH=""
    [[ -f "$CURSOR_FILE" ]] &&
      {
        IFS= read -r CURSOR_BYTES
        IFS= read -r CURSOR_PATH
      } 2>/dev/null <"$CURSOR_FILE"
    CURSOR_BYTES="${CURSOR_BYTES%$'\r'}"
    CURSOR_PATH="${CURSOR_PATH%$'\r'}"
    [[ "$CURSOR_BYTES" =~ ^b([1-9][0-9]{0,14})$ && "$CURSOR_PATH" == "$TRANSCRIPT" ]] &&
      CURSOR="${BASH_REMATCH[1]}"
    ((CURSOR >= 2)) || CURSOR=0
  else
    MARKER_DIR=""
  fi
fi

SCANNED=0
cursor_advance() {
  [[ -n "$CURSOR_FILE" ]] || return 0
  printf 'b%s\n%s\n' "$SCANNED" "$TRANSCRIPT" 2>/dev/null >"$CURSOR_FILE" || :
}
dispose_and_exit() {
  cursor_advance
  exit 0
}

TAIL_BYTES="${HOOK_FAILURE_AUDIT_TAIL_BYTES:-2000000}"

NEEDLE='"hook_non_blocking_error"'
RECORDS=""
LINES=()
N=0
scan_lines() {
  local i
  for ((i = $1; i < N; i++)); do
    [[ "${LINES[i]}" == *"$NEEDLE"* ]] && RECORDS+="${LINES[i]}"
  done
  RECORDS="${RECORDS%$'\n'}"
}

warm_read() {
  local LC_ALL=C window body complete line
  { window=$(tail -c "+$((CURSOR - 1))" -- "$TRANSCRIPT"); } 2>/dev/null
  SCANNED=$CURSOR
  if [[ "$window" != ?$'\n'* ]]; then
    [[ ${#window} == 1 ]]
    return
  fi
  body="${window:2}"
  if [[ "$body" == *$'\n'* ]]; then
    complete="${body%$'\n'*}"
    SCANNED=$((CURSOR + ${#complete} + 1))
  fi
  [[ "$body" == *"$NEEDLE"* ]] || return 0
  local IFS=$'\n'
  set -f
  for line in $body; do
    [[ "$line" == *"$NEEDLE"* ]] && RECORDS+="$line"$'\n'
  done
  set +f
  RECORDS="${RECORDS%$'\n'}"
}

if ((CURSOR > 0)); then
  warm_read || CURSOR=0
fi

if ((CURSOR == 0)); then
  SIZE=""
  { read -r SIZE _ < <(wc -c -- "$TRANSCRIPT"); } 2>/dev/null
  [[ "$SIZE" =~ ^[0-9]+$ ]] || exit 0
  SCANNED=$SIZE
  if ((SIZE > TAIL_BYTES)); then
    RECORDS=$(tail -c "$TAIL_BYTES" -- "$TRANSCRIPT" 2>/dev/null | sed '1d' |
      grep -F "$NEEDLE")
  elif ((HAVE_MAPFILE)); then
    # slow-shape-ok: SIZE <= TAIL_BYTES on this branch, so the whole file is at most the cap
    mapfile LINES <"$TRANSCRIPT" 2>/dev/null
    N=${#LINES[@]}
    scan_lines 0
  else
    # slow-shape-ok: SIZE <= TAIL_BYTES on this branch, so the whole file is at most the cap
    { RECORDS=$(grep -F "$NEEDLE" -- "$TRANSCRIPT"); } 2>/dev/null
  fi
fi
LINES=()
[[ -n "$RECORDS" ]] || dispose_and_exit
SUMMARY=$(printf '%s' "$RECORDS" |
  jq -cRs '
    def stale:
      ((.stderr // "") | sub("[\\r\\n]+$"; "")) as $e
      | (.command // "") as $c
      | if .exitCode != 127 or ($e | test(": line [0-9]+: ")) then false
        else ([$e | capture("^(?:Failed with non-blocking status code: )?(?:bash|sh|/[^:\\n]*/(?:bash|sh)): (?<p>[^\\n]+): No such file or directory$")?
               | .p | split("/") | last | split("\\") | last] | first) as $b
          | if $b == null or $b == "" then false
            elif ($c | test("\\$\\{CLAUDE_PLUGIN_ROOT\\}|\\.(sh|bash|mjs|cjs|js|py|ps1)\\b")) # portability-ok: jq Oniguruma regex, not GNU grep or sed
            then ($c | [splits("[\\s\"'"'"'/\\\\]+")] | any(. == $b)) # portability-ok: jq Oniguruma regex, not GNU grep or sed
            else true end
        end;
    [
      split("\n")[] | fromjson?
      | select(.type? == "attachment") | .attachment
      | select(.type? == "hook_non_blocking_error")
      | {hookName: (.hookName // "unknown"),
         command: ((.command // "") | .[0:120]),
         exitCode: (.exitCode // null),
         class: (if ((.stderr // "")
                     | test("execvpe|execve\\(|exec format error|executing hook command: Executable not found in \\$PATH"; "i"))
                 then "launch"
                 elif stale then "stale"
                 elif (.exitCode == 126 or .exitCode == 127) then "ambiguous"
                 else "completed" end),
         stderr: ((.stderr // "") | .[0:160])}
    ]
    | group_by(.hookName + "	" + .command)
    | map({hookName: .[0].hookName, command: .[0].command,
           count: length,
           launchCount: (map(select(.class == "launch")) | length),
           staleCount: (map(select(.class == "stale")) | length),
           ambiguousCount: (map(select(.class == "ambiguous")) | length),
           completedCount: (map(select(.class == "completed")) | length),
           exitCode: last.exitCode, stderr: last.stderr})' 2>/dev/null)
[[ -n "$SUMMARY" ]] || exit 0
[[ "$SUMMARY" != "[]" ]] || dispose_and_exit

MARKER=""
WARNED=""
if [[ -n "$MARKER_DIR" ]]; then
  find "$MARKER_DIR" -type f -mtime +7 -delete 2>/dev/null
  MARKER="$MARKER_DIR/${SESSION}"
  [[ -f "$MARKER" ]] && { WARNED=$(<"$MARKER"); } 2>/dev/null
fi

NEW=$(jq -cn --argjson summary "$SUMMARY" --arg warned "$WARNED" '
  ($warned | split("\n") | map(rtrimstr("\r")) | map(select(length > 0))) as $seen
  | [$summary[] | select((.hookName + "	" + .command) as $k | $seen | index($k) | not)]')
[[ -n "$NEW" ]] || exit 0
[[ "$NEW" != "[]" ]] || dispose_and_exit

TOTAL=$(jq -rn --argjson new "$NEW" '[$new[].count] | add')

NO_STDERR_PLACEHOLDER='Failed with non-blocking status code: No stderr output'

DETAIL=$(jq -rn --argjson new "$NEW" --arg ph "$NO_STDERR_PLACEHOLDER" '
  [$new[] |
    (if (.stderr == "" or .stderr == $ph) then "(none — hook produced no stderr)"
     else .stderr end) as $err |
    (if .exitCode == null then "?" else (.exitCode|tostring) end) as $ec |
    ([{n: .launchCount, label: "launch failure"},
      {n: .staleCount, label: "stale config: registered script missing from disk"},
      {n: .ambiguousCount,
       label: "ambiguous: exit 126/127 with no exec-failure signature"},
      {n: .completedCount, label: "completed non-zero exit"}]
     | map(select(.n > 0))) as $classes |
    (if ($classes | length) == 1 then $classes[0].label
     else ($classes | map("\(.n) \(.label)") | join(" + ")) end) as $kind |
    "\(.hookName) [\(.command)] (\(.count)x; \($kind); exit \($ec); last stderr: \($err))"
  ] | join("; ")')

read -r HAS_LAUNCH HAS_AMBIGUOUS HAS_COMPLETED HAS_STALE < <(jq -rn --argjson new "$NEW" '
  [([$new[] | .launchCount > 0]    | any),
   ([$new[] | .ambiguousCount > 0] | any),
   ([$new[] | .completedCount > 0] | any),
   ([$new[] | .staleCount > 0]     | any)] | @tsv')
HAS_STALE="${HAS_STALE%$'\r'}"

MSG="plugin-diagnostics: ${TOTAL} hook failure(s) Claude Code did not show: ${DETAIL}."
if [[ "$HAS_LAUNCH" == "true" ]]; then
  MSG="${MSG} A hook that fails to launch enforces nothing; the calls it guards ran unchecked (fail-open)."
fi
if [[ "$HAS_STALE" == "true" ]]; then
  MSG="${MSG} A stale-config record means the hook's own script is missing from disk: this session is running hook config it loaded before the plugin changed, so that hook enforced nothing for the calls listed. Run /reload-plugins to load the current config, or restart the session."
fi
if [[ "$HAS_AMBIGUOUS" == "true" ]]; then
  MSG="${MSG} Exit 126/127 without an exec-failure signature can be the registered command or a command the hook ran. Both are possible: check the registered command, and read the hook's own logic."
fi
if [[ "$HAS_COMPLETED" == "true" ]]; then
  MSG="${MSG} A hook that exited non-zero with no exec-failure evidence enforced nothing; its exit status and stderr above say why."
fi
if [[ "$HAS_STALE" != "true" && ("$HAS_LAUNCH" == "true" || "$HAS_AMBIGUOUS" == "true") ]]; then
  MSG="${MSG} Hook config changed on disk mid-session is not loaded yet. Run /reload-plugins to load the current config, or restart the session."
fi

hook::emit_system_message "$MSG"

cursor_advance

if [[ -n "$MARKER" ]]; then
  FINGERPRINTS=""
  { FINGERPRINTS=$(jq -rn --argjson new "$NEW" '$new[] | .hookName + "	" + .command'); } 2>/dev/null
  [[ -n "$FINGERPRINTS" ]] && printf '%s\n' "${FINGERPRINTS//$'\r'/}" >>"$MARKER" 2>/dev/null
fi

DATA=$(jq -cn --arg session_id "$SESSION_ID" --argjson new "$NEW" --argjson total "${TOTAL:-0}" \
  '{subjects: ([$new[].hookName] | unique), total: $total} + (if $session_id == "" then {} else {session_id: $session_id} end)')
hook::emit_telemetry "hook-failure-audit" "Stop" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
