#!/usr/bin/env bash
# Self-contained tests for extract-breadcrumbs.sh. Fixtures are built inline in
# a tmpdir. Per the shell-test-helpers convention, assertion helpers are local.
#
# The load-bearing case here is per-directory grouping: spike S1 resolved a real
# cross-file breadcrumb (a neighbor's citation named an unfenced copy's source),
# so siblings have to travel together or the resolving step never sees them.
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
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# --- Fixtures --------------------------------------------------------------------

DIR_A="$TEST_TMPDIR/topic"
DIR_B="$TEST_TMPDIR/other"
mkdir -p "$DIR_A" "$DIR_B"

# Line numbers below are asserted, so this fixture's layout is load-bearing.
{
  echo '# Notes'                                                       # 1
  echo ''                                                              # 2
  echo 'See [the skills doc](https://code.claude.com/docs/skills.md).' # 3
  echo ''                                                              # 4
  echo 'A bare link: https://example.com/page and prose after.'        # 5
  echo ''                                                              # 6
  echo '> A quoted excerpt from somewhere upstream.'                   # 7
  echo ''                                                              # 8
  echo 'Verified 2026-08-12 against the live page.'                    # 9
  echo ''                                                              # 10
  echo '```bash'                                                       # 11
  echo 'curl https://api.example.com/v1/thing'                         # 12
  echo '```'                                                           # 13
  echo ''                                                              # 14
  echo 'An angle link: <https://angle.example.com/doc>.'               # 15
} >"$DIR_A/notes.md"

{
  echo '<!-- Vendored from https://github.com/acme/repo on 2026-07-01. -->' # 1
  echo '# Copied page'                                                      # 2
  echo ''                                                                   # 3
  echo 'Body text with no breadcrumb of its own.'                           # 4
} >"$DIR_A/copied.md"

{
  echo '# Empty of breadcrumbs' # 1
  echo ''                       # 2
  echo 'Nothing to see here.'   # 3
} >"$DIR_A/bare.md"

{
  echo '<!-- provenance: https://paired.example.com/src -->' # 1
  echo 'Fenced body line one.'                               # 2
  echo 'Fenced body line two.'                               # 3
  echo '<!-- /provenance -->'                                # 4
  echo ''                                                    # 5
  echo '<!--'                                                # 6
  echo 'Multi-line comment citing https://multi.example.com' # 7
  echo 'as of 2026-01-05.'                                   # 8
  echo '-->'                                                 # 9
} >"$DIR_A/fenced.md"

{
  echo '# Sibling'                            # 1
  echo ''                                     # 2
  echo 'As of April 2022 this was accurate.'  # 3
  echo 'Changelog entry dated 2026-03-04.'    # 4
  echo 'Quote with a "straight quoted" span.' # 5
} >"$DIR_B/sibling.md"

run() { bash "$EXTRACT" "$@"; }

# --- Usage -----------------------------------------------------------------------

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

# --- Product shape ---------------------------------------------------------------

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

# --- URLs ------------------------------------------------------------------------

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

# --- Stamps and quotes -----------------------------------------------------------

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

# --- Fences ----------------------------------------------------------------------

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

# --- Per-directory grouping ------------------------------------------------------

MULTI="$(run --files "$DIR_A/notes.md" "$DIR_B/sibling.md" 2>/dev/null)"
assert_eq "--files groups by directory" \
  "$(echo "$MULTI" | jq -r '.directories | length')" "2"
assert_eq "each group carries only its own files" \
  "$(echo "$MULTI" | jq -r '[.directories[].files | length] | add')" "2"
assert_contains "the group names its directory" \
  "$(echo "$MULTI" | jq -r '.directories[].dir')" "topic"

assert_eq "--dir does not recurse into subdirectories" \
  "$(run --dir "$TEST_TMPDIR" 2>/dev/null | jq -r '.directories[0].files | length')" "0"

# --- Counts and determinism ------------------------------------------------------

assert_eq "counts.files matches the listed files" \
  "$(echo "$OUT" | jq -r '.counts.files == ([.directories[].files | length] | add)')" "true"
assert_eq "counts.urls matches the extracted URLs" \
  "$(echo "$OUT" | jq -r '.counts.urls == ([.directories[].files[].urls | length] | add)')" "true"
assert_eq "counts.directories matches the groups" \
  "$(echo "$OUT" | jq -r '.counts.directories == (.directories | length)')" "true"

RUN_A="$(run --dir "$DIR_A" 2>/dev/null)"
RUN_B="$(run --dir "$DIR_A" 2>/dev/null)"
assert_eq "repeat runs produce identical output" "$RUN_A" "$RUN_B"

# --- JSON escaping ---------------------------------------------------------------

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
