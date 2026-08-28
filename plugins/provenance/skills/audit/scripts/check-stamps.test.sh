#!/usr/bin/env bash
# Self-contained tests for check-stamps.sh. Fixtures are built inline in a
# tmpdir. Per the shell-test-helpers convention, assertion helpers are local.
#
# The load-bearing cases here are the declined ones. The live corpus carries
# stamp dates in a long tail of prose forms — "verified <ISO>" dominates, but
# "as of April 2022", "As of August 23, 2024" and bare years all appear — and a
# parser that guessed at those would manufacture findings. So this suite pins
# both halves: what the parser claims, and what it declines with a reason.
#
# Every case pins --as-of, so the suite's verdicts do not drift with the clock.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-stamps.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (this suite reads the script's JSON product)" >&2
  exit 0
fi

export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# --- Fixtures --------------------------------------------------------------------
#
# AS_OF is 2026-08-28 and the default window is 180 days, so the expiry boundary
# falls exactly on 2026-03-01. The three dates around it are pinned deliberately.

AS_OF="2026-08-28"
DIR="$TEST_TMPDIR/corpus"
mkdir -p "$DIR"

{
  echo '# Stamps'                                       # 1
  echo ''                                               # 2
  echo 'Verified 2026-08-01 against the live page.'     # 3
  echo 'Checked 2026-03-01 against the settings doc.'   # 4
  echo 'Confirmed 2026-02-28 against the plugins page.' # 5
  echo 'Measured 2025-01-01 on the release runner.'     # 6
} >"$DIR/dated.md"

{
  echo '# Unparsed forms'                             # 1
  echo ''                                             # 2
  echo 'As of April 2022 this behavior was current.'  # 3
  echo 'Verified 08/12/2026 against the vendor page.' # 4
  echo 'Checked as of 2024 and not revisited since.'  # 5
} >"$DIR/prose.md"

{
  echo '# Not stamps'                                   # 1
  echo ''                                               # 2
  echo 'Changelog entry dated 2026-03-04 for the fix.'  # 3
  echo 'Confirmed from a primary source, no date here.' # 4
  echo 'Issue 1638 tracks the follow-up work.'          # 5
} >"$DIR/neither.md"

{
  echo '# Trigger present'                                    # 1
  echo ''                                                     # 2
  echo 'Verified 2025-06-01 against the upstream page.'       # 3
  echo ''                                                     # 4
  echo 'Recheck trigger: the next Claude Code minor release.' # 5
} >"$DIR/with-trigger.md"

{
  echo '# No trigger'                                   # 1
  echo ''                                               # 2
  echo 'Verified 2025-06-01 against the upstream page.' # 3
  echo 'Nothing here says when to look again.'          # 4
} >"$DIR/no-trigger.md"

run() { bash "$CHECK" --as-of "$AS_OF" "$@"; }

# --- Usage -----------------------------------------------------------------------

OUT="$(bash "$CHECK" --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "check-stamps.sh"

bash "$CHECK" --nope >/dev/null 2>&1
assert_exit "unknown argument exits 2" "$?" "2"

run --expiry-days >/dev/null 2>&1
assert_exit "a flag missing its value exits 2" "$?" "2"

run "$TEST_TMPDIR/absent.md" >/dev/null 2>&1
assert_exit "a missing file exits 2" "$?" "2"

run --paths-file "$TEST_TMPDIR/absent.txt" >/dev/null 2>&1
assert_exit "an unreadable --paths-file exits 2" "$?" "2"

# --- Expiry ----------------------------------------------------------------------

OUT="$(run "$DIR/dated.md" 2>/dev/null)"
assert_exit "a clean run exits 0" "$?" "0"

echo "$OUT" | jq -e . >/dev/null 2>&1
assert_exit "stdout is valid JSON" "$?" "0"

assert_eq "a fresh stamp is not a finding" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.line == 3)] | length')" "0"
assert_eq "a stamp exactly at the window is not a finding" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.line == 4)] | length')" "0"
assert_eq "a stamp one day past the window is a finding" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 5) | .days_over')" "1"
assert_eq "a long-expired stamp reports its days over" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 6) | .days_over')" "424"

assert_eq "a finding carries its stamp date" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 6) | .stamp_date')" "2025-01-01"
assert_eq "a finding carries the window it was judged against" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 6) | .window_days')" "180"
assert_eq "a finding carries its file" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 6) | .file')" "$DIR/dated.md"
assert_eq "expiry findings carry the expiry rule id" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule == "provenance/audit/rule-stamp-expired")] | length')" "2"

assert_eq "--expiry-days narrows the window" \
  "$(run --expiry-days 10 "$DIR/dated.md" 2>/dev/null | jq -r '.findings | length')" "4"
