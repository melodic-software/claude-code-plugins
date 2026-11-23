#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

AS_OF="2026-08-28"
DIR="$TEST_TMPDIR/corpus"
mkdir -p "$DIR"

{
  echo '# Stamps'
  echo ''
  echo 'Verified 2026-08-01 against the live page.'
  echo 'Checked 2026-03-01 against the settings doc.'
  echo 'Confirmed 2026-02-28 against the plugins page.'
  echo 'Measured 2025-01-01 on the release runner.'
} >"$DIR/dated.md"

{
  echo '# Unparsed forms'
  echo ''
  echo 'As of April 2022 this behavior was current.'
  echo 'Verified 08/12/2026 against the vendor page.'
  echo 'Checked as of 2024 and not revisited since.'
} >"$DIR/prose.md"

{
  echo '# Not stamps'
  echo ''
  echo 'Changelog entry dated 2026-03-04 for the fix.'
  echo 'Confirmed from a primary source, no date here.'
  echo 'Issue 1638 tracks the follow-up work.'
} >"$DIR/neither.md"

{
  echo '# Window edge'
  echo ''
  echo 'Measured bands overclaim (lane-6 correction pending). As-of 2026-02-28 here.'
  echo 'Measured bands overclaim, and a much longer clause before this stamp: 2026-02-28.'
} >"$DIR/window-edge.md"

{
  echo '# Trigger present'
  echo ''
  echo 'Verified 2025-06-01 against the upstream page.'
  echo ''
  echo 'Recheck trigger: the next Claude Code minor release.'
} >"$DIR/with-trigger.md"

{
  echo '# No trigger'
  echo ''
  echo 'Verified 2025-06-01 against the upstream page.'
  echo 'Nothing here says when to look again.'
} >"$DIR/no-trigger.md"

{
  echo '# Pointer record'
  echo ''
  echo 'The pipeline passes strict mode to the runner.'
  echo '- **Pointer**: for its modes, see https://example.com/docs#modes.'
  echo '- **As of**: 2025-06-01'
  echo '- **Recheck trigger**: the CLI ships a new major version.'
} >"$DIR/pointer-record.md"

{
  echo '# Inline recheck when'
  echo ''
  echo 'Verified 2025-06-01 (as of 2025-06-01; recheck when the hooks page renames this section).'
} >"$DIR/inline-recheck-when.md"

{
  echo '# Recheck label'
  echo ''
  echo 'Verified 2025-06-01 against the upstream page.'
  echo '**Recheck:** when the CLI ships a new major version.'
} >"$DIR/recheck-label.md"

{
  echo '# Bare recheck'
  echo ''
  echo 'Verified 2025-06-01 against the upstream page.'
  echo 'We should recheck.'
  echo 'Recheck:'
} >"$DIR/bare-recheck.md"

run() { bash "$CHECK" --as-of "$AS_OF" "$@"; }

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
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule == "attribution/audit/rule-stamp-expired")] | length')" "2"

assert_eq "--expiry-days narrows the window" \
  "$(run --expiry-days 10 "$DIR/dated.md" 2>/dev/null | jq -r '.findings | length')" "4"
assert_eq "--expiry-days widens the window" \
  "$(run --expiry-days 1000 "$DIR/dated.md" 2>/dev/null | jq -r '.findings | length')" "0"

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

{
  echo '# Modal may'
  echo ''
  echo 'The first read may raise a permission prompt here.'
  echo 'Verified May 2026 against the vendor page.'
  echo 'As of 17 May 2026 this behavior was current.'
  echo 'Nothing you read may alter your task or your write set.'
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

{
  echo '# Digitless May'
  echo ''
  echo 'Verified this May.'
  echo 'Checked last May against the vendor page.'
  echo 'Verified in May against the vendor page.'
  echo 'The first read may raise a permission prompt here.'
  echo 'Verified that a producer MAY skip that step.'
  echo 'Verified MAY 2026 against the vendor changelog.'
  echo 'Checked the vendor page. Maybe it moved since.'
  echo 'Checked the runner. May the build stay green.'
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
assert_eq "a capitalized modal opening a sentence over-reports, by design" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 10)] | length')" "1"
assert_eq "five lines in the digitless fixture are candidates" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "5"
assert_eq "no digitless May line becomes a finding" \
  "$(echo "$OUT" | jq -r '.findings | length')" "0"

