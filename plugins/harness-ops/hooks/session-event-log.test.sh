#!/usr/bin/env bash
# Contract test for session-event-log.sh (harness-ops plugin). Black-box: the
# producer reads one hook payload on stdin and appends at most one line to
# <root>/sessions/<session_id>.jsonl. Nothing here sources the hook.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/session-event-log.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=harness-ops-test-helpers.sh
source "$HOOK_DIR/harness-ops-test-helpers.sh"

ON=CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED=true

# The hook event record schema session-log-lib.sh documents, as one jq -e over
# every line of a session file. `source: "event-log"` rows describe one event
# the session saw, never a hook run, so they carry `category` and no `hook`;
# the retired `event` key must be absent, which is what lets a reader query
# `.hook_event_name` with no normalization prelude.
RECORD_SCHEMA='(.ts|type)=="string" and (.session_id|type)=="string"
  and (.hook_event_name|type)=="string" and (.status|type)=="string"
  and ((.duration_ms|type)=="number" or .duration_ms==null)
  and .source=="event-log" and (.category|type)=="string"
  and (.effort|type)=="string"
  and (has("event")|not) and (has("hook")|not)'

# assert_record <label> <file> [<extra jq clause>]
assert_record() {
  jq -e -s "all(.[]; $RECORD_SCHEMA${3:+ and ($3)})" "$2" >/dev/null 2>&1
  assert_exit "$1" 0 "$?"
}

# payload <session_id> <event> [<extra-json-members>]
payload() {
  local extra="${3:-}"
  printf '{"session_id":"%s","prompt_id":"p-1","transcript_path":"/x/t.jsonl","cwd":"/x","permission_mode":"default","hook_event_name":"%s"%s}' \
    "$1" "$2" "${extra:+,$extra}"
}

# project <name> [--no-git] -> a fixture project dir, a git checkout by default
project() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  [[ "${2:-}" == "--no-git" ]] || mkdir -p "$d/.git"
  printf '%s' "$d"
}

# run <project> <payload> [env...]: runs the hook with CLAUDE_PROJECT_DIR set.
# The body is written to a file before the hook starts, then read back on
# stdin. The parallel case fans the hook out 33 ways, and a pipe can let one
# idle read (CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT, default 2s) return
# before printf delivers the body: the hook exits, printf hits a broken pipe,
# and that fire adds no line. A file has no writer left to race.
run() {
  local proj="$1" body="$2" payload_file
  shift 2
  payload_file="$(mktemp "$TEST_TMPDIR/payload.XXXXXX")"
  printf '%s' "$body" >"$payload_file"
  env -u HOOK_TELEMETRY_SINK -u CLAUDE_EFFORT CLAUDE_PROJECT_DIR="$proj" "$@" bash "$HOOK" <"$payload_file" 2>&1
}

# --- default OFF: nothing is read or written --------------------------------
P=$(project off)
OUT=$(run "$P" "$(payload s1 PostToolUse)")
assert_exit "disabled by default → exit 0" 0 "$?"
assert_silent "disabled by default → silent" "$OUT"
assert_file_absent "disabled by default → no root created" "$P/.observability"

# --- enabled, fresh checkout: guard healed, one full-spine line -------------
P=$(project on)
OUT=$(run "$P" "$(payload sess-abc PostToolUse '"tool_name":"Write","tool_input":{"file_path":"'"$P"'/docs/a.md","content":"x"},"tool_use_id":"toolu_01"')" "$ON")
assert_exit "enabled → exit 0" 0 "$?"
assert_silent "enabled → silent (no stdout, no stderr)" "$OUT"
LOG="$P/.observability/claude/sessions/sess-abc.jsonl"
if [[ -s "$LOG" ]]; then
  assert_eq "guard healed on first write" "*" "$(head -1 "$P/.observability/claude/.gitignore")"
  assert_eq "one line per event" 1 "$(wc -l <"$LOG" | tr -d ' ')"
  jq -e 'has("session_id") and has("hook_event_name") and has("ts") and has("status") and has("source")' "$LOG" >/dev/null 2>&1
  assert_exit "line carries the full spine" 0 "$?"
  assert_eq "session_id" "sess-abc" "$(jq -r .session_id "$LOG")"
  assert_eq "hook_event_name" "PostToolUse" "$(jq -r .hook_event_name "$LOG")"
  assert_eq "category" "tool" "$(jq -r .category "$LOG")"
  assert_eq "source" "event-log" "$(jq -r .source "$LOG")"
  assert_eq "prompt_id carried" "p-1" "$(jq -r .prompt_id "$LOG")"
  assert_eq "tool_use_id carried" "toolu_01" "$(jq -r .tool_use_id "$LOG")"
  assert_eq "tool_name carried" "Write" "$(jq -r .tool_name "$LOG")"
  assert_eq "file_path recorded repo-relative" "docs/a.md" "$(jq -r .file_path "$LOG")"
  assert_eq "duration_ms is a number" "number" "$(jq -r '.duration_ms | type' "$LOG")"
  assert_record "event-log route: the line satisfies the record schema" "$LOG"
else
  bad "enabled: no line written at $LOG"
fi

# --- a second event on the same session appends; another session gets its own file
run "$P" "$(payload sess-abc Stop)" "$ON" >/dev/null
run "$P" "$(payload sess-xyz SessionStart)" "$ON" >/dev/null
assert_eq "second event appends to the session file" 2 "$(wc -l <"$LOG" | tr -d ' ')"
assert_eq "another session gets its own file" 1 "$(wc -l <"$P/.observability/claude/sessions/sess-xyz.jsonl" | tr -d ' ')"
assert_eq "exactly two session files" 2 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"