assert_eq "--expiry-days widens the window" \
  "$(run --expiry-days 1000 "$DIR/dated.md" 2>/dev/null | jq -r '.findings | length')" "0"

# --- Declined candidates ---------------------------------------------------------

OUT="$(run "$DIR/prose.md" 2>/dev/null)"
assert_eq "no unparsed form becomes a finding" \
  "$(echo "$OUT" | jq -r '.findings | length')" "0"
assert_eq "every unparsed candidate is counted" \
  "$(echo "$OUT" | jq -r '.counts.declined')" "3"
assert_contains "a month-name form declines with a reason" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "month name"
assert_contains "a slash form declines with a reason" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "slash"
assert_contains "a bare year declines with a reason" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "year"
assert_eq "a declined candidate names its file and line" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 3)] | length')" "1"

OUT="$(run "$DIR/neither.md" 2>/dev/null)"
assert_eq "a date with no stamp keyword is not a candidate" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "0"
assert_eq "a stamp keyword with no date is not a candidate" \
  "$(echo "$OUT" | jq -r '.counts.declined')" "0"

OUT="$(run "$DIR/dated.md" "$DIR/prose.md" 2>/dev/null)"
assert_eq "candidates equal parsed plus declined" \
  "$(echo "$OUT" | jq -r '.counts.candidates == (.counts.parsed + .counts.declined)')" "true"
assert_eq "parsed counts every ISO stamp" \
  "$(echo "$OUT" | jq -r '.counts.parsed')" "4"

# --- Trigger-less check ----------------------------------------------------------

OUT="$(run "$DIR/no-trigger.md" 2>/dev/null)"
assert_eq "the trigger-less check is off by default" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"
assert_eq "the run reports the trigger-less check as off" \
  "$(echo "$OUT" | jq -r '.trigger_less_check')" "false"

OUT="$(run --trigger-less "$DIR/no-trigger.md" 2>/dev/null)"
assert_eq "--trigger-less flags a stamp on a surface with no trigger" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule == "provenance/audit/rule-trigger-less-stamp")] | length')" "1"
assert_eq "the trigger-less finding names its line" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.rule | test("trigger-less")) | .line')" "3"

OUT="$(run --trigger-less "$DIR/with-trigger.md" 2>/dev/null)"
assert_eq "a stated recheck trigger clears the surface" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"

# --- Config cascade --------------------------------------------------------------

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
printf '%s\n' '{"stamp_expiry_days": 30}' >"$CLAUDE_PROJECT_DIR/.claude/provenance.json"
assert_eq "config sets the expiry window" \
  "$(run "$DIR/dated.md" 2>/dev/null | jq -r '.expiry_days')" "30"
assert_eq "--expiry-days beats config" \
  "$(run --expiry-days 1000 "$DIR/dated.md" 2>/dev/null | jq -r '.expiry_days')" "1000"

printf '%s\n' '{"trigger_less_stamp_check": true}' >"$CLAUDE_PROJECT_DIR/.claude/provenance.json"
assert_eq "config enables the trigger-less check" \
  "$(run "$DIR/no-trigger.md" 2>/dev/null | jq -r '.trigger_less_check')" "true"
rm -f "$CLAUDE_PROJECT_DIR/.claude/provenance.json"

OUT="$(run --show-config 2>&1)"
assert_exit "--show-config exits 0" "$?" "0"
assert_contains "--show-config prints the effective window" "$OUT" "stamp_expiry_days"
assert_contains "--show-config prints the trigger-less setting" "$OUT" "trigger_less_stamp_check"

# --- Inputs ----------------------------------------------------------------------

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$DIR/dated.md" >"$PATHS"
assert_eq "--paths-file supplies the corpus" \
  "$(run --paths-file "$PATHS" 2>/dev/null | jq -r '.counts.files')" "1"

assert_eq "counts.files matches the inputs" \
  "$(run "$DIR/dated.md" "$DIR/prose.md" 2>/dev/null | jq -r '.counts.files')" "2"

# --- Determinism and escaping ----------------------------------------------------

RUN_A="$(run "$DIR/dated.md" 2>/dev/null)"
RUN_B="$(run "$DIR/dated.md" 2>/dev/null)"
assert_eq "repeat runs produce identical output" "$RUN_A" "$RUN_B"

{
  echo '# Escaping'
  echo 'Verified 2025-01-01 against "the quoted page" and a back\slash.'
} >"$DIR/esc.md"
ESC="$(run "$DIR/esc.md" 2>/dev/null)"
echo "$ESC" | jq -e . >/dev/null 2>&1
assert_exit "quotes and backslashes stay valid JSON" "$?" "0"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
