#!/usr/bin/env bash
# The repository's own script-generated docs open their generated block with the
# standalone BEGIN GENERATED marker line detect.sh skips. Each case copies the
# committed file, plants an em dash just inside the block and another after the
# file's end, and expects only the outside one flagged: a marker the detector
# does not recognize lets the fix-docs lane edit text its generator overwrites.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Shipped defaults only: this repository's ai-slop.yaml disables rule-em-dash.
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

DOCS=(
  docs/catalog.md
  docs/skill-cheat-sheet.md
  docs/native-surfaces.md
  plugins/harness-ops/evals/fixtures/an-native-surfaces.md
  plugins/sql-server/reference/read-safety-measurement.md
)

FAILED=0
CASE_NUM=0
EXPECTED_CASES=$((${#DOCS[@]} * 3))

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
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

for doc in "${DOCS[@]}"; do
  fixture="$TEST_TMPDIR/$(basename "$doc")"
  awk -v inside="Planted inside ${EM} sentinel-inside." -v outside="Planted outside ${EM} sentinel-outside." '
    { print }
    !planted && /^<!-- BEGIN GENERATED:[^>]*-->$/ { print ""; print inside; print ""; planted = 1 }
    END { print ""; print outside }
  ' "$REPO_ROOT/$doc" >"$fixture"
  out="$(bash "$DETECT" "$fixture" 2>&1)"
  planted="$(grep -c 'sentinel-inside' "$fixture")"
  assert_contains "$doc: carries a standalone BEGIN GENERATED marker" "planted=$planted" "planted=1"
  assert_not_contains "$doc: the line inside the generated block is skipped" "$out" "sentinel-inside"
  assert_contains "$doc: the line after the block is still scanned" "$out" "sentinel-outside"
done

printf '\nResult: %d/%d passed\n' "$((CASE_NUM - FAILED))" "$CASE_NUM"
if [[ "$CASE_NUM" -ne "$EXPECTED_CASES" ]]; then
  printf 'expected %d cases, ran %d\n' "$EXPECTED_CASES" "$CASE_NUM" >&2
  exit 1
fi
[[ "$FAILED" -eq 0 ]]