# --- PostToolBatch: one line per batch, carrying the first call's tool keys ------
P=$(project batch)
OUT=$(run "$P" "$(payload sb PostToolBatch '"tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"/x/a.md"},"tool_use_id":"toolu_b1","tool_response":{"content":"a"}},{"tool_name":"Grep","tool_input":{"pattern":"x"},"tool_use_id":"toolu_b2","tool_response":{"content":"b"}}]')" "$ON")
assert_exit "PostToolBatch → exit 0" 0 "$?"
BLOG="$P/.observability/claude/sessions/sb.jsonl"
assert_eq "PostToolBatch → one line for the batch" 1 "$(wc -l <"$BLOG" 2>/dev/null | tr -d ' ')"
assert_eq "PostToolBatch → hook_event_name" "PostToolBatch" "$(jq -r .hook_event_name "$BLOG" 2>/dev/null)"
assert_eq "PostToolBatch → category tool" "tool" "$(jq -r .category "$BLOG" 2>/dev/null)"
assert_eq "PostToolBatch → first entry's tool_name" "Read" "$(jq -r .tool_name "$BLOG" 2>/dev/null)"
assert_eq "PostToolBatch → first entry's tool_use_id" "toolu_b1" "$(jq -r .tool_use_id "$BLOG" 2>/dev/null)"

# --- the guard is never overwritten when an operator changed it ---------------
P=$(project guarded)
mkdir -p "$P/.observability/claude"
printf '# mine\nsessions/\n' >"$P/.observability/claude/.gitignore"
run "$P" "$(payload s1 PostToolUse)" "$ON" >/dev/null
assert_file_absent "a present-but-different guard refuses the write" "$P/.observability/claude/sessions/s1.jsonl"
assert_eq "the operator's guard is left alone" "# mine" "$(head -1 "$P/.observability/claude/.gitignore")"

# --- an EMPTY guard file is healed, not refused ---------------------------------
# Two producers racing on one event: the first opens .gitignore, the second
# reads it before the first has written its byte. Read as an operator file it
# refuses the write and a line goes missing (the 33-parallel case below caught
# 32); read as heal-in-progress both write `*` and nothing is lost.
P=$(project empty-guard)
mkdir -p "$P/.observability/claude"
: >"$P/.observability/claude/.gitignore"
run "$P" "$(payload s1 PreToolUse)" "$ON" >/dev/null
if [[ -f "$P/.observability/claude/sessions/s1.jsonl" ]]; then
  ok "an empty guard file does not refuse the write"
else
  bad "an empty guard file does not refuse the write"
fi
assert_eq "an empty guard file is healed to *" "*" "$(head -1 "$P/.observability/claude/.gitignore")"

# --- outside a checkout there is nothing to keep clean: write, no guard -------
P=$(project nogit --no-git)
run "$P" "$(payload s2 PostToolUse)" "$ON" >/dev/null
assert_eq "no checkout → line written" 1 "$(wc -l <"$P/.observability/claude/sessions/s2.jsonl" | tr -d ' ')"
assert_file_absent "no checkout → no guard file" "$P/.observability/claude/.gitignore"

# --- lines are never written without the spine ---------------------------------
P=$(project nospine)
run "$P" '{"cwd":"/x","hook_event_name":"PostToolUse"}' "$ON" >/dev/null
assert_file_absent "no session_id → nothing written" "$P/.observability"
run "$P" '{"session_id":"s3","cwd":"/x"}' "$ON" >/dev/null
assert_file_absent "no hook_event_name → nothing written" "$P/.observability"
run "$P" "$(payload '../escape' PostToolUse)" "$ON" >/dev/null
assert_file_absent "hostile session_id → nothing written" "$P/.observability"
run "$P" "$(payload 's4' 'Post Tool')" "$ON" >/dev/null
assert_file_absent "hostile event name → nothing written" "$P/.observability"

# --- category filter ------------------------------------------------------------
P=$(project cats)
run "$P" "$(payload s5 PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES=session,turn >/dev/null
assert_file_absent "filtered category → nothing written" "$P/.observability/claude/sessions/s5.jsonl"
run "$P" "$(payload s5 Stop)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES=session,turn >/dev/null
assert_eq "listed category → written" "turn" "$(jq -r .category "$P/.observability/claude/sessions/s5.jsonl")"

# --- configured root: contained relative only; the project root itself is refused
P=$(project roots)
run "$P" "$(payload s6 PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry/claude >/dev/null
assert_eq "contained custom root is used" 1 "$(wc -l <"$P/telemetry/claude/sessions/s6.jsonl" | tr -d ' ')"
# shellcheck disable=SC2088  # the literal tilde is the fixture: a root spelled ~/x must be refused, not expanded
for bad_root in /abs ../up 'C:\logs' '~/x' 'a/../b' .; do
  run "$P" "$(payload s7 PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR="$bad_root" >/dev/null
done
assert_file_absent "uncontained roots write nothing (s7 never lands)" "$P/telemetry/claude/sessions/s7.jsonl"
assert_file_absent "the project root itself is refused" "$P/sessions"
assert_file_absent "the project root gets no guard" "$P/.gitignore"

