#!/usr/bin/env bash
# Regression tests for /observability skill jq pipelines + privacy filter.
# Validates the queries in context/data-sources.md and rules in context/privacy.md
# against synthetic JSONL fixtures.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Fixture: a hook log root ---
# The shared file (legacy rows, `event` key) plus one per-session file whose
# envelope rows carry `hook_event_name` and `source: "envelope"`. Every
# whole-root query reads both through the HOOK_NORM prelude in data-sources.md.
HOOK_ROOT="$TEST_TMPDIR/root"
mkdir -p "$HOOK_ROOT/sessions"
HOOK_LOG="$HOOK_ROOT/hook-events.jsonl"
SESSION_LOG="$HOOK_ROOT/sessions/s-a.jsonl"
SINCE_ISO="2026-01-01T00:00:00Z"
HOOK_NORM='map(. + {event: (.event // .hook_event_name)})'

# Append a single legacy event to the shared file. Schema mirrors observability/conventions.md fields;
# session_id/branch/cwd are constant across the fixture (no test asserts on them).
# Args: <ts> <hook> <tool> <duration_ms> <exit_code> <subject> <status>
emit_event() {
  jq -nc \
    --arg ts "$1" --arg hook "$2" --arg tool "$3" \
    --argjson duration_ms "$4" --argjson exit_code "$5" \
    --arg subject "$6" --arg status "$7" \
    '{ts:$ts, event:"PostToolUse", hook:$hook, tool:$tool,
      duration_ms:$duration_ms, exit_code:$exit_code,
      subject:$subject, status:$status,
      session_id:"s1", branch:"main", cwd:"/repo"}' \
    >>"$HOOK_LOG"
}
# Append one per-session envelope row (the reference sink's per-session shape).
# Args: <ts> <hook> <event> <duration_ms> <exit_code> <subject> <status>
emit_session_event() {
  jq -nc \
    --arg ts "$1" --arg hook "$2" --arg ev "$3" \
    --argjson duration_ms "$4" --argjson exit_code "$5" \
    --arg subject "$6" --arg status "$7" \
    '{ts:$ts, session_id:"s-a", hook_event_name:$ev, status:$status,
      duration_ms:$duration_ms, source:"envelope", hook:$hook,
      exit_code:$exit_code, subject:$subject, tool:"Write"}' \
    >>"$SESSION_LOG"
}
# Append one per-session event-log row (session-event-log.sh's shape). No hook.
# Args: <ts> <event> <category> [tool_name] [file_path]
emit_log_row() {
  jq -nc --arg ts "$1" --arg ev "$2" --arg cat "$3" --arg tool "${4:-}" --arg file "${5:-}" \
    '{ts:$ts, session_id:"s-a", hook_event_name:$ev, category:$cat, status:"ok",
      source:"event-log", duration_ms:1, prompt_id:"p-1"}
     + (if $tool == "" then {} else {tool_name:$tool} end)
     + (if $file == "" then {} else {file_path:$file} end)' \
    >>"$SESSION_LOG"
}

# Count lines in a JSONL fixture, stripping spaces and Git Bash CR.
lines_in() {
  wc -l <"$1" | tr -d ' \r'
}

# 12 bash-format events: 10 fast (~120ms), 2 slow (5000ms+ outliers)
for i in $(seq 1 10); do
  emit_event "2026-04-29T10:0${i}:00.000Z" bash-format Write 120 0 test.sh success
done
emit_event "2026-04-29T10:11:00.000Z" bash-format Write 5000 0 slow.sh success
emit_event "2026-04-29T10:12:00.000Z" bash-format Write 6000 0 slower.sh success

# 5 sarif-diagnostics events with 1 error
for i in $(seq 1 4); do
  emit_event "2026-04-29T11:0${i}:00.000Z" sarif-diagnostics Edit 800 0 a.cs success
done
emit_event "2026-04-29T11:05:00.000Z" sarif-diagnostics Edit 1200 2 b.cs error

# Out-of-window event (should be filtered)
emit_event "2025-01-01T00:00:00.000Z" old-hook Write 100 0 old.sh success

