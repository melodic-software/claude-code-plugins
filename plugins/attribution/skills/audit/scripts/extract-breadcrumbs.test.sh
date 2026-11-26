#!/usr/bin/env bash
# test-scope: docs/conventions/attribution.yaml
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT="$SCRIPT_DIR/extract-breadcrumbs.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (this suite reads the script's JSON product)" >&2
  exit 0
fi

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

DIR_A="$TEST_TMPDIR/topic"
DIR_B="$TEST_TMPDIR/other"
mkdir -p "$DIR_A" "$DIR_B"

{
  echo '# Notes'
  echo ''
  echo 'See [the skills doc](https://code.claude.com/docs/skills.md).'
  echo ''
  echo 'A bare link: https://example.com/page and prose after.'
  echo ''
  echo '> A quoted excerpt from somewhere upstream.'
  echo ''
  echo 'Verified 2026-08-12 against the live page.'
  echo ''
  echo '```bash'
  echo 'curl https://api.example.com/v1/thing'
  echo '```'
  echo ''
  echo 'An angle link: <https://angle.example.com/doc>.'
} >"$DIR_A/notes.md"

{
  echo '<!-- Vendored from https://github.com/acme/repo on 2026-07-01. -->'
  echo '# Copied page'
  echo ''
  echo 'Body text with no breadcrumb of its own.'
} >"$DIR_A/copied.md"

{
  echo '# Empty of breadcrumbs'
  echo ''
  echo 'Nothing to see here.'
} >"$DIR_A/bare.md"

{
  echo '<!-- provenance: https://paired.example.com/src -->'
  echo 'Fenced body line one.'
  echo 'Fenced body line two.'
  echo '<!-- /provenance -->'
  echo ''
  echo '<!--'
  echo 'Multi-line comment citing https://multi.example.com'
  echo 'as of 2026-01-05.'
  echo '-->'
} >"$DIR_A/fenced.md"

{
  echo '# Sibling'
  echo ''
  echo 'As of April 2022 this was accurate.'
  echo 'Changelog entry dated 2026-03-04.'
  echo 'Quote with a "straight quoted" span.'
} >"$DIR_B/sibling.md"

run() { bash "$EXTRACT" "$@"; }

OUT="$(run --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "extract-breadcrumbs.sh"

run --nope >/dev/null 2>&1
assert_exit "unknown argument exits 2" "$?" "2"

run >/dev/null 2>&1
assert_exit "no selector exits 2" "$?" "2"

run --dir "$DIR_A" --files "$DIR_B/sibling.md" >/dev/null 2>&1
assert_exit "both selectors together exit 2" "$?" "2"

run --dir "$TEST_TMPDIR/absent" >/dev/null 2>&1
assert_exit "a missing directory exits 2" "$?" "2"

run --files "$TEST_TMPDIR/absent.md" >/dev/null 2>&1
assert_exit "a missing file exits 2" "$?" "2"

OUT="$(run --dir "$DIR_A" 2>/dev/null)"
assert_exit "a clean run exits 0" "$?" "0"

echo "$OUT" | jq -e . >/dev/null 2>&1
assert_exit "stdout is valid JSON" "$?" "0"

assert_eq "--dir yields exactly one directory group" \
  "$(echo "$OUT" | jq -r '.directories | length')" "1"
assert_eq "the group lists every markdown sibling" \
  "$(echo "$OUT" | jq -r '.directories[0].files | length')" "4"
assert_contains "a file with no breadcrumbs is still listed" \
  "$(echo "$OUT" | jq -r '.directories[0].files[].file')" "bare.md"
assert_eq "the breadcrumb-free file carries empty arrays" \
  "$(echo "$OUT" | jq -r '.directories[0].files[] | select(.file | endswith("bare.md")) | (.urls | length) + (.fences | length) + (.stamp_lines | length)')" "0"

NOTES='.directories[0].files[] | select(.file | endswith("notes.md"))'

assert_eq "a markdown link URL is extracted" \
  "$(echo "$OUT" | jq -r "$NOTES | .urls[] | select(.line == 3) | .url")" \
  "https://code.claude.com/docs/skills.md"
assert_eq "a bare URL is extracted with its line" \
  "$(echo "$OUT" | jq -r "$NOTES | .urls[] | select(.line == 5) | .url")" \
  "https://example.com/page"
assert_eq "an angle-bracketed URL loses its delimiters" \
  "$(echo "$OUT" | jq -r "$NOTES | .urls[] | select(.line == 15) | .url")" \
  "https://angle.example.com/doc"