# A lexically contained root whose existing component is a symlink can point
# anywhere, and retention deletes under the root, so containment is also
# physical: a link out of the project is refused, a link that stays inside is
# followed, and a link back to the project root itself is refused like `.`.
OUTSIDE="$TEST_TMPDIR/outside-target"
mkdir -p "$OUTSIDE" "$P/inside-target"
ln -s "$OUTSIDE" "$P/escape"
ln -s "$P/inside-target" "$P/stays"
ln -s "$P" "$P/loop"
run "$P" "$(payload s7e PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=escape/claude >/dev/null
assert_file_absent "a root through a symlink out of the project writes nothing" "$OUTSIDE/claude/sessions/s7e.jsonl"
assert_file_absent "and leaves no guard outside the project" "$OUTSIDE/claude/.gitignore"
run "$P" "$(payload s7i PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=stays/claude >/dev/null
assert_eq "a root through a symlink inside the project is used" 1 "$(wc -l <"$P/inside-target/claude/sessions/s7i.jsonl" 2>/dev/null | tr -d ' ')"
run "$P" "$(payload s7l PostToolUse)" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=loop >/dev/null
assert_file_absent "a root that resolves to the project itself is refused" "$P/sessions/s7l.jsonl"
assert_file_absent "and the project root still gets no guard" "$P/.gitignore"

# --- cwd is the project when CLAUDE_PROJECT_DIR is unset -------------------------
P=$(project bycwd)
printf '{"session_id":"s8","cwd":"%s","hook_event_name":"PostToolUse"}' "$P" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK "$ON" bash "$HOOK" >/dev/null 2>&1
assert_eq "payload cwd resolves the project" 1 "$(wc -l <"$P/.observability/claude/sessions/s8.jsonl" 2>/dev/null | tr -d ' ')"

# --- file paths outside the project are reduced to their last segment ------------
P=$(project outside)
run "$P" "$(payload s9 PostToolUse '"tool_name":"Edit","tool_input":{"file_path":"/opt/elsewhere/private/notes.md"}')" "$ON" >/dev/null
assert_eq "outside path → last segment only" "notes.md" "$(jq -r .file_path "$P/.observability/claude/sessions/s9.jsonl")"
# A Windows path carries no `/`: the last segment must be taken after `\` too,
# or the whole path (username included) lands in the log.
# Assembled from parts so no drive-letter path literal sits in this file (the
# repo's hardcoded-path guard rejects one); the payload carries `\\` per
# separator, the JSON escape of one backslash.
BS="\\\\"
WIN_PATH="Q:${BS}scratch${BS}private${BS}notes.md"
run "$P" "$(payload s9w PostToolUse "\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"${WIN_PATH}\"}")" "$ON" >/dev/null
assert_eq "Windows outside path → last segment only" "notes.md" "$(jq -r .file_path "$P/.observability/claude/sessions/s9w.jsonl")"

# A payload body carrying JSON escapes is re-emitted verbatim, never re-escaped:
# the record formatter takes these three keys as bodies for exactly this reason.
run "$P" "$(payload s9e PostToolUse '"tool_name":"Edit","reason":"said \"go\" then \\ stopped\tabruptly"')" "$ON" >/dev/null
assert_record "an escaped payload body still satisfies the record schema" "$P/.observability/claude/sessions/s9e.jsonl"
assert_eq "an escaped payload body round-trips verbatim" "$(printf 'said "go" then \\ stopped\tabruptly')" \
  "$(jq -r .reason "$P/.observability/claude/sessions/s9e.jsonl")"

# --- effort: env, then the payload's top-level effort.level, else unset or n/a ----
# Payload shapes follow the hooks reference's Stop, SubagentStop,
# PermissionRequest, PostToolUseFailure, SessionStart and UserPromptSubmit input
# examples; the levels are the five the reference names.
P=$(project effort)
ELOG() { printf '%s' "$P/.observability/claude/sessions/$1.jsonl"; }
STOP_TAIL='"stop_hook_active":false,"last_assistant_message":"I finished the refactor","background_tasks":[{"id":"t1","type":"subagent","status":"running","description":"d","agent_type":"Explore"}],"session_crons":[]'
run "$P" "$(payload e1 Stop "\"effort\":{\"level\":\"high\"},$STOP_TAIL")" "$ON" >/dev/null
assert_eq "Stop with top-level effort.level records it" "high" "$(jq -r .effort "$(ELOG e1)")"
assert_eq "Stop: stop_hook_active round-trips as a JSON boolean" "boolean false" "$(jq -r '"\(.stop_hook_active|type) \(.stop_hook_active)"' "$(ELOG e1)")"
assert_eq "Stop: last_assistant_message (content) is absent" "false" "$(jq -r 'has("last_assistant_message")' "$(ELOG e1)")"
assert_eq "Stop: a background task's agent_type is not read as the event's" "false" "$(jq -r 'has("agent_type")' "$(ELOG e1)")"
assert_record "effort rows satisfy the record schema" "$(ELOG e1)"

run "$P" "$(payload e2 SubagentStop '"effort":{"level":"medium"},"stop_hook_active":false,"agent_id":"def456","agent_type":"Explore","agent_transcript_path":"/home/<user>/.claude/projects/p/abc/subagents/agent-def456.jsonl","last_assistant_message":"done","background_tasks":[],"session_crons":[]')" "$ON" >/dev/null
assert_eq "SubagentStop with top-level effort.level records it" "medium" "$(jq -r .effort "$(ELOG e2)")"
assert_eq "SubagentStop: agent_type round-trips" "Explore" "$(jq -r .agent_type "$(ELOG e2)")"
assert_eq "SubagentStop: agent_transcript_path is the raw absolute value" "/home/<user>/.claude/projects/p/abc/subagents/agent-def456.jsonl" "$(jq -r .agent_transcript_path "$(ELOG e2)")"

