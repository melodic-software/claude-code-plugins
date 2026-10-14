#!/usr/bin/env bash
# Black-box contract tests for hook-transcript-timing.sh against a hand-built transcript
# (fixtures/hook-timing-transcript.jsonl). Every expected number is computed by hand from the
# fixture's durationMs values:
#   Stop summaries: a.sh 100,200,900 (median 200); touch-hook 300,500,100 (median 300);
#     slowest hook per firing 300,500,900 -> p50 500, p95 860 (linear: 500 + 0.9 * 400).
#     A Stop attachment of 5000 ms must be skipped: the summary already holds Stop.
#   PreToolUse attachments: guard.sh 40,60,80 (median 60); lint.sh 120,20 (median 70);
#     firings t1 max 120, t2 60, t3 80 -> p50 80, p95 116 (80 + 0.9 * 40).
#   UserPromptSubmit: ctx.sh 30.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT="$SCRIPT_DIR/hook-transcript-timing.sh"
readonly FIXTURE="$SCRIPT_DIR/fixtures/hook-timing-transcript.jsonl"
readonly TAB=$'\t'

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

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: jq not found\n' >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'Stop\tbash a.sh\n# a comment\nPreToolUse\tbash guard.sh\nPostToolUse\tbash fmt.sh\n\nSessionStart\tbash never.sh\n' >"$TMP/enabled.tsv"

run() { # <args...>, run from $TMP so a hook that executed would leave hook-ran there
  out="$(cd "$TMP" && bash "$SCRIPT" "$@" 2>&1)"
  rc=$?
}

run --enabled "$TMP/enabled.tsv" "$FIXTURE"
assert_eq "per-hook view exits 0" 0 "$rc"
assert_contains "Stop a.sh: 3 samples, median 200" "$out" "Stop${TAB}3${TAB}200${TAB}complete${TAB}bash a.sh"
assert_contains "Stop touch-hook: 3 samples, median 300" "$out" "Stop${TAB}3${TAB}300${TAB}complete${TAB}touch hook-ran"
assert_contains "PreToolUse guard.sh: 3 sampled, median 60" "$out" "PreToolUse${TAB}3${TAB}60${TAB}sampled${TAB}bash guard.sh"
assert_contains "PreToolUse lint.sh: 2 sampled, median 70" "$out" "PreToolUse${TAB}2${TAB}70${TAB}sampled${TAB}bash lint.sh"
assert_contains "an attachment without toolUseID counts" "$out" "UserPromptSubmit${TAB}1${TAB}30${TAB}sampled${TAB}bash ctx.sh"
slowest="$(sed -n '/^slowest hook per event/,/^$/p' <<<"$out")"
assert_contains "slowest Stop hook is the touch hook at 300" "$slowest" "Stop${TAB}300${TAB}touch hook-ran"
assert_contains "slowest PreToolUse hook is lint.sh at 70" "$slowest" "PreToolUse${TAB}70${TAB}bash lint.sh"
assert_not_contains "no per-event sum (200 + 300)" "$slowest" "500"
unsampled="$(sed -n '/^unsampled enabled hooks/,$p' <<<"$out")"
assert_contains "enabled PostToolUse hook with no record is unsampled" "$unsampled" "PostToolUse${TAB}bash fmt.sh"
assert_contains "enabled SessionStart hook with no record is unsampled" "$unsampled" "SessionStart${TAB}bash never.sh"
assert_not_contains "a sampled enabled hook is not listed unsampled" "$unsampled" "bash guard.sh"
assert_not_contains "a comment line is not an enabled hook" "$unsampled" "comment"
assert_not_contains "the Stop attachment is not double counted" "$out" "5000"
assert_not_contains "a quoted record in message text is not read" "$out" "99999"
for field in FIXTURE-STDOUT FIXTURE-STDERR FIXTURE-CONTENT; do
  assert_not_contains "hook output $field is never emitted" "$out" "$field"
done
assert_eq "no hook was executed" "absent" "$([[ -e "$TMP/hook-ran" ]] && echo present || echo absent)"

run --latency "$FIXTURE"
assert_eq "latency within the default Stop budget exits 0" 0 "$rc"
assert_contains "Stop p50/p95 from the slowest hook per summary" "$out" "unknown${TAB}Stop${TAB}3${TAB}500${TAB}860${TAB}2000"
assert_contains "PreToolUse is sampled with no budget" "$out" "unknown${TAB}PreToolUse${TAB}3${TAB}80${TAB}116${TAB}n/a${TAB}sampled"

run --latency --budget Stop=800 "$FIXTURE"
assert_eq "Stop p95 860 over an 800 budget exits 1" 1 "$rc"
assert_contains "the over-budget reason is named" "$out" "800${TAB}p95>budget"
run --latency --budget PreToolUse=10 "$FIXTURE"
assert_eq "a budget never flags a sampled event" 0 "$rc"

printf '{"type":"user"}\n' >"$TMP/empty.jsonl"
run "$TMP/empty.jsonl"
assert_eq "a transcript with no hook durations exits 2" 2 "$rc"
assert_contains "and says so" "$out" "no hook durations found"
run "$TMP/missing.jsonl"
assert_eq "a missing transcript exits 2" 2 "$rc"
run --enabled
assert_eq "--enabled without a file exits 2" 2 "$rc"
run
assert_eq "no transcript exits 2" 2 "$rc"

printf '\n%d case(s), %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
