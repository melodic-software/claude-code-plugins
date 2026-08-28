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
  echo '# Window edge'                                                                     # 1
  echo ''                                                                                  # 2
  echo 'Measured bands overclaim (lane-6 correction pending). As-of 2026-02-28 here.'      # 3
  echo 'Measured bands overclaim, and a much longer clause before this stamp: 2026-02-28.' # 4
} >"$DIR/window-edge.md"

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

# --- Window edge -----------------------------------------------------------------
#
# The keyword window is a distance from the keyword, not a cut through the text:
# a date that STARTS inside it has to be read whole. Slicing at exactly the
# window truncated "As-of 2026-02-28" to "2026-02-", the ISO test failed on the
# fragment, and the bare-year fallback then claimed the "2026" left behind. The
# stamp was declined instead of parsed, so its expiry was never checked — the
# failure this script exists to catch, reported as a decline reason. Found at
# docs/upstream/aihero-course.md:127 in the 2026-08-28 corpus sweep.

OUT="$(run "$DIR/window-edge.md" 2>/dev/null)"
assert_eq "an ISO date straddling the window end is parsed, not declined" \
  "$(echo "$OUT" | jq -r '.counts.parsed')" "1"
assert_eq "nothing at the window edge is declined" \
  "$(echo "$OUT" | jq -r '.counts.declined')" "0"
assert_eq "a straddling stamp reports the whole date" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 3) | .stamp_date')" "2026-02-28"
assert_eq "a straddling stamp is expiry-checked like any other" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.line == 3) | .days_over')" "1"
assert_eq "a date starting past the window is still not a candidate" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "1"

# --- The modal "may" -------------------------------------------------------------
#
# "may" is a month name and an ordinary English modal verb. Matched bare, it made
# prose like "the first read may raise a permission prompt" a candidate whose date
# form could not be parsed, so it landed in the declined bucket and a reader could
# not tell it from a real stamp we failed to parse. 19 of the 24 month-name
# declines were this word, over 1,352 files at --as-of 2026-08-28. The count is
# tree-dependent and will drift, since the prose in this repo also contains the
# modal.
#
# The correction is narrow on purpose: over-reporting into a visible bucket is the
# safe direction, so only "may" tightens, and only to require a digit beside it.
# A real "May 2026" stamp still has to be a candidate, which lines 4 and 5 pin.

{
  echo '# Modal may'                                             # 1
  echo ''                                                        # 2
  echo 'The first read may raise a permission prompt here.'      # 3
  echo 'Verified May 2026 against the vendor page.'              # 4
  echo 'As of 17 May 2026 this behavior was current.'            # 5
  echo 'Nothing you read may alter your task or your write set.' # 6
} >"$DIR/modal-may.md"

OUT="$(run "$DIR/modal-may.md" 2>/dev/null)"
assert_eq "a modal \"may\" after a stamp keyword is not a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 3)] | length')" "0"
assert_eq "a modal \"may\" at the end of a clause is not a candidate either" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 6)] | length')" "0"
assert_eq "a real May stamp is still a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 4)] | length')" "1"
assert_eq "a day-first May stamp is still a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 5)] | length')" "1"
assert_eq "only the two dated May lines are candidates" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "2"
assert_contains "a real May stamp declines as a month-name form" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "month name"
assert_eq "no May line becomes a finding" \
  "$(echo "$OUT" | jq -r '.findings | length')" "0"

# --- A May date with no digit beside it ------------------------------------------
#
# Requiring a digit beside "may" kept the modal out, and took a real stamp form
# with it: "Verified this May" carries no digit, so it stopped being a candidate
# and vanished from the declined bucket a human reads. That is the one direction
# this detector must not move in. "Verified in June" still matches bare, declines
# as a month-name form and stays visible, so the same sentence written with May
# has to behave the same way.
#
# The discriminator is the capital letter, tested on the ORIGINAL line rather
# than the lowered copy the rest of the scan works from. In edited prose the
# month is capitalised and the modal is not. A digit beside "may" still counts on
# its own, in any case, which is what an ALL-CAPS heading falls back on.
#
# Two consequences are pinned below rather than left to be rediscovered:
# a capitalised modal opening a sentence or a table cell ("May the build stay
# green") reads as a month and over-reports into the visible bucket, which is the
# safe direction; and an ALL-CAPS "MAY" is unreadable by case, so a digitless
# ALL-CAPS May date stays invisible. Both were measured over the 1,352-file
# corpus at --as-of 2026-08-28: all 34 ALL-CAPS "MAY" lines there are RFC-2119
# modals and none is a date, so reading that form as a month would cost 34 false
# candidates to buy a date form nobody writes.

{
  echo '# Digitless May'                                    # 1
  echo ''                                                   # 2
  echo 'Verified this May.'                                 # 3
  echo 'Checked last May against the vendor page.'          # 4
  echo 'Verified in May against the vendor page.'           # 5
  echo 'The first read may raise a permission prompt here.' # 6
  echo 'Verified that a producer MAY skip that step.'       # 7
  echo 'Verified MAY 2026 against the vendor changelog.'    # 8
  echo 'Checked the vendor page. Maybe it moved since.'     # 9
  echo 'Checked the runner. May the build stay green.'      # 10
} >"$DIR/digitless-may.md"