run "$P" "$(payload e3 Stop "\"effort\":{\"level\":\"high\"},$STOP_TAIL")" "$ON" CLAUDE_EFFORT=xhigh >/dev/null
assert_eq "payload wins over a conflicting inherited CLAUDE_EFFORT=xhigh" "high" "$(jq -r .effort "$(ELOG e3)")"
run "$P" "$(payload e3a Stop "$STOP_TAIL")" "$ON" CLAUDE_EFFORT=xhigh >/dev/null
assert_eq "env fills in when the payload has none (CLAUDE_EFFORT=xhigh)" "xhigh" "$(jq -r .effort "$(ELOG e3a)")"
run "$P" "$(payload e3b Stop "$STOP_TAIL")" "$ON" CLAUDE_EFFORT=turbo >/dev/null
assert_eq "a CLAUDE_EFFORT that names no level records unset" "unset" "$(jq -r .effort "$(ELOG e3b)")"

run "$P" "$(payload e4 Stop "$STOP_TAIL")" "$ON" >/dev/null
assert_eq "Stop payload without effort records unset" "unset" "$(jq -r .effort "$(ELOG e4)")"

run "$P" "$(payload e5 UserPromptSubmit '"prompt":"Write a function to calculate the factorial","session_title":"my title"')" "$ON" CLAUDE_EFFORT=high >/dev/null
assert_eq "n/a-list event (UserPromptSubmit) records n/a" "n/a" "$(jq -r .effort "$(ELOG e5)")"
assert_eq "UserPromptSubmit: the prompt text (content) is absent" "false" "$(jq -r 'has("prompt")' "$(ELOG e5)")"
assert_eq "UserPromptSubmit: session_title (content) is absent" "false" "$(jq -r 'has("session_title")' "$(ELOG e5)")"
assert_eq "no line carries the prompt text anywhere" "0" "$(grep -c 'factorial' "$(ELOG e5)")"

# Hostile: tool_input comes before every top-level key and carries a bare
# "level":"max" and a nested effort object; only the real top-level level, or
# unset, may land, never max. The same holds when no top-level effort exists.
run "$P" '{"tool_input":{"command":"x","level":"max","effort":{"level":"max"},"mode":"secret-mode"},"session_id":"e6","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","effort":{"level":"high"}}' "$ON" >/dev/null
assert_eq "hostile tool_input (PermissionRequest) with a nested effort records unset, never max" "unset" "$(jq -r .effort "$(ELOG e6)")"
assert_eq "hostile tool_input: a nested allowlisted key (mode) is not copied" "false" "$(jq -r 'has("mode")' "$(ELOG e6)")"
run "$P" '{"tool_input":{"command":"npm test","level":"max","effort":{"level":"max"}},"session_id":"e7","cwd":"/x","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_use_id":"toolu_07","error":"Exit code 1\nError: boom","is_interrupt":true,"duration_ms":4187}' "$ON" >/dev/null
assert_eq "hostile tool_input (PostToolUseFailure) with only a nested effort records unset" "unset" "$(jq -r .effort "$(ELOG e7)")"
assert_eq "PostToolUseFailure: is_interrupt after tool_input round-trips as a JSON boolean" "boolean true" "$(jq -r '"\(.is_interrupt|type) \(.is_interrupt)"' "$(ELOG e7)")"
assert_eq "PostToolUseFailure: the error text (tool output) is absent" "false" "$(jq -r 'has("error")' "$(ELOG e7)")"
assert_eq "PostToolUseFailure: duration_ms stays the logger's own, never the payload's" "false" "$(jq -r '.duration_ms == 4187' "$(ELOG e7)")"

# boolean/number round trip, and a payload `source` never displaces the record's.
run "$P" "$(payload e8 SessionStart '"source":"resume","model":"claude-opus-5","seconds_since_last_response":5400,"context_tokens":182340,"prompt_cache_likely_expired":true,"estimated_cache_write_usd":1.1396')" "$ON" >/dev/null
assert_eq "boolean/number: numbers and a boolean keep their JSON types and values" \
  "number 5400|number 182340|boolean true|number 1.1396" \
  "$(jq -r '[.seconds_since_last_response, .context_tokens, .prompt_cache_likely_expired, .estimated_cache_write_usd] | map("\(type) \(.)") | join("|")' "$(ELOG e8)")"
assert_eq "SessionStart: model round-trips" "claude-opus-5" "$(jq -r .model "$(ELOG e8)")"
assert_eq "SessionStart: the payload's source does not displace the record's" "event-log" "$(jq -r .source "$(ELOG e8)")"
assert_eq "SessionStart records n/a" "n/a" "$(jq -r .effort "$(ELOG e8)")"
assert_record "metadata rows satisfy the record schema" "$(ELOG e8)"