assert_eq "trailing sentence punctuation is not part of the URL" \
  "$(echo "$OUT" | jq -r "$NOTES | [.urls[] | select(.url | endswith(\".\"))] | length")" "0"

assert_eq "a URL inside a code fence is flagged as such" \
  "$(echo "$OUT" | jq -r "$NOTES | .urls[] | select(.line == 12) | .in_code_fence")" "true"
assert_eq "a URL in prose is not flagged as fenced" \
  "$(echo "$OUT" | jq -r "$NOTES | .urls[] | select(.line == 5) | .in_code_fence")" "false"

assert_eq "a stamp line is inventoried with its line number" \
  "$(echo "$OUT" | jq -r "$NOTES | .stamp_lines[] | select(.line == 9) | .line")" "9"
assert_contains "the stamp line carries its text" \
  "$(echo "$OUT" | jq -r "$NOTES | .stamp_lines[].text")" "Verified 2026-08-12"

assert_eq "a blockquote line is inventoried" \
  "$(echo "$OUT" | jq -r "$NOTES | .quote_lines[] | select(.line == 7) | .kind")" "blockquote"

SIB_OUT="$(run --files "$DIR_B/sibling.md" 2>/dev/null)"
SIB='.directories[0].files[0]'
assert_eq "a non-ISO stamp form is still inventoried" \
  "$(echo "$SIB_OUT" | jq -r "$SIB | [.stamp_lines[] | select(.line == 3)] | length")" "1"
assert_eq "a bare date with no stamp keyword is not a stamp line" \
  "$(echo "$SIB_OUT" | jq -r "$SIB | [.stamp_lines[] | select(.line == 4)] | length")" "0"

STRADDLE_DIR="$TEST_TMPDIR/straddle"
mkdir -p "$STRADDLE_DIR"
{
  printf '# Straddle\n\n'
  # shellcheck disable=SC2016 # fixture text lifted verbatim from the corpus
  printf '  synced set (verified against the `chore: sync standards components` history on 2026-07-30), so\n\n'
  # shellcheck disable=SC2016 # same literal fixture text, date shifted past the window.
  printf '  synced set (verified against the `chore: sync standards componentsxxxx` history on 2026-07-30), so\n'
} >"$STRADDLE_DIR/straddle.md"

STRADDLE_OUT="$(run --files "$STRADDLE_DIR/straddle.md" 2>/dev/null)"
assert_eq "a stamp whose date straddles the window end is inventoried" \
  "$(echo "$STRADDLE_OUT" | jq -r '.directories[0].files[0] | [.stamp_lines[] | select(.line == 3)] | length')" "1"
assert_eq "a date starting past the window is still not a stamp" \
  "$(echo "$STRADDLE_OUT" | jq -r '.directories[0].files[0] | [.stamp_lines[] | select(.line == 5)] | length')" "0"

MAY_DIR="$TEST_TMPDIR/may"
mkdir -p "$MAY_DIR"
{
  echo '# Modal may'
  echo ''
  echo 'The first read may raise a permission prompt here.'
  echo 'Verified May 2026 against the vendor page.'
  echo 'As of 17 May 2026 this behavior was current.'
  echo 'Nothing you read may alter your task or your write set.'
} >"$MAY_DIR/modal-may.md"

MAY_OUT="$(run --files "$MAY_DIR/modal-may.md" 2>/dev/null)"
MAY_FILE='.directories[0].files[0]'
assert_eq "a modal \"may\" after a stamp keyword is not a stamp line" \
  "$(echo "$MAY_OUT" | jq -r "$MAY_FILE | [.stamp_lines[] | select(.line == 3)] | length")" "0"
assert_eq "a modal \"may\" at the end of a clause is not a stamp line either" \
  "$(echo "$MAY_OUT" | jq -r "$MAY_FILE | [.stamp_lines[] | select(.line == 6)] | length")" "0"
assert_eq "a real May stamp is still inventoried" \
  "$(echo "$MAY_OUT" | jq -r "$MAY_FILE | [.stamp_lines[] | select(.line == 4)] | length")" "1"
assert_eq "a day-first May stamp is still inventoried" \
  "$(echo "$MAY_OUT" | jq -r "$MAY_FILE | [.stamp_lines[] | select(.line == 5)] | length")" "1"

MAY_CANDIDATES="$(bash "$SCRIPT_DIR/check-stamps.sh" --as-of 2026-08-28 \
  "$MAY_DIR/modal-may.md" 2>/dev/null | jq -r '.counts.candidates')"
assert_eq "both scripts agree on which May lines are candidates" \
  "$(echo "$MAY_OUT" | jq -r "$MAY_FILE | .stamp_lines | length")" "$MAY_CANDIDATES"
assert_eq "and they agree on two" "$MAY_CANDIDATES" "2"

DIGITLESS_DIR="$TEST_TMPDIR/digitless-may"
mkdir -p "$DIGITLESS_DIR"
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
} >"$DIGITLESS_DIR/digitless-may.md"

DIGITLESS_OUT="$(run --files "$DIGITLESS_DIR/digitless-may.md" 2>/dev/null)"
DIGITLESS_FILE='.directories[0].files[0]'
assert_eq "a digitless May stamp is inventoried" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 3)] | length")" "1"
assert_eq "a digitless May stamp mid-sentence is inventoried" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 4)] | length")" "1"
assert_eq "a digitless May stamp after a preposition is inventoried" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 5)] | length")" "1"
assert_eq "the lowercase modal is still not a stamp line" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 6)] | length")" "0"
assert_eq "an ALL-CAPS modal is not a stamp line either" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 7)] | length")" "0"
assert_eq "a digit rescues an ALL-CAPS May date" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 8)] | length")" "1"
assert_eq "\"Maybe\" is not a May date" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 9)] | length")" "0"
assert_eq "a capitalized modal opening a sentence over-reports, by design" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | [.stamp_lines[] | select(.line == 10)] | length")" "1"