# Per-session file: two more bash-format fires, one blocked guard, and event-log
# rows (which carry no hook and must never count as a hook fire).
emit_session_event "2026-04-29T12:01:00.000Z" bash-format PostToolUse 130 0 s.sh success
emit_session_event "2026-04-29T12:02:00.000Z" bash-format PostToolUse 140 0 t.sh success
emit_session_event "2026-04-29T12:03:00.000Z" block-dangerous-git PreToolUse 7 2 "Bash:git push --force" blocked
emit_log_row "2026-04-29T12:00:59.000Z" PreToolUse tool Write s.sh
emit_log_row "2026-04-29T12:01:00.500Z" PostToolUse tool Write s.sh
emit_log_row "2026-04-29T12:05:00.000Z" Stop turn

# The whole-root file set, as data-sources.md builds it.
shopt -s nullglob
HOOK_FILES=("$HOOK_ROOT"/sessions/*.jsonl)
shopt -u nullglob
[[ -f "$HOOK_LOG" ]] && HOOK_FILES+=("$HOOK_LOG")
assert_eq "file set: one session file plus the shared file" "2" "${#HOOK_FILES[@]}"

# --- Test 1: latency p50/p95 per (hook,event) across the root ---
LAT_OUT=$(jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null))
  | group_by(.hook + "|" + .event)
  | map({
      key: (.[0].hook + " " + .[0].event),
      n: length,
      p50: (sort_by(.duration_ms) | .[length/2|floor].duration_ms),
      p95: (sort_by(.duration_ms) | .[(length*0.95)|floor].duration_ms),
      max: (max_by(.duration_ms).duration_ms)
    })' "${HOOK_FILES[@]}")

assert_contains "bash-format key present" "$LAT_OUT" "bash-format PostToolUse"
assert_contains "sarif-diagnostics key present" "$LAT_OUT" "sarif-diagnostics PostToolUse"
assert_contains "a per-session envelope row keys on hook_event_name" "$LAT_OUT" "block-dangerous-git PreToolUse"

bash_format_n=$(echo "$LAT_OUT" | jq -r '.[] | select(.key=="bash-format PostToolUse") | .n')
assert_eq "bash-format count = 14 (12 shared + 2 per-session)" "14" "$bash_format_n"

bash_format_max=$(echo "$LAT_OUT" | jq -r '.[] | select(.key=="bash-format PostToolUse") | .max')
assert_eq "bash-format max = 6000" "6000" "$bash_format_max"

# --- Test 2: error rate per hook ---
ERR_OUT=$(jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null))
  | group_by(.hook)
  | map({
      hook: .[0].hook,
      n: length,
      errors: (map(select(.exit_code != 0)) | length)
    })
  | map(select(.errors > 0))' "${HOOK_FILES[@]}")

assert_contains "sarif-diagnostics has errors" "$ERR_OUT" "sarif-diagnostics"
sarif_err=$(echo "$ERR_OUT" | jq -r '.[] | select(.hook=="sarif-diagnostics") | .errors')
assert_eq "sarif error count = 1" "1" "$sarif_err"
assert_contains "a blocked per-session row counts as an error" "$ERR_OUT" "block-dangerous-git"

# --- Test 3: window filter excludes 2025 event; event-log rows never count as hooks ---
filtered_count=$(jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null)) | length' "${HOOK_FILES[@]}")
assert_eq "window filter applied" "20" "$filtered_count" # 12 + 5 + 3 (excludes old-hook and the 3 event-log rows)

assert_not_contains "out-of-window event excluded" "$LAT_OUT" "old-hook"

# --- Test 3.5: the per-session report (data-sources.md §2.5) ---
SESSION_FILES=("$SESSION_LOG")
FIRED=$(jq -s "$HOOK_NORM"' | map(select(.source == "envelope"))
  | group_by(.hook)
  | map({hook: .[0].hook, n: length,
         events: (map(.event) | unique),
         errors: (map(select(.exit_code != 0)) | length),
         p50_ms: (sort_by(.duration_ms) | .[length/2|floor].duration_ms),
         max_ms: (max_by(.duration_ms).duration_ms)})
  | sort_by(-.n)' "${SESSION_FILES[0]}")
assert_eq "per-session: two hooks fired" "2" "$(echo "$FIRED" | jq 'length')"
assert_eq "per-session: bash-format fired twice" "2" "$(echo "$FIRED" | jq -r '.[] | select(.hook=="bash-format") | .n')"
assert_eq "per-session: event-log rows are not hook fires" "0" "$(echo "$FIRED" | jq '[.[] | select(.hook == null)] | length')"

BLOCKED=$(jq -sc "$HOOK_NORM"' | .[] | select(.status == "blocked") | {ts, hook, event, subject}' "${SESSION_FILES[0]}")
assert_eq "per-session: one blocked row" "1" "$(printf '%s\n' "$BLOCKED" | grep -c .)"
assert_contains "per-session: blocked row names the hook" "$BLOCKED" "block-dangerous-git"

REWROTE=$(jq -sc "$HOOK_NORM"' | .[] | select(.changed == true) | {ts, hook, subject}' "${SESSION_FILES[0]}")
assert_eq "per-session: rewrote is empty until a producer emits changed" "" "$REWROTE"

TIMELINE=$(jq -sr '.[] | select(.source == "event-log")
  | [.ts, .hook_event_name, .category, (.tool_name // ""), (.file_path // ""), (.agent_id // "")]
  | @tsv' "${SESSION_FILES[0]}")
assert_eq "per-session: timeline has the three event-log rows" "3" "$(printf '%s\n' "$TIMELINE" | grep -c .)"
assert_contains "per-session: timeline carries the tool and file" "$TIMELINE" "PreToolUse	tool	Write	s.sh"

# session:<id> names one file; `session` is the newest by mtime.
sleep 1
printf '%s\n' '{"ts":"2026-04-30T00:00:00Z","session_id":"s-b","hook_event_name":"Stop","category":"turn","status":"ok","source":"event-log","duration_ms":1}' >"$HOOK_ROOT/sessions/s-b.jsonl"
SCOPE="session:s-a"
assert_eq "session:<id> resolves the named file" "$SESSION_LOG" "$HOOK_ROOT/sessions/${SCOPE#session:}.jsonl"
# shellcheck disable=SC2012  # mtime order is the documented resolution; names are hook-validated ids
NEWEST="$(ls -t "$HOOK_ROOT"/sessions/*.jsonl 2>/dev/null | head -n 1)"
assert_eq "session resolves the newest file by mtime" "$HOOK_ROOT/sessions/s-b.jsonl" "$NEWEST"

# --- Test 4: redaction — token-shaped strings ---
redact() {
  sed -E 's|[A-Za-z0-9+/_-]{32,}={0,2}|[redacted-token]|g'
}

# Synthetic 40-char base64-shaped string (clearly fake — XYZ prefix + repeating chars)
fake_token='XYZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1234'
token_input="some_field=${fake_token}"
redacted=$(echo "$token_input" | redact)
assert_contains "long base64-shaped string redacted" "$redacted" "[redacted-token]"
assert_not_contains "raw fake token absent" "$redacted" "$fake_token"

# --- Test 5: redaction — env-var assignment ---
env_redact() {
  sed -E 's/(AWS_[A-Z_]*|GITHUB_[A-Z_]*|.*_TOKEN|.*_KEY|.*_SECRET|.*_PASSWORD)=[^[:space:]"]*/\1=[redacted]/gi'
}