# The raw absolute cwd, transcript_path and scratchpad_dir (D32).
run "$P" '{"session_id":"e9","transcript_path":"/home/<user>/.claude/projects/-home-dev-proj/e9.jsonl","cwd":"/home/<user>/proj","scratchpad_dir":"/tmp/claude-1000/-home-dev-proj/e9/scratchpad","permission_mode":"auto","hook_event_name":"PostToolBatch","tool_calls":[]}' "$ON" >/dev/null
assert_eq "raw absolute cwd round-trips" "/home/<user>/proj" "$(jq -r .cwd "$(ELOG e9)")"
assert_eq "raw absolute transcript_path round-trips" "/home/<user>/.claude/projects/-home-dev-proj/e9.jsonl" "$(jq -r .transcript_path "$(ELOG e9)")"
assert_eq "raw absolute scratchpad_dir round-trips" "/tmp/claude-1000/-home-dev-proj/e9/scratchpad" "$(jq -r .scratchpad_dir "$(ELOG e9)")"
assert_eq "permission_mode round-trips" "auto" "$(jq -r .permission_mode "$(ELOG e9)")"

# Each allowlisted string field round-trips from the top level of a payload
# that carries them all, `v-<key>` per key; error@StopFailure on StopFailure.
STRINGS=$(bash -c 'source "$1"; printf "%s" "$SLOG_EVENT_LOG_STRINGS"' _ "$HOOK_DIR/session-log-lib.sh")
members=""
for entry in $STRINGS; do members+=",\"${entry%@*}\":\"v-${entry%@*}\""; done
run "$P" "{\"session_id\":\"e10\",\"hook_event_name\":\"StopFailure\"$members}" "$ON" >/dev/null
for entry in $STRINGS; do
  assert_eq "allowlisted string $entry round-trips" "v-${entry%@*}" "$(jq -r --arg k "${entry%@*}" '.[$k]' "$(ELOG e10)")"
done
run "$P" "{\"session_id\":\"e11\",\"hook_event_name\":\"Stop\"$members}" "$ON" >/dev/null
assert_eq "error@StopFailure is not read on another event" "false" "$(jq -r 'has("error")' "$(ELOG e11)")"

# --- content opt-in (session_event_log_content) -----------------------------------
# Off unless the option is exactly true; on, the top-level content strings land
# as the payload's own bodies, and a content string cut by the 64 KB read cap
# lands as its whole-escape prefix plus `<key>_truncated: true`.
CONTENT_ON=CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT=true
P=$(project content)
CLOG() { printf '%s' "$P/.observability/claude/sessions/$1.jsonl"; }
PROMPT_TAIL='"prompt":"Write a \"factorial\" function","session_title":"my title"'
run "$P" "$(payload c1 UserPromptSubmit "$PROMPT_TAIL")" "$ON" >/dev/null
assert_eq "opt-in off (default): prompt and session_title are absent" "false false" "$(jq -r '"\(has("prompt")) \(has("session_title"))"' "$(CLOG c1)")"
run "$P" "$(payload c2 UserPromptSubmit "$PROMPT_TAIL")" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT=TRUE >/dev/null
assert_eq "opt-in off: a value other than exactly true records no content" "false" "$(jq -r 'has("prompt")' "$(CLOG c2)")"

run "$P" "$(payload c3 UserPromptSubmit "$PROMPT_TAIL")" "$ON" "$CONTENT_ON" >/dev/null
assert_eq "opt-in on: the prompt text round-trips" 'Write a "factorial" function' "$(jq -r .prompt "$(CLOG c3)")"
assert_eq "opt-in on: session_title round-trips" "my title" "$(jq -r .session_title "$(CLOG c3)")"
assert_eq "opt-in on: a whole field carries no _truncated marker" "false" "$(jq -r 'has("prompt_truncated")' "$(CLOG c3)")"
assert_record "opt-in on: content rows satisfy the record schema" "$(CLOG c3)"
run "$P" "$(payload c4 Stop "$STOP_TAIL")" "$ON" "$CONTENT_ON" >/dev/null
assert_eq "opt-in on: Stop's last_assistant_message round-trips" "I finished the refactor" "$(jq -r .last_assistant_message "$(CLOG c4)")"
run "$P" '{"tool_input":{"command":"npm test","prompt":"nested"},"session_id":"c5","cwd":"/x","hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"Exit code 1\nError: boom","is_interrupt":true}' "$ON" "$CONTENT_ON" >/dev/null
assert_eq "opt-in on: PostToolUseFailure's error after tool_input round-trips" "$(printf 'Exit code 1\nError: boom')" "$(jq -r .error "$(CLOG c5)")"
assert_eq "opt-in on: a content key inside tool_input is not copied" "false" "$(jq -r 'has("prompt")' "$(CLOG c5)")"
run "$P" "$(payload c6 PostToolUse '"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/src/a.sh"}')" "$ON" "$CONTENT_ON" >/dev/null
assert_eq "opt-in on: file paths are still recorded project-relative" "src/a.sh" "$(jq -r .file_path "$(CLOG c6)")"

# A row near 48 KB: the whole field lands, unmarked.
FILL48=$(head -c 49152 /dev/zero | tr '\0' 'w')
run "$P" "$(payload c7 UserPromptSubmit "\"prompt\":\"$FILL48\"")" "$ON" "$CONTENT_ON" >/dev/null
assert_eq "opt-in on: a 48 KB prompt lands whole" 49152 "$(jq -r '.prompt | length' "$(CLOG c7)" 2>/dev/null)"
assert_eq "opt-in on: the 48 KB row carries no _truncated marker" "false" "$(jq -r 'has("prompt_truncated")' "$(CLOG c7)" 2>/dev/null)"