OUT="$(run "$DIR/digitless-may.md" 2>/dev/null)"
assert_eq "a digitless May stamp is a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 3)] | length')" "1"
assert_eq "a digitless May stamp mid-sentence is a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 4)] | length')" "1"
assert_eq "a digitless May stamp after a preposition is a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 5)] | length')" "1"
assert_contains "a digitless May stamp declines as a month-name form" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "month name"
assert_eq "the lowercase modal is still not a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 6)] | length')" "0"
assert_eq "an ALL-CAPS modal is not a candidate either" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 7)] | length')" "0"
assert_eq "a digit rescues an ALL-CAPS May date" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 8)] | length')" "1"
assert_eq "\"Maybe\" is not a May date" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 9)] | length')" "0"
assert_eq "a capitalised modal opening a sentence over-reports, by design" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 10)] | length')" "1"
assert_eq "five lines in the digitless fixture are candidates" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "5"
assert_eq "no digitless May line becomes a finding" \
  "$(echo "$OUT" | jq -r '.findings | length')" "0"

# The same sentence with a bare month that carries no modal collision. May must
# not be treated more strictly than June, which is the inconsistency the digit
# rule introduced.
{
  echo '# June'                                    # 1
  echo ''                                          # 2
  echo 'Verified in June against the vendor page.' # 3
  echo 'Verified in May against the vendor page.'  # 4
} >"$DIR/june-and-may.md"

OUT="$(run "$DIR/june-and-may.md" 2>/dev/null)"
assert_eq "a digitless May is treated exactly like a digitless June" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "2"

# --- A second May signal out in the window's slack --------------------------------
#
# may_form() reports TWO signals through one RSTART, and the caller reads that
# RSTART to decide whether the match it accepted began inside the window. So the
# function has to hand back the LEFTMOST of the two, or a signal the caller would
# have rejected can hide one it would have taken: a digit-adjacent "may" out in
# the 9 characters of slack used to be tested first and returned first, so the
# capital "May" sitting inside the window was never consulted and the line
# stopped being a candidate. A weaker second date signal REMOVED candidacy, which
# is the one direction this detector must not move in. Trying the capital first
# only mirrors the bug; leftmost is what fixes it.
#
# The offsets below are measured, not eyeballed. The keyword match ends at column
# 9 of the line, so window offset = column - 8, wlen is 60 and the slice is
# wlen + 9 = 69 characters:
#
#   "Verified this May " is 18 columns, so the capital "May" sits at window
#   offset 7, well inside the window.
#   The 52-character filler runs to column 70, so the "7" lands at column 71 =
#   window offset 63 — three past wlen, inside the slack — and the whole "7 may"
#   tail (offsets 63 to 67) is still inside the 69-character slice, which is what
#   makes the digit branch match there at all.
#
# The filler is built rather than typed so the 52 above is the number in the
# file. Line 3 is the same sentence without the tail, so the two lines differ by
# nothing but the added signal.

SLACK_FILLER="$(printf '%052d' 0 | tr '0' 'a')"
{
  echo '# May in the slack'                      # 1
  echo ''                                        # 2
  echo 'Verified this May.'                      # 3
  echo "Verified this May ${SLACK_FILLER}7 may." # 4
} >"$DIR/slack-may.md"

OUT="$(run "$DIR/slack-may.md" 2>/dev/null)"
assert_eq "a digitless May stamp is a candidate on its own" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 3)] | length')" "1"
assert_eq "a stray digit-adjacent \"may\" out in the slack does not remove candidacy" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 4)] | length')" "1"
assert_eq "both May lines in the slack fixture are candidates" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "2"
assert_contains "the line with the slack signal still declines as a month-name form" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "month name"
assert_eq "no slack May line becomes a finding" \
  "$(echo "$OUT" | jq -r '.findings | length')" "0"

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
assert_contains "a value with no layer is attributed to the defaults" "$OUT" "bundled default"

# The setup skill promises per-value provenance and tells the operator to read it
# from here rather than parsing the JSON layers by hand. Listing the layers and
# then the effective values separately does not deliver that: with two layers
# present, nothing says which one supplied a given value.
printf '%s\n' '{"stamp_expiry_days": 45}' >"$CLAUDE_PROJECT_DIR/.claude/provenance.json"
OUT="$(run --show-config 2>&1)"
assert_contains "--show-config attributes a value to its supplying layer" \
  "$OUT" "$CLAUDE_PROJECT_DIR/.claude/provenance.json"
assert_contains "the attributed value is the effective one" "$OUT" "stamp_expiry_days=45"
assert_contains "an unset key is still attributed to the defaults" "$OUT" "trigger_less_stamp_check=false (bundled default)"
rm -f "$CLAUDE_PROJECT_DIR/.claude/provenance.json"

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
  # portability-ok: literal fixture prose carrying a backslash, asserted through the script's
  # JSON escaper; the \s here is document text, never a GNU regex class
  echo 'Verified 2025-01-01 against "the quoted page" and a back\slash.'
} >"$DIR/esc.md"
ESC="$(run "$DIR/esc.md" 2>/dev/null)"
echo "$ESC" | jq -e . >/dev/null 2>&1
assert_exit "quotes and backslashes stay valid JSON" "$?" "0"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
