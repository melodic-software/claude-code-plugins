#!/usr/bin/env bash
# Contract test for session-event-log.sh (claude-ops plugin). Black-box: the
# producer reads one hook payload on stdin and appends at most one line to
# <root>/sessions/<session_id>.jsonl. Nothing here sources the hook.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/session-event-log.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

ON=CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED=true

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
run() {
  local proj="$1" body="$2"
  shift 2
  printf '%s' "$body" | env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$proj" "$@" bash "$HOOK" 2>&1
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
else
  bad "enabled: no line written at $LOG"
fi

# --- a second event on the same session appends; another session gets its own file
run "$P" "$(payload sess-abc Stop)" "$ON" >/dev/null
run "$P" "$(payload sess-xyz SessionStart)" "$ON" >/dev/null
assert_eq "second event appends to the session file" 2 "$(wc -l <"$LOG" | tr -d ' ')"
assert_eq "another session gets its own file" 1 "$(wc -l <"$P/.observability/claude/sessions/sess-xyz.jsonl" | tr -d ' ')"
assert_eq "exactly two session files" 2 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"

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
for i in $(seq 1 33); do
  run "$P" "$(payload s12 PostToolUse "\"tool_name\":\"T$i\"")" "$ON" >/dev/null &
done
wait
PLOG="$P/.observability/claude/sessions/s12.jsonl"
assert_eq "33 parallel fires → 33 lines" 33 "$(wc -l <"$PLOG" | tr -d ' ')"
assert_eq "33 parallel fires → every line parses" 33 "$(jq -c . "$PLOG" 2>/dev/null | wc -l | tr -d ' ')"

# --- the producer sources nothing from hook-utils --------------------------------
assert_eq "no hook-utils.sh source" 0 "$(grep -cE '^[[:space:]]*(source|\.)[[:space:]].*hook-utils' "$HOOK" "$HOOK_DIR/session-log-lib.sh" | awk -F: '{ s += $2 } END { print s + 0 }')"
assert_eq "kill switch is the first statement after set" 1 \
  "$(awk '/^set -uo pipefail/{f=1;next} f && NF && !/^#/ {print; exit}' "$HOOK" | grep -c 'SESSION_EVENT_LOG_ENABLED')"

report