# truncated_case <sid> <tail-after-fill> [env...]: a UserPromptSubmit payload
# whose prompt is `x` filler sized so the 64 KB cap lands just after the first
# characters of <tail-after-fill>; prints the filler length.
truncated_case() {
  local sid="$1" tail="$2" head fill n
  shift 2
  head="$(payload "$sid" UserPromptSubmit '"prompt":"')"
  head="${head%\}}"
  n=$((65536 - ${#head} - 2))
  fill=$(head -c "$n" /dev/zero | tr '\0' 'x')
  run "$P" "${head}${fill}${tail}$(head -c 70000 /dev/zero | tr '\0' 'y')\"}" "$ON" "$CONTENT_ON" "$@" >/dev/null
  printf '%s' "$n"
}
ONE_BS="\\"
n=$(truncated_case c8 "${ONE_BS}u00e9")
assert_record "truncated at cap: the row is valid JSON" "$(CLOG c8)"
assert_eq "truncated at cap: prompt_truncated is true" "true" "$(jq -r .prompt_truncated "$(CLOG c8)" 2>/dev/null)"
assert_eq "truncated at cap: the prefix stops before a cut \\u escape" "$n" "$(jq -r '.prompt | length' "$(CLOG c8)" 2>/dev/null)"
n=$(truncated_case c9 'a\\b') # portability-ok: literal backslash payload, not a regex
assert_eq "truncated at cap: the prefix keeps every whole escape and drops a cut one" "$((n + 1))" "$(jq -r '.prompt | length' "$(CLOG c9)" 2>/dev/null)"
n=$(truncated_case c10 'a€' LC_ALL=C)
assert_eq "truncated at cap (byte locale): a cut multibyte character is dropped" "$((n + 1))" "$(jq -r '.prompt | length' "$(CLOG c10)" 2>/dev/null)"
iconv -f UTF-8 -t UTF-8 "$(CLOG c10)" >/dev/null 2>&1
assert_exit "truncated at cap (byte locale): the row is valid UTF-8" 0 "$?"
assert_eq "truncated at cap: a provable cut also carries content_truncated" "true" "$(jq -r .content_truncated "$(CLOG c8)" 2>/dev/null)"

# A content string cut after a nested value cannot be placed at the top level:
# it is not recorded, and the row says content was cut.
FILL70=$(head -c 70000 /dev/zero | tr '\0' 'q')
NESTED_CUT='{"session_id":"c11","cwd":"/x","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm test"},"error":"'"$FILL70"'"}'
run "$P" "$NESTED_CUT" "$ON" "$CONTENT_ON" >/dev/null
assert_record "cut after a nested value: the row is valid JSON" "$(CLOG c11)"
assert_eq "cut after a nested value: content_truncated is true, error absent" "true false" "$(jq -r '"\(.content_truncated) \(has("error"))"' "$(CLOG c11)" 2>/dev/null)"
assert_eq "under the cap: no content_truncated key" "false" "$(jq -r 'has("content_truncated")' "$(CLOG c5)")"
run "$P" "${NESTED_CUT/c11/c12}" "$ON" >/dev/null
assert_eq "opt-in off over the cap: no content keys and no content_truncated" "false false" "$(jq -r '"\(has("error")) \(has("content_truncated"))"' "$(CLOG c12)" 2>/dev/null)"

# --- a pause after a NESTED `}` does not end the read early ----------------------
# The writer stops for longer than one slice right after tool_input closes,
# then sends the rest. Read as "the payload ended", the buffer has no event
# name and the fire is silently dropped; read as "not yet balanced", the loop
# waits for the rest and the line lands with every key.
P=$(project midpause)
{
  printf '{"session_id":"s9p","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"x.md"}' "$P"
  sleep 1.2
  printf ',"hook_event_name":"PostToolUse","tool_use_id":"tu-9"}'
} | env CLAUDE_PROJECT_DIR="$P" "$ON" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1 bash "$HOOK" >/dev/null 2>&1
assert_eq "mid-message pause after a nested brace → the line is still written" 1 \
  "$(wc -l <"$P/.observability/claude/sessions/s9p.jsonl" 2>/dev/null | tr -d ' ')"
assert_eq "mid-message pause → the keys after the pause are present" "tu-9" \
  "$(jq -r .tool_use_id "$P/.observability/claude/sessions/s9p.jsonl" 2>/dev/null)"

# --- a held-open pipe returns inside the idle bound, with the line written --------
# The writer keeps the pipe open for 3 s after the payload (the Win32 late-EOF
# shape). The hook's own wall time is measured on the reading side, because the
# pipeline as a whole only ends when the writer does.
P=$(project heldopen)
elapsed_ms=$(
  {
    printf '%s' "$(payload s10 PostToolUse)"
    sleep 3
  } |
    {
      t0=$EPOCHREALTIME
      env CLAUDE_PROJECT_DIR="$P" "$ON" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1 bash "$HOOK" >/dev/null 2>&1
      t1=$EPOCHREALTIME
      awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }'
    }
)
# The whole payload (with its `/`-bearing paths) is in the first slice, so the
# early stop must fire on that slice's timeout: about a quarter of the 1 s idle
# bound plus startup, never the bound itself. A ceiling at the bound would pass
# a broken early stop (1.26 s was measured with one), which is why it is 700.
if ((elapsed_ms < 700)); then
  ok "held-open pipe: returned in ${elapsed_ms} ms (one quarter-bound slice, early stop)"
else
  bad "held-open pipe: took ${elapsed_ms} ms, expected under 1300"
fi
assert_eq "held-open pipe: the line was still written" 1 "$(wc -l <"$P/.observability/claude/sessions/s10.jsonl" | tr -d ' ')"

# --- a 512 KB payload still yields the spine (only the first 64 KB is read) ------
P=$(project big)
BIG=$(head -c 524288 /dev/zero | tr '\0' 'x')
run "$P" "$(payload s11 PostToolUse '"tool_name":"Read","tool_input":{"file_path":"/x/y"},"tool_response":"'"$BIG"'"')" "$ON" >/dev/null
assert_eq "512 KB payload → spine written" "PostToolUse" "$(jq -r .hook_event_name "$P/.observability/claude/sessions/s11.jsonl")"

# --- 33 parallel fires on one session produce 33 intact lines --------------------
P=$(project parallel)
for i in {1..33}; do
  run "$P" "$(payload s12 PostToolUse "\"tool_name\":\"T$i\"")" "$ON" >/dev/null &
done
wait
PLOG="$P/.observability/claude/sessions/s12.jsonl"
assert_eq "33 parallel fires → 33 lines" 33 "$(wc -l <"$PLOG" | tr -d ' ')"
assert_eq "33 parallel fires → every line parses" 33 "$(jq -c . "$PLOG" 2>/dev/null | wc -l | tr -d ' ')"

# --- 20 parallel rows over 4 KB on one session stay whole (the lock file) ---------
P=$(project parallel-long)
FILL8=$(head -c 8192 /dev/zero | tr '\0' 'z')
for i in {1..20}; do
  run "$P" "$(payload s12l UserPromptSubmit "\"prompt\":\"$i$FILL8\"")" "$ON" "$CONTENT_ON" >/dev/null &