env_input='subject contains GITHUB_TOKEN=placeholder123 in error log' # gitleaks:allow — synthetic fixture proving this very value gets redacted
env_redacted=$(echo "$env_input" | env_redact)
assert_contains "GITHUB_TOKEN redacted" "$env_redacted" "GITHUB_TOKEN=[redacted]"
assert_not_contains "raw value absent" "$env_redacted" "placeholder123"

# --- Test 6: paths are NOT redacted (normal paths must survive) ---
path_input='subject=apps/monolith-api/Program.cs'
path_after=$(echo "$path_input" | env_redact)
assert_contains "path preserved through env filter" "$path_after" "apps/monolith-api/Program.cs"

# --- Test 7: empty-log graceful degradation ---
EMPTY_LOG="$TEST_TMPDIR/empty.jsonl"
: >"$EMPTY_LOG"
empty_out=$(jq -s --arg since "$SINCE_ISO" \
  'map(select(.ts >= $since)) | length' "$EMPTY_LOG")
assert_eq "empty log returns 0" "0" "$empty_out"

# --- Test 8: missing-log handled by caller guard ---
MISSING_LOG="$TEST_TMPDIR/does-not-exist.jsonl"
if [[ -f "$MISSING_LOG" ]]; then
  count=$(jq -s 'length' "$MISSING_LOG")
else
  count=0
fi
assert_eq "missing log handled by guard" "0" "$count"

