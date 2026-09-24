#!/usr/bin/env bash
# Self-contained tests for cross-check.sh: fixtures are built inline in a
# tmpdir, with the same git and config isolation as detect.test.sh.
# Fixture text holds literal backticks inside single-quoted printf formats.
# shellcheck disable=SC2016
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROSS="$SCRIPT_DIR/cross-check.sh"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

FAILED=0
CASE_NUM=0
SKIPPED=0
# PASS + FAIL + SKIP when every case runs; see detect.test.sh for the contract.
EXPECTED_CASES=19

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
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

EM=$'\xe2\x80\x94'
F="$TEST_TMPDIR/docs"
mkdir -p "$F"

printf '# Plain\n\nOne %s two %s three.\nClean line.\nAnother %s here.\n' "$EM" "$EM" "$EM" >"$F/plain.md"
printf -- '- item\n- ```sh\n  echo a %s b\n  ```\n\nText %s here.\n' "$EM" "$EM" >"$F/listfence.md"
{
  printf 'Code `a %s b` only.\n' "$EM"
  printf 'Line with %s dash <!-- ai-slop-ignore: quoted title -->\n' "$EM"
  printf '<!-- ai-slop-ignore-start -->\nBlock %s dash.\n<!-- ai-slop-ignore-end -->\n' "$EM"
  printf 'Counted %s dash.\n' "$EM"
  printf 'Mention `<!-- ai-slop-ignore -->` and %s dash.\n' "$EM"
} >"$F/markers.md"
printf 'Before %s the marker.\n<!-- ai-slop-ignore-file -->\nAfter %s it.\n' "$EM" "$EM" >"$F/filemark.md"
# An unclosed fence in a list item ends when a non-blank line dedents past the
# item's content column.
printf -- '- ```sh\n  echo a %s b\nDedented %s line.\n' "$EM" "$EM" >"$F/dedent.md"
# None of these lines opens a fence under the detector rules: a four-space
# indent, a tab indent, five spaces after a list marker, a ten-digit ordinal.
{
  printf '    ```\nA %s one.\n\n' "$EM"
  printf '\t```\nA %s two.\n\n' "$EM"
  printf -- '-     ```\nA %s three.\n\n' "$EM"
  printf '1234567890. ```\nA %s four.\n' "$EM"
} >"$F/notfence.md"

T="$TEST_TMPDIR/targets.tsv"
printf '%s\t%s\n' plain.md "$F/plain.md" listfence.md "$F/listfence.md" markers.md "$F/markers.md" \
  filemark.md "$F/filemark.md" >"$T"

# --- counting -------------------------------------------------------------------

out="$(bash "$CROSS" --targets "$T" 2>&1)"
rc=$?
assert_exit "count: exit 0" 0 "$rc"
assert_contains "count: two em-dash lines, one of them holding two dashes" "$out" "CrossCheck: file=plain.md em_dash_lines=2"
assert_contains "count: a fence opened after a list marker is code" "$out" "CrossCheck: file=listfence.md em_dash_lines=1"
assert_contains "count: inline code and ignore markers are not counted" "$out" "CrossCheck: file=markers.md em_dash_lines=2"
assert_contains "count: a file marker skips the whole file" "$out" "CrossCheck: file=filemark.md em_dash_lines=0"
assert_not_contains "count: no total without detector output" "$out" "CrossCheck total:"
printf '%s\t%s\n' dedent.md "$F/dedent.md" >"$TEST_TMPDIR/dedent.tsv"
out="$(bash "$CROSS" --targets "$TEST_TMPDIR/dedent.tsv" 2>&1)"
assert_contains "count: a dedented line closes a list-item fence" "$out" "CrossCheck: file=dedent.md em_dash_lines=1"
printf '%s\t%s\n' notfence.md "$F/notfence.md" >"$TEST_TMPDIR/notfence.tsv"
out="$(bash "$CROSS" --targets "$TEST_TMPDIR/notfence.tsv" 2>&1)"
assert_contains "count: openers the detector rejects stay prose" "$out" "CrossCheck: file=notfence.md em_dash_lines=4"

bash "$CROSS" >/dev/null 2>&1
rc=$?
assert_exit "usage: no --targets exits 2" 2 "$rc"

# --- comparison with hand-written detector output ---------------------------------