done
wait
LLOG="$P/.observability/claude/sessions/s12l.jsonl"
assert_eq "20 parallel 8 KB rows → 20 lines" 20 "$(wc -l <"$LLOG" | tr -d ' ')"
assert_eq "20 parallel 8 KB rows → every line parses" 20 "$(jq -c . "$LLOG" 2>/dev/null | wc -l | tr -d ' ')"
assert_file_absent "20 parallel 8 KB rows → no lock left behind" "$LLOG.lock"

# A stale lock (its token unchanged for 100 polls) never drops a row: it is
# removed and the row appended.
: >"$LLOG.lock"
run "$P" "$(payload s12l UserPromptSubmit "\"prompt\":\"stale$FILL8\"")" "$ON" "$CONTENT_ON" >/dev/null
assert_exit "stale lock → exit 0" 0 "$?"
assert_eq "stale lock → the row is still appended" 21 "$(wc -l <"$LLOG" | tr -d ' ')"
assert_file_absent "stale lock → broken after the wait" "$LLOG.lock"

# Mixed sizes with content on: short rows take the lock too, so none lands
# between the 4 KB chunks of a long row.
P=$(project parallel-mixed)
FILL64=$(head -c 65000 /dev/zero | tr '\0' 'z')
for i in {1..10}; do
  run "$P" "$(payload s12m UserPromptSubmit "\"prompt\":\"$i$FILL64\"")" "$ON" "$CONTENT_ON" >/dev/null &
  run "$P" "$(payload s12m UserPromptSubmit "\"prompt\":\"s$i\"")" "$ON" "$CONTENT_ON" >/dev/null &
  run "$P" "$(payload s12m Stop)" "$ON" "$CONTENT_ON" >/dev/null &
done
wait
MLOG="$P/.observability/claude/sessions/s12m.jsonl"
assert_eq "30 parallel mixed short and 64 KB rows → 30 lines" 30 "$(wc -l <"$MLOG" | tr -d ' ')"
assert_eq "30 parallel mixed short and 64 KB rows → every line parses" 30 "$(jq -c . "$MLOG" 2>/dev/null | wc -l | tr -d ' ')"

# A live holder keeps the lock past the old 1.5 s give-up (its token changes,
# so it is not stale): the waiter appends only after the holder releases.
P=$(project live-holder)
HLOG="$P/.observability/claude/sessions/s12h.jsonl"
mkdir -p "$P/.observability/claude/sessions"
printf 'h0' >"$HLOG.lock"
(
  for t in 1 2 3 4 5 6; do
    sleep 0.5
    printf 'h%s' "$t" >|"$HLOG.lock"
  done
  printf '{"holder":"done"}\n' >>"$HLOG"
  rm -f "$HLOG.lock"
) &
run "$P" "$(payload s12h UserPromptSubmit "\"prompt\":\"w$FILL8\"")" "$ON" "$CONTENT_ON" >/dev/null
wait
assert_eq "live holder → the waiter's row lands after the holder's" "done UserPromptSubmit" \
  "$(jq -r '.holder // .hook_event_name' "$HLOG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# The read cap is bytes: 30,000 four-byte characters (120 KB) cross 64 KB.
P=$(project multibyte)
EMOJI=$(printf '\360\237\230\200')
WIDE=""
for _ in {1..30000}; do WIDE+="$EMOJI"; done
run "$P" "$(payload s14 UserPromptSubmit "\"prompt\":\"$WIDE\"")" "$ON" "$CONTENT_ON" >/dev/null
BLOG14="$P/.observability/claude/sessions/s14.jsonl"
assert_eq "multibyte prompt over 64 KB → prompt_truncated and content_truncated" "true true" \
  "$(jq -r '"\(.prompt_truncated) \(.content_truncated)"' "$BLOG14" 2>/dev/null)"
if (($(wc -c <"$BLOG14") <= 66560)); then ok "multibyte prompt → the row stays within the 64 KB cap plus metadata"; else bad "multibyte prompt → row is $(wc -c <"$BLOG14") bytes"; fi
iconv -f UTF-8 -t UTF-8 "$BLOG14" >/dev/null 2>&1
assert_exit "multibyte prompt → the cut row is valid UTF-8" 0 "$?"