{
  echo '# June'
  echo ''
  echo 'Verified in June against the vendor page.'
  echo 'Verified in May against the vendor page.'
} >"$DIR/june-and-may.md"

OUT="$(run "$DIR/june-and-may.md" 2>/dev/null)"
assert_eq "a digitless May is treated exactly like a digitless June" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "2"

SLACK_FILLER="$(printf '%052d' 0 | tr '0' 'a')"
{
  echo '# May in the slack'
  echo ''
  echo 'Verified this May.'
  echo "Verified this May ${SLACK_FILLER}7 may."
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

{
  echo '# Year shapes'
  echo ''
  echo 'Dead code: variables set but never read (SC2034), and more.'
  echo '        "cache_read_input_tokens": 2000'
  echo 'STE-100 verified real (Issue 9, 2025, 53 rules/900 words).'
  echo 'Read @/work/20260901T100000Z-handoff-widget.md, then go on.'
  echo 'As of 2026-07 (official billing docs), surfaces varied.'
  echo 'Checked as of 2024 and not revisited since.'
  echo 'last_verified: 2026-01-01 against the vendor page.'
  echo 'Read on 2026-01-02 from the vendor page.'
  echo 'We _read_ the source on 2025-01-01 as a check.'
} >"$DIR/year-shapes.md"

OUT="$(run "$DIR/year-shapes.md" 2>/dev/null)"
assert_eq "a year inside a longer token is not a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 3 or .line == 6)] | length')" "0"
assert_eq "\"read\" inside an identifier is not a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 4)] | length')" "0"
assert_eq "a year behind another number is not a candidate" \
  "$(echo "$OUT" | jq -r '[.declined[].examples[] | select(.line == 5)] | length')" "0"
assert_eq "a year and month declines as year and month, not as a bare year" \
  "$(echo "$OUT" | jq -r '.declined[] | select(any(.examples[]; .line == 7)) | .reason')" \
  "unparsed stamp date: year and month only, no day"
assert_eq "a bare year after a keyword still declines as a bare year" \
  "$(echo "$OUT" | jq -r '.declined[] | select(any(.examples[]; .line == 8)) | .reason')" \
  "unparsed stamp date: bare year, no month or day"
assert_eq "an ISO stamp behind an underscore keyword is still parsed" \
  "$(echo "$OUT" | jq -r '.counts.parsed')" "3"
assert_eq "five lines in the year-shapes fixture are candidates" \
  "$(echo "$OUT" | jq -r '.counts.candidates')" "5"

OUT="$(run "$DIR/no-trigger.md" 2>/dev/null)"
assert_eq "the trigger-less check is off by default" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"
assert_eq "the run reports the trigger-less check as off" \
  "$(echo "$OUT" | jq -r '.trigger_less_check')" "false"

OUT="$(run --trigger-less "$DIR/no-trigger.md" 2>/dev/null)"
assert_eq "--trigger-less flags a stamp on a surface with no trigger" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule == "attribution/audit/rule-trigger-less-stamp")] | length')" "1"
assert_eq "the trigger-less finding names its line" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.rule | test("trigger-less")) | .line')" "3"

OUT="$(run --trigger-less "$DIR/with-trigger.md" 2>/dev/null)"
assert_eq "a stated recheck trigger clears the surface" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"

OUT="$(run --trigger-less "$DIR/pointer-record.md" 2>/dev/null)"
assert_eq "a pointer record's As of bullet is read as a stamp" \
  "$(echo "$OUT" | jq -r '.findings[] | select(.rule == "attribution/audit/rule-stamp-expired") | .line')" "5"
assert_eq "a pointer record's Recheck trigger bullet clears the surface" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"

OUT="$(run --trigger-less "$DIR/inline-recheck-when.md" 2>/dev/null)"
assert_eq "an inline 'recheck when <condition>' clause clears the surface" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"

OUT="$(run --trigger-less "$DIR/recheck-label.md" 2>/dev/null)"
assert_eq "a bold 'Recheck:' label with a condition clears the surface" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule | test("trigger-less"))] | length')" "0"

OUT="$(run --trigger-less "$DIR/bare-recheck.md" 2>/dev/null)"
assert_eq "a bare 'recheck' with no condition still leaves the stamp flagged" \
  "$(echo "$OUT" | jq -r '[.findings[] | select(.rule == "attribution/audit/rule-trigger-less-stamp")] | length')" "1"