# --- Test 9: clean action — synthetic mixed-age data + dry-run + real run ---
CLEAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/clean.sh"
clean_test_dir="$TEST_TMPDIR/clean-test"
mkdir -p "$clean_test_dir"
(cd "$clean_test_dir" && git init -q && git config commit.gpgsign false)
mkdir -p "$clean_test_dir/.claude/observability"
TODAY=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# portability-ok: GNU-first dual-dialect probe, BSD branch in the else below (#1510)
if date -u -d "45 days ago" +%s >/dev/null 2>&1; then
  OLD_45=$(date -u -d "45 days ago" +%Y-%m-%dT%H:%M:%SZ) # portability-ok: see if-guard above (#1510)
  OLD_5=$(date -u -d "5 days ago" +%Y-%m-%dT%H:%M:%SZ)   # portability-ok: see if-guard above (#1510)
else
  OLD_45=$(date -u -v-45d +%Y-%m-%dT%H:%M:%SZ)
  OLD_5=$(date -u -v-5d +%Y-%m-%dT%H:%M:%SZ)
fi
HOOK_FX="$clean_test_dir/.claude/observability/hook-events.jsonl"
for _ in 1 2 3; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$OLD_45" >>"$HOOK_FX"
done
for _ in 1 2; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$OLD_5" >>"$HOOK_FX"
done
for _ in 1 2; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$TODAY" >>"$HOOK_FX"
done

# 9a: dry-run does not modify
before_hook=$(lines_in "$HOOK_FX")
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --dry-run --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean --dry-run preserves hook log" "$before_hook" "$after_hook"

# 9b: real run with --keep-days 30 prunes 45-day-old (3 hook)
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean prunes 45-day-old hook events" "4" "$after_hook" # 2 (5d) + 2 (today)

# 9c: --keep-days 4 prunes the 5-day-old hook events (2)
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 4 --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean --keep-days 4 prunes 5-day-old" "2" "$after_hook" # only today's 2 remain

# 9d: idempotent — re-run with same window changes nothing
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 4 --quiet) >/dev/null 2>&1
after_hook2=$(lines_in "$HOOK_FX")
assert_eq "clean is idempotent" "$after_hook" "$after_hook2"

# --- 9s: skill-usage target (opt-in; its own window; its own resolved location) ---
# The rollback property is asserted first and is the important one: with no
# skill-usage flag this script must behave byte-for-byte as it did before the
# target existed, so reverting the feature is dropping one branch.
SU_FX="$clean_test_dir/.claude/observability/skill-usage.jsonl"
: >"$SU_FX"
for _ in 1 2 3; do
  printf '{"ts":"%s","event":"SkillUse","skill":"a:one","source":"tool"}\n' "$OLD_45" >>"$SU_FX"
done
printf '{"ts":"%s","event":"SkillUse","skill":"b:two","source":"expansion"}\n' "$TODAY" >>"$SU_FX"

# 9s-a: inert without the flag — the 45-day rows survive a 30-day hook prune.
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1
assert_eq "clean leaves skill-usage untouched without its flag" "4" "$(lines_in "$SU_FX")"

# 9s-b: opted in with a long window, the same old rows still survive — proving
# the target uses ITS OWN window rather than inheriting --keep-days.
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --skill-usage-scope repo --quiet) >/dev/null 2>&1
assert_eq "skill-usage uses its own 365d window, not --keep-days" "4" "$(lines_in "$SU_FX")"

# 9s-c: dry-run reports the resolved target without modifying it.
su_out=$(cd "$clean_test_dir" && bash "$CLEAN" --dry-run --skill-usage-scope repo 2>&1 || true)
assert_contains "clean --dry-run names the skill-usage target" "$su_out" "skill-usage target"
assert_eq "clean --dry-run preserves skill-usage" "4" "$(lines_in "$SU_FX")"

# 9s-d: a short window does prune, so the branch is real and not inert.
(cd "$clean_test_dir" && bash "$CLEAN" --skill-usage-scope repo --keep-skill-usage-days 4 --quiet) >/dev/null 2>&1
assert_eq "skill-usage prunes at its own short window" "1" "$(lines_in "$SU_FX")"