DIGITLESS_CANDIDATES="$(bash "$SCRIPT_DIR/check-stamps.sh" --as-of 2026-08-28 \
  "$DIGITLESS_DIR/digitless-may.md" 2>/dev/null | jq -r '.counts.candidates')"
assert_eq "both scripts agree on which digitless May lines are candidates" \
  "$(echo "$DIGITLESS_OUT" | jq -r "$DIGITLESS_FILE | .stamp_lines | length")" "$DIGITLESS_CANDIDATES"
assert_eq "and they agree on five" "$DIGITLESS_CANDIDATES" "5"

SLACK_DIR="$TEST_TMPDIR/slack-may"
mkdir -p "$SLACK_DIR"
SLACK_FILLER="$(printf '%052d' 0 | tr '0' 'a')"
{
  echo '# May in the slack'
  echo ''
  echo 'Verified this May.'
  echo "Verified this May ${SLACK_FILLER}7 may."
} >"$SLACK_DIR/slack-may.md"

SLACK_OUT="$(run --files "$SLACK_DIR/slack-may.md" 2>/dev/null)"
SLACK_FILE='.directories[0].files[0]'
assert_eq "a digitless May stamp is inventoried on its own" \
  "$(echo "$SLACK_OUT" | jq -r "$SLACK_FILE | [.stamp_lines[] | select(.line == 3)] | length")" "1"
assert_eq "a stray digit-adjacent \"may\" out in the slack does not remove the stamp line" \
  "$(echo "$SLACK_OUT" | jq -r "$SLACK_FILE | [.stamp_lines[] | select(.line == 4)] | length")" "1"

SLACK_CANDIDATES="$(bash "$SCRIPT_DIR/check-stamps.sh" --as-of 2026-08-28 \
  "$SLACK_DIR/slack-may.md" 2>/dev/null | jq -r '.counts.candidates')"
assert_eq "both scripts agree on the May line carrying a slack signal" \
  "$(echo "$SLACK_OUT" | jq -r "$SLACK_FILE | .stamp_lines | length")" "$SLACK_CANDIDATES"
assert_eq "and they agree on two, not on zero" "$SLACK_CANDIDATES" "2"

YEAR_DIR="$TEST_TMPDIR/year-shapes"
mkdir -p "$YEAR_DIR"
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
} >"$YEAR_DIR/year-shapes.md"

YEAR_OUT="$(run --files "$YEAR_DIR/year-shapes.md" 2>/dev/null)"
YEAR_FILE='.directories[0].files[0]'
assert_eq "only the five dated lines are stamp lines" \
  "$(echo "$YEAR_OUT" | jq -r "$YEAR_FILE | [.stamp_lines[].line] | join(\",\")")" "7,8,9,10,11"