D="$TEST_TMPDIR/detector.txt"
{
  printf 'Finding: rule=ai-slop/audit/rule-em-dash file=plain.md line=%d fired=zero-tolerance excerpt=x\n' 3 5
  printf 'Finding: rule=ai-slop/audit/rule-em-dash file=listfence.md line=6 fired=zero-tolerance excerpt=x\n'
  printf 'Finding: rule=ai-slop/audit/rule-em-dash file=markers.md line=%d fired=zero-tolerance excerpt=x\n' 6 7
  printf 'Declined: file=filemark.md cause=file-marker\n'
} >"$D"
out="$(bash "$CROSS" --targets "$T" --detector "$D" 2>&1)"
assert_not_contains "agree: matching counts print no Disagree row" "$out" "Disagree:"
assert_contains "agree: a declined file is skipped" "$out" "CrossCheck: file=filemark.md skipped=declined"
assert_contains "agree: total counts compared files only" "$out" "CrossCheck total: files=3 disagreements=0"

printf 'Finding: rule=ai-slop/audit/rule-em-dash file=plain.md line=4 fired=zero-tolerance excerpt=x\n' >>"$D"
out="$(bash "$CROSS" --targets "$T" --detector "$D" 2>&1)"
assert_contains "disagree: a wrong detector count is reported" "$out" "Disagree: file=plain.md detector=3 cross_check=2"
assert_contains "disagree: the total counts it" "$out" "CrossCheck total: files=3 disagreements=1"

# --- config: allowed paths and a disabled rule ---------------------------------------

if command -v jq >/dev/null 2>&1; then
  A="$TEST_TMPDIR/allowcfg"
  mkdir -p "$A/.claude"
  printf '%s\n' '{ "rule_allowed_paths": { "rule-em-dash": ["plain.*"] } }' >"$A/.claude/ai-slop.json"
  out="$(CLAUDE_PROJECT_DIR="$A" bash "$CROSS" --targets "$T" --detector "$D" 2>&1)"
  assert_contains "allowed: a rule_allowed_paths file is skipped" "$out" "CrossCheck: file=plain.md skipped=rule-allowed"
  assert_not_contains "allowed: and never compared" "$out" "Disagree: file=plain.md"

  X="$TEST_TMPDIR/disabledcfg"
  mkdir -p "$X/.claude"
  printf '%s\n' '{ "disabled_rules": ["rule-em-dash"] }' >"$X/.claude/ai-slop.json"
  out="$(CLAUDE_PROJECT_DIR="$X" bash "$CROSS" --targets "$T" --detector "$D" 2>&1)"
  assert_contains "disabled: the comparison is skipped" "$out" "CrossCheck: comparison skipped: rule-em-dash disabled"
  assert_not_contains "disabled: no file rows" "$out" "CrossCheck: file="
else
  for c in "allowed: a rule_allowed_paths file is skipped" "allowed: and never compared" \
    "disabled: the comparison is skipped" "disabled: no file rows"; do
    skip "$c" "jq not on PATH, config unread"
  done
fi

# --- the real detector over the same fixtures ----------------------------------------

RT="$TEST_TMPDIR/real-targets.tsv"
RD="$TEST_TMPDIR/real-detector.txt"
bash "$DETECT" --list-targets "$F" >"$RT" 2>/dev/null
bash "$DETECT" --paths-file "$RT" >"$RD" 2>/dev/null
out="$(bash "$CROSS" --targets "$RT" --detector "$RD" 2>&1)"
assert_contains "real detector: zero disagreements over the fixtures" "$out" "CrossCheck total: files=5 disagreements=0"

# --- Result ---------------------------------------------------------------------

echo
TOTAL=$((CASE_NUM + SKIPPED))
RC=0
if [[ "$TOTAL" -ne "$EXPECTED_CASES" ]]; then
  RC=1
  printf 'CASE COUNT MISMATCH: ran %d cases (%d pass/fail + %d host skip), expected %d.\n' \
    "$TOTAL" "$CASE_NUM" "$SKIPPED" "$EXPECTED_CASES" >&2
fi
if [[ "$FAILED" -ne 0 ]]; then
  RC=1
  echo "$FAILED of $CASE_NUM cases FAILED, $SKIPPED host skip(s)"
elif [[ "$RC" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed, $SKIPPED host skip(s)"
fi
exit "$RC"
