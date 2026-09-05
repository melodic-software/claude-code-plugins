#!/usr/bin/env bash
# Contract test for session-retention.sh (claude-ops plugin). Black-box over a
# fixture log root; mtimes are staged with POSIX `touch -t` from a bash
# builtin timestamp, and process spawns are counted through PATH shims.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/session-retention.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

ON=CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED=true

# stamp_to <var> <days-ago>: a `touch -t` timestamp that many days in the past.
stamp_to() {
  printf -v "$1" '%(%Y%m%d%H%M)T' "$((EPOCHSECONDS - $2 * 86400))"
}

# populate <root> <count>: <count> session files, file i being i days old
# (file 1 newest), so recency order and age agree and the union rule is exact.
populate() {
  local root="$1" n="$2" i st
  mkdir -p "$root/sessions"
  for ((i = 1; i <= n; i++)); do
    printf '{"session_id":"s%03d"}\n' "$i" >"$root/sessions/s$(printf '%03d' "$i").jsonl"
    stamp_to st "$i"
    touch -t "$st" "$root/sessions/s$(printf '%03d' "$i").jsonl"
  done
}

# Spawn-counting shims: every process the hook may start is logged, then
# delegated to the real binary.
SHIM="$TEST_TMPDIR/shim"
SPAWNS="$TEST_TMPDIR/spawns"
mkdir -p "$SHIM"
for b in ls find mv rm nohup; do
  real=$(command -v "$b")
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >>"%s"\nexec "%s" "$@"\n' "$b" "$SPAWNS" "$real" >"$SHIM/$b"
  chmod +x "$SHIM/$b"
done

# run <project> [env...]: no stdin is offered at all (the hook must not read it).
run() {
  local proj="$1"
  shift
  : >"$SPAWNS"
  env CLAUDE_PROJECT_DIR="$proj" PATH="$SHIM:$PATH" "$@" bash "$HOOK" </dev/null >/dev/null 2>&1
}

# --- disabled: nothing happens ----------------------------------------------
P="$TEST_TMPDIR/off"
populate "$P/.observability/claude" 40
run "$P"
assert_eq "disabled → every file kept" 40 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"
assert_eq "disabled → no process spawned" 0 "$(wc -l <"$SPAWNS" | tr -d ' ')"

# --- the union rule: keep newest N or younger than D days -------------------
# 100 files, file i is i days old. keep 30 sessions / 14 days: files 1..30
# are protected by count, files 1..14 by age; doomed = 31..100 (70 files).
P="$TEST_TMPDIR/union"
populate "$P/.observability/claude" 100
t0=$EPOCHREALTIME
run "$P" "$ON"
t1=$EPOCHREALTIME
kept=$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')
assert_eq "100 files, 30/14 → 30 kept" 30 "$kept"
assert_eq "the newest 30 are the survivors" "s001.jsonl s030.jsonl" \
  "$(find "$P/.observability/claude/sessions" -name '*.jsonl' -exec basename {} \; | sort | sed -n '1p;$p' | tr '\n' ' ' | sed 's/ $//')"
# Three processes on a first prune (ls, find, rm); the pending sweep's find
# is paid only once a prune-pending directory exists.
assert_eq "a pruning run spawns three processes (ls, find, rm)" 3 "$(wc -l <"$SPAWNS" | tr -d ' ')"
# No stdin read: a writer that holds the pipe open for 3 s (the Win32 late-EOF
# shape) must not delay the hook at all. Measured on the reading side, because
# the pipeline as a whole only ends when the writer does.
P2="$TEST_TMPDIR/heldopen"
populate "$P2/.observability/claude" 40
held_ms=$(
  {
    printf '{"session_id":"x","hook_event_name":"SessionEnd","reason":"other"}'
    sleep 3
  } |
    {
      h0=$EPOCHREALTIME
      env CLAUDE_PROJECT_DIR="$P2" PATH="$SHIM:$PATH" "$ON" bash "$HOOK" >/dev/null 2>&1
      h1=$EPOCHREALTIME
      awk -v a="$h0" -v b="$h1" 'BEGIN { printf "%d", (b - a) * 1000 }'
    }
)
if ((held_ms < 500)); then
  ok "no stdin read: a held-open stdin does not delay the hook (${held_ms} ms)"