# 9s-d2: data-dir HAPPY PATH — the branch must reach the store the WRITER
# actually produces (<data-root>/skill-usage/<repo-slug>), not a repo-relative
# path. Without this the branch could abort or prune the wrong file and no test
# would notice.
su_data_root="$TEST_TMPDIR/plugin-data"
su_slug_dir="$su_data_root/skill-usage/$(basename "$clean_test_dir")-$(printf '%s' "$clean_test_dir" | sha1sum | cut -c1-8)"
mkdir -p "$su_slug_dir"
printf '{"ts":"%s","event":"SkillUse","skill":"old:one"}\n' "$OLD_45" >"$su_slug_dir/skill-usage.jsonl"
printf '{"ts":"%s","event":"SkillUse","skill":"new:two"}\n' "$TODAY" >>"$su_slug_dir/skill-usage.jsonl"
su_dd_out=$(cd "$clean_test_dir" && bash "$CLEAN" --dry-run --skill-usage-scope data-dir --skill-usage-data-root "$su_data_root" 2>&1 || true)
assert_contains "data-dir resolves under the plugin data root" "$su_dd_out" "$su_data_root/skill-usage/"

# 9s-e: data-dir refuses to guess a location. CLAUDE_PLUGIN_DATA in a skill
# subprocess was observed pointing at an UNRELATED plugin's data directory, so a
# delete path is never derived from it.
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --skill-usage-scope data-dir --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "data-dir scope demands an explicit dir (exit 2)" "2" "$rc"

# 9s-f: a traversing dir is refused rather than resolved.
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --skill-usage-scope repo --skill-usage-dir ../../etc --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "traversal in --skill-usage-dir rejected (exit 2)" "2" "$rc"

# 9s-g: an unknown scope is refused rather than defaulted.
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --skill-usage-scope nonsense --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "unknown skill-usage scope rejected (exit 2)" "2" "$rc"