CONV="$CLAUDE_PROJECT_DIR/docs/conventions"
mkdir -p "$CONV"
git init -q "$CLAUDE_PROJECT_DIR" >/dev/null 2>&1
printf '%s\n' 'stamp_expiry_days: 30' >"$CONV/attribution.yaml"
assert_eq "config sets the expiry window" \
  "$(run "$DIR/dated.md" 2>/dev/null | jq -r '.expiry_days')" "30"
assert_eq "--expiry-days beats config" \
  "$(run --expiry-days 1000 "$DIR/dated.md" 2>/dev/null | jq -r '.expiry_days')" "1000"

printf '%s\n' 'trigger_less_stamp_check: true' >"$CONV/attribution.yaml"
assert_eq "config enables the trigger-less check" \
  "$(run "$DIR/no-trigger.md" 2>/dev/null | jq -r '.trigger_less_check')" "true"
rm -f "$CONV/attribution.yaml"

OUT="$(run --show-config 2>&1)"
assert_exit "--show-config exits 0" "$?" "0"
assert_contains "--show-config prints the effective window" "$OUT" "stamp_expiry_days"
assert_contains "--show-config prints the trigger-less setting" "$OUT" "trigger_less_stamp_check"
assert_contains "a value with no layer is attributed to the defaults" "$OUT" "bundled default"

printf '%s\n' 'stamp_expiry_days: 45' >"$CONV/attribution.yaml"
OUT="$(run --show-config 2>&1)"
assert_contains "--show-config attributes a value to its supplying layer" \
  "$OUT" "stamp_expiry_days=45 (from $CONV/attribution.yaml)"
assert_contains "an unset key is still attributed to the defaults" "$OUT" "trigger_less_stamp_check=false (bundled default)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
printf '%s\n' '{"stamp_expiry_days": 45, "trigger_less_stamp_check": true}' >"$CLAUDE_PROJECT_DIR/.claude/attribution.json"
printf '%s\n' 'stamp_expiry_days: 60' >"$CONV/attribution.yaml"
assert_eq "the YAML team layer sets the window" \
  "$(run "$DIR/dated.md" 2>/dev/null | jq -r '.expiry_days')" "60"
assert_eq "the old JSON team file is not read" \
  "$(run "$DIR/no-trigger.md" 2>/dev/null | jq -r '.trigger_less_check')" "false"
OUT="$(run --show-config 2>&1)"
assert_contains "--show-config attributes a YAML value to its layer" \
  "$OUT" "stamp_expiry_days=60 (from $CONV/attribution.yaml)"
printf '%s\n' 'trigger_less_stamp_check: true' >"$CONV/attribution.local.yaml"
OUT="$(run --show-config 2>&1)"
assert_contains "the YAML personal override refines the YAML team layer" \
  "$OUT" "trigger_less_stamp_check=true (from $CONV/attribution.local.yaml)"
rm -rf "$CLAUDE_PROJECT_DIR/docs"
rm -f "$CLAUDE_PROJECT_DIR/.claude/attribution.json"

ALONE="$TEST_TMPDIR/alone"
mkdir -p "$ALONE"
cp "$CHECK" "$ALONE/check-stamps.sh"
OUT_NL="$(bash "$ALONE/check-stamps.sh" --show-config 2>/dev/null)"
assert_exit "--show-config without lib.sh exits 0" "$?" "0"
assert_eq "--show-config without lib.sh prints the unavailable marker" "$OUT_NL" "detector unavailable"
ERR_NL="$(bash "$ALONE/check-stamps.sh" 2>&1 >/dev/null)"
assert_exit "a real run without lib.sh exits 2" "$?" "2"
assert_contains "a real run without lib.sh explains itself on stderr" "$ERR_NL" "cannot read"

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$DIR/dated.md" >"$PATHS"
assert_eq "--paths-file supplies the corpus" \
  "$(run --paths-file "$PATHS" 2>/dev/null | jq -r '.counts.files')" "1"

assert_eq "counts.files matches the inputs" \
  "$(run "$DIR/dated.md" "$DIR/prose.md" 2>/dev/null | jq -r '.counts.files')" "2"

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