else
  bad "no stdin read: the hook waited on stdin (${held_ms} ms)"
fi
assert_eq "held-open stdin: the prune still ran" 30 "$(find "$P2/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"
printf 'info: 100-file prune took %s ms\n' "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"

# keep by age beyond the count: 50 sessions / 1 day → files 1..50 by count,
# files younger than 1 day: none older than the count, so 50 kept.
P="$TEST_TMPDIR/bycount"
populate "$P/.observability/claude" 60
run "$P" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS=50 CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS=1
assert_eq "count protects beyond age" 50 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"
# keep by age beyond the count: 5 sessions / 40 days on 60 files → all younger
# than 40 days are kept (files 1..39), the rest doomed.
P="$TEST_TMPDIR/byage"
populate "$P/.observability/claude" 60
run "$P" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS=5 CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS=40
kept=$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')
if ((kept >= 39 && kept <= 40)); then ok "age protects beyond count ($kept kept)"; else bad "age protects beyond count: kept $kept"; fi

# --- under the count nothing is touched, and an empty root is fine -----------
P="$TEST_TMPDIR/few"
populate "$P/.observability/claude" 10
run "$P" "$ON"
assert_eq "10 files under keep 30 → untouched" 10 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"
P="$TEST_TMPDIR/empty"
mkdir -p "$P/.observability/claude/sessions"
run "$P" "$ON"
assert_exit "empty sessions dir → exit 0" 0 "$?"
P="$TEST_TMPDIR/noroot"
mkdir -p "$P"
run "$P" "$ON"
assert_exit "no root at all → exit 0" 0 "$?"

# --- invalid knobs fall back to the defaults --------------------------------------
P="$TEST_TMPDIR/knobs"
populate "$P/.observability/claude" 100
run "$P" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS=zero CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS=-3
assert_eq "invalid knobs → defaults (30/14)" 30 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"

# --- pre-prune command: files move aside, the command runs detached ---------------
P="$TEST_TMPDIR/archiver"
populate "$P/.observability/claude" 40
ARCHIVE_LOG="$TEST_TMPDIR/archiver.log"
CMD="printf '%s\\n' \"\$1\" >>\"$ARCHIVE_LOG\"; sleep 30"
t0=$EPOCHREALTIME
run "$P" "$ON" CLAUDE_PLUGIN_OPTION_SESSION_LOG_PRE_PRUNE_COMMAND="$CMD"
t1=$EPOCHREALTIME
elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')
if ((elapsed < 1000)); then ok "a sleeping archiver does not delay the hook (${elapsed} ms)"; else bad "hook waited on the archiver: ${elapsed} ms"; fi
assert_eq "sessions/ pruned to the kept 30" 30 "$(find "$P/.observability/claude/sessions" -name '*.jsonl' | wc -l | tr -d ' ')"
pending=$(find "$P/.observability/claude/prune-pending" -mindepth 1 -maxdepth 1 -type d | head -1)
assert_eq "doomed files moved into one pending directory" 10 "$(find "$pending" -name '*.jsonl' | wc -l | tr -d ' ')"
wait_for_sink "$ARCHIVE_LOG" 100
assert_eq "the archiver received the pending directory as its argument" "$pending" "$(head -1 "$ARCHIVE_LOG" 2>/dev/null)"
# The sleeping archiver is detached; it must not keep the test alive.
pkill -f 'sleep 30' 2>/dev/null || true

# --- a pending directory is swept only once it is older than 24 h ----------------
P="$TEST_TMPDIR/sweep"
populate "$P/.observability/claude" 5
mkdir -p "$P/.observability/claude/prune-pending/1-old" "$P/.observability/claude/prune-pending/2-fresh"
stamp_to st 2
touch -t "$st" "$P/.observability/claude/prune-pending/1-old"
run "$P" "$ON"
assert_file_absent "a pending directory older than 24 h is swept" "$P/.observability/claude/prune-pending/1-old"
if [[ -d "$P/.observability/claude/prune-pending/2-fresh" ]]; then
  ok "a fresh pending directory is left for its archiver"
else
  bad "fresh pending directory was swept"
fi

# --- the hook sources nothing from hook-utils ------------------------------------------
assert_eq "no hook-utils.sh source" 0 "$(grep -cE '^[[:space:]]*(source|\.)[[:space:]].*hook-utils' "$HOOK")"

report