# 9e: missing files don't crash
empty_dir="$TEST_TMPDIR/empty-clean"
mkdir -p "$empty_dir"
(cd "$empty_dir" && git init -q && git config commit.gpgsign false)
mkdir -p "$empty_dir/.claude/observability"
rc=0
(cd "$empty_dir" && bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean handles missing files (exit 0)" "0" "$rc"

# 9f: invalid --keep-days rejected
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days notanumber --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean rejects non-integer --keep-days (exit 2)" "2" "$rc"

# 9g: OTEL store wiring — clean delegates to otel/prune-otel-store.sh (dry-run, non-destructive).
# env -u CC_OTEL_STORE forces the store to resolve to the temp repo regardless of any
# machine-level CC_OTEL_STORE.
mkdir -p "$clean_test_dir/.claude/observability/otel"
otel_now=$EPOCHSECONDS
otel_logs="$clean_test_dir/.claude/observability/otel/cc-logs.json"
printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s"}]}]}]}\n' "$((otel_now - 3600))000000000" >"$otel_logs"
printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s"}]}]}]}\n' "$((otel_now - 30 * 86400))000000000" >>"$otel_logs"
otel_before=$(lines_in "$otel_logs")
otel_out=$(cd "$clean_test_dir" && env -u CC_OTEL_STORE bash "$CLEAN" --keep-days 30 --dry-run 2>&1)
assert_contains "clean wires OTEL prune (dry-run report)" "$otel_out" "cc-logs.json: kept=1 dropped=1"
otel_after=$(lines_in "$otel_logs")
assert_eq "clean --dry-run leaves OTEL store unchanged" "$otel_before" "$otel_after"

# --- Test 9h: the hook log root — session files, stale prune sets, the new shared file ---
NEW_ROOT="$clean_test_dir/.observability/claude"
mkdir -p "$NEW_ROOT/sessions" "$NEW_ROOT/prune-pending/1000-old" "$NEW_ROOT/prune-pending/2000-fresh"
printf '*\n' >"$NEW_ROOT/.gitignore"
printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$OLD_45" >"$NEW_ROOT/hook-events.jsonl"
printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$TODAY" >>"$NEW_ROOT/hook-events.jsonl"
printf '{"a":1}\n' >"$NEW_ROOT/sessions/stale.jsonl"
printf '{"a":1}\n' >"$NEW_ROOT/sessions/live.jsonl"
touch -t 202601010000 "$NEW_ROOT/sessions/stale.jsonl" "$NEW_ROOT/prune-pending/1000-old"

root_dry=$(cd "$clean_test_dir" && env -u CC_OTEL_STORE bash "$CLEAN" --keep-days 30 --dry-run 2>&1)
assert_contains "clean --dry-run names the hook log root" "$root_dry" "hook log root $NEW_ROOT"
assert_contains "clean --dry-run counts stale session files" "$root_dry" "sessions/: 1 file(s) untouched for 30 days → would remove"
assert_contains "clean --dry-run counts stale prune sets" "$root_dry" "prune-pending/: 1 set(s) older than 24 h → would sweep"
if [[ -f "$NEW_ROOT/sessions/stale.jsonl" ]]; then
  pass "clean --dry-run leaves the stale session file"
else
  fail "clean --dry-run leaves the stale session file" "present" "removed"
fi

(cd "$clean_test_dir" && env -u CC_OTEL_STORE bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1
if [[ ! -e "$NEW_ROOT/sessions/stale.jsonl" && -e "$NEW_ROOT/sessions/live.jsonl" ]]; then
  pass "clean removes the stale session file and keeps the live one"
else
  fail "clean removes the stale session file and keeps the live one" "stale gone, live kept" "$(ls "$NEW_ROOT/sessions")"
fi
if [[ ! -e "$NEW_ROOT/prune-pending/1000-old" && -e "$NEW_ROOT/prune-pending/2000-fresh" ]]; then
  pass "clean sweeps the prune set older than 24 h and keeps the fresh one"
else
  fail "clean sweeps the prune set older than 24 h and keeps the fresh one" "old swept, fresh kept" "$(ls "$NEW_ROOT/prune-pending")"
fi
assert_eq "clean prunes the root's shared file line by line" "1" "$(lines_in "$NEW_ROOT/hook-events.jsonl")"
assert_eq "clean leaves the root's guard alone" "*" "$(head -1 "$NEW_ROOT/.gitignore")"

# --hook-root moves the root; an uncontained value is refused.
ALT_ROOT="$clean_test_dir/telemetry/hooks"
mkdir -p "$ALT_ROOT/sessions"
printf '{"a":1}\n' >"$ALT_ROOT/sessions/old.jsonl"
touch -t 202601010000 "$ALT_ROOT/sessions/old.jsonl"
(cd "$clean_test_dir" && env -u CC_OTEL_STORE bash "$CLEAN" --keep-days 30 --hook-root telemetry/hooks --quiet) >/dev/null 2>&1
if [[ ! -e "$ALT_ROOT/sessions/old.jsonl" ]]; then
  pass "clean --hook-root prunes the moved root"
else
  fail "clean --hook-root prunes the moved root" "old.jsonl removed" "present"
fi
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --hook-root ../outside --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean refuses an uncontained --hook-root (exit 2)" "2" "$rc"
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --hook-root . --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean refuses a root-equivalent --hook-root (exit 2)" "2" "$rc"

# --- Test 10: failed-then-fixed sequence detection (data-sources.md query) ---
retry_log="$TEST_TMPDIR/retry-events.jsonl"
printf '%s\n' \
  '{"ts":"2026-01-01T10:00:00Z","hook":"bash-format","exit_code":1}' \
  '{"ts":"2026-01-01T10:00:05Z","hook":"bash-format","exit_code":0}' \
  '{"ts":"2026-01-01T10:01:00Z","hook":"biome","exit_code":0}' \
  '{"ts":"2026-01-01T10:02:00Z","hook":"bash-format","exit_code":1}' \
  '{"ts":"2026-01-01T10:02:05Z","hook":"bash-format","exit_code":0}' >"$retry_log"
retry_out=$(jq -s "$HOOK_NORM"' | map(select(.hook != null)) | sort_by(.ts) as $e
  | [range(1; $e | length)
     | select($e[. - 1].hook == $e[.].hook and $e[. - 1].exit_code != 0 and $e[.].exit_code == 0)
     | $e[. - 1].hook]
  | group_by(.) | map({hook: .[0], retries: length})
  | sort_by(-.retries)
' "$retry_log")
assert_eq "failed-then-fixed counts bash-format retries" \
  "$(echo '[{"hook":"bash-format","retries":2}]' | jq -c .)" "$(echo "$retry_out" | jq -c .)"

# --- Summary ---
TOTAL=$CASE_NUM
PASSED=$((TOTAL - FAILED))
printf '\n--- Results: %d/%d passed ---\n' "$PASSED" "$TOTAL"
[[ $FAILED -eq 0 ]] || exit 1