YEAR_CANDIDATES="$(bash "$SCRIPT_DIR/check-stamps.sh" --as-of 2026-08-28 \
  "$YEAR_DIR/year-shapes.md" 2>/dev/null | jq -r '.counts.candidates')"
assert_eq "both scripts agree on the year-shapes candidates" \
  "$(echo "$YEAR_OUT" | jq -r "$YEAR_FILE | .stamp_lines | length")" "$YEAR_CANDIDATES"
assert_eq "and they agree on five" "$YEAR_CANDIDATES" "5"

COPIED='.directories[0].files[] | select(.file | endswith("copied.md"))'
assert_eq "an HTML comment carrying a URL is a fence" \
  "$(echo "$OUT" | jq -r "$COPIED | .fences[0].source_url")" "https://github.com/acme/repo"
assert_eq "the fence carries its ISO date" \
  "$(echo "$OUT" | jq -r "$COPIED | .fences[0].date")" "2026-07-01"
assert_eq "a single-comment fence starts and ends on its own line" \
  "$(echo "$OUT" | jq -r "$COPIED | .fences[0] | \"\\(.start_line)-\\(.end_line)\"")" "1-1"

FENCED='.directories[0].files[] | select(.file | endswith("fenced.md"))'
assert_eq "a paired fence spans to its closing comment" \
  "$(echo "$OUT" | jq -r "$FENCED | .fences[] | select(.start_line == 1) | .end_line")" "4"
assert_eq "a paired fence keeps its source URL" \
  "$(echo "$OUT" | jq -r "$FENCED | .fences[] | select(.start_line == 1) | .source_url")" \
  "https://paired.example.com/src"
assert_eq "a fence with no date reports null" \
  "$(echo "$OUT" | jq -r "$FENCED | .fences[] | select(.start_line == 1) | .date")" "null"
assert_eq "a multi-line comment spans its own extent" \
  "$(echo "$OUT" | jq -r "$FENCED | .fences[] | select(.start_line == 6) | .end_line")" "9"
assert_eq "a multi-line fence finds the date inside it" \
  "$(echo "$OUT" | jq -r "$FENCED | .fences[] | select(.start_line == 6) | .date")" "2026-01-05"

MULTI="$(run --files "$DIR_A/notes.md" "$DIR_B/sibling.md" 2>/dev/null)"
assert_eq "--files groups by directory" \
  "$(echo "$MULTI" | jq -r '.directories | length')" "2"
assert_eq "each group carries only its own files" \
  "$(echo "$MULTI" | jq -r '[.directories[].files | length] | add')" "2"
assert_contains "the group names its directory" \
  "$(echo "$MULTI" | jq -r '.directories[].dir')" "topic"

assert_eq "--dir does not recurse into subdirectories" \
  "$(run --dir "$TEST_TMPDIR" 2>/dev/null | jq -r '.directories[0].files | length')" "0"

assert_eq "counts.files matches the listed files" \
  "$(echo "$OUT" | jq -r '.counts.files == ([.directories[].files | length] | add)')" "true"
assert_eq "counts.urls matches the extracted URLs" \
  "$(echo "$OUT" | jq -r '.counts.urls == ([.directories[].files[].urls | length] | add)')" "true"
assert_eq "counts.directories matches the groups" \
  "$(echo "$OUT" | jq -r '.counts.directories == (.directories | length)')" "true"

RUN_A="$(run --dir "$DIR_A" 2>/dev/null)"
RUN_B="$(run --dir "$DIR_A" 2>/dev/null)"
assert_eq "repeat runs produce identical output" "$RUN_A" "$RUN_B"

ESC_DIR="$TEST_TMPDIR/esc"
mkdir -p "$ESC_DIR"
{
  echo '# Escaping'
  # portability-ok: literal fixture prose carrying a backslash, asserted through the script's
  # JSON escaper; the \s here is document text, never a GNU regex class
  echo 'Verified 2026-02-02 against "the quoted source" and a back\slash.'
} >"$ESC_DIR/esc.md"
ESC_OUT="$(run --dir "$ESC_DIR" 2>/dev/null)"
echo "$ESC_OUT" | jq -e . >/dev/null 2>&1
assert_exit "quotes and backslashes in text stay valid JSON" "$?" "0"
# portability-ok: the \s is the fixture's literal document text round-tripping through the
# JSON escaper, never a GNU regex class
assert_contains "the escaped text round-trips" \
  "$(echo "$ESC_OUT" | jq -r '.directories[0].files[0].stamp_lines[0].text')" 'back\slash'

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