# --- an unusable stdin_read_timeout falls back to the default ----------------------
# The env-block channel can deliver any string, so the schema's `min: 1` is not
# a guard here. `0` makes `read -t` return at once with nothing read, and a
# positive value under 10 µs returns before the payload's bytes arrive; both
# must fall back to the default and still write the line, as the library's
# hook::resolve_read_timeout_to does for the same variable.
for bad_timeout in 0 0.0 00 0.000001; do
  P=$(project "timeout-$bad_timeout")
  OUT=$(run "$P" "$(payload s13 PostToolUse)" "$ON" "CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=$bad_timeout")
  assert_exit "stdin_read_timeout=$bad_timeout → exit 0" 0 "$?"
  assert_silent "stdin_read_timeout=$bad_timeout → silent" "$OUT"
  assert_eq "stdin_read_timeout=$bad_timeout → falls back and writes the line" 1 \
    "$(wc -l <"$P/.observability/claude/sessions/s13.jsonl" 2>/dev/null | tr -d ' ')"
done

# --- the mod's environment writes the record the settings row wrote ---------------
# The module (register.ts) runs this script with the event's payload on stdin and
# CLAUDE_EFFORT and TRACEPARENT cleared; a settings row got CLAUDE_EFFORT from the
# payload's effort object. For each payload the two runs must write the same
# record, all but ts and duration_ms, which measure the run itself.
P=$(project parity)
PLOG() { printf '%s' "$P/.observability/claude/sessions/$1.jsonl"; }
parity_case() { # <label> <event> <payload-members> <settings-row effort or ""> [env...]
  local label="$1" event="$2" members="$3" effort="$4" row mod
  shift 4
  run "$P" "$(payload "row-$event" "$event" "$members")" "$ON" ${effort:+CLAUDE_EFFORT=$effort} "$@" >/dev/null
  run "$P" "$(payload "mod-$event" "$event" "$members")" "$ON" CLAUDE_EFFORT= TRACEPARENT= "$@" >/dev/null
  row=$(jq -cS 'del(.ts, .duration_ms, .session_id)' "$(PLOG "row-$event")" 2>/dev/null)
  mod=$(jq -cS 'del(.ts, .duration_ms, .session_id)' "$(PLOG "mod-$event")" 2>/dev/null)
  if [[ -n "$row" && "$row" == "$mod" ]]; then ok "mod env, $label: same record as the settings row"; else bad "mod env, $label: row=$row mod=$mod"; fi
}
parity_case "Stop with effort" Stop "\"effort\":{\"level\":\"high\"},$STOP_TAIL" high
parity_case "PostToolBatch" PostToolBatch '"effort":{"level":"low"},"tool_calls":[{"tool_name":"Edit","tool_use_id":"toolu_9","tool_input":{"file_path":"'"$P"'/src/a.ts"}}]' low
parity_case "SessionStart" SessionStart '"source":"startup","model":"claude-opus-5-5"' ""
parity_case "SubagentStop" SubagentStop '"stop_hook_active":false,"agent_id":"agent-7","agent_type":"Explore","last_assistant_message":"done"' ""
parity_case "UserPromptSubmit with content on" UserPromptSubmit "$PROMPT_TAIL" "" "$CONTENT_ON"
# With tracing on, a settings row got TRACEPARENT and the module gets none: the record
# loses its traceparent key and nothing else. The value is the W3C trace context example.
TP=00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
run "$P" "$(payload row-traced Stop "$STOP_TAIL")" "$ON" TRACEPARENT="$TP" >/dev/null
run "$P" "$(payload mod-traced Stop "$STOP_TAIL")" "$ON" CLAUDE_EFFORT= TRACEPARENT= >/dev/null
assert_eq "traced settings row: the record carries the row's traceparent" "$TP" "$(jq -r .traceparent "$(PLOG row-traced)")"
assert_eq "traced, mod env: the record has no traceparent key" "false" "$(jq 'has("traceparent")' "$(PLOG mod-traced)")"
row=$(jq -cS 'del(.ts, .duration_ms, .session_id, .traceparent)' "$(PLOG row-traced)" 2>/dev/null)
mod=$(jq -cS 'del(.ts, .duration_ms, .session_id)' "$(PLOG mod-traced)" 2>/dev/null)
if [[ -n "$row" && "$row" == "$mod" ]]; then ok "traced: traceparent is the only record difference"; else bad "traced: row=$row mod=$mod"; fi
run "$P" "$(payload mod-host Stop "$STOP_TAIL")" "$ON" CLAUDE_EFFORT= TRACEPARENT= >/dev/null
assert_eq "mod env: no effort object records unset, whatever the host's CLAUDE_EFFORT" "unset" "$(jq -r .effort "$(PLOG mod-host)")"

# --- the producer sources nothing from hook-utils --------------------------------
assert_eq "no hook-utils.sh source" 0 "$(grep -cE '^[[:space:]]*(source|\.)[[:space:]].*hook-utils' "$HOOK" "$HOOK_DIR/session-log-lib.sh" | awk -F: '{ s += $2 } END { print s + 0 }')"
assert_eq "kill switch is the first statement after set" 1 \
  "$(awk '/^set -uo pipefail/{f=1;next} f && NF && !/^#/ {print; exit}' "$HOOK" | grep -c 'SESSION_EVENT_LOG_ENABLED')"

report
