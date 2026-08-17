#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib; fixtures are built
# inline in a tmpdir, so the plugin ships no slop samples for the audit to trip
# over). Per the shell-test-helpers convention, assertion helpers are local.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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

# --- Fixtures (built inline) ----------------------------------------------------

SLOP="$TEST_TMPDIR/slop.md"
cat >"$SLOP" <<EOF
# A pivotal document

This stands as a testament to the vibrant tapestry of the field ${EM} a
crucial, groundbreaking interplay that will delve into the intricacies.
Meticulously bolstered, showcasing renowned and enduring work.
EOF

CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
# Release notes

The parser now accepts empty input. Tests cover the three failure paths.
See the changelog for upgrade steps.
EOF

MARKED="$TEST_TMPDIR/marked.md"
cat >"$MARKED" <<EOF
# Marker handling

An exempted line ${EM} with an em dash. <!-- ai-slop-ignore -->
EOF

FENCED="$TEST_TMPDIR/fenced.md"
cat >"$FENCED" <<EOF
# Code fences

\`\`\`text
An em dash inside a fence ${EM} stays exempt.
\`\`\`

And one in inline code: \`a ${EM} b\` also stays exempt.
EOF

FILEMARK="$TEST_TMPDIR/filemark.md"
cat >"$FILEMARK" <<EOF
<!-- ai-slop-ignore-file: catalog-style file -->
Full of em dashes ${EM} and delve, tapestry, pivotal, crucial vocabulary.
EOF

# --- Cases ----------------------------------------------------------------------

out="$(bash "$DETECT" "$SLOP" 2>&1)"
rc=$?
assert_exit "slop fixture: exit 0" 0 "$rc"
assert_contains "slop fixture: em-dash rule fires" "$out" "rule=ai-slop/audit/rule-em-dash"
assert_contains "slop fixture: em-dash fired condition is zero-tolerance" "$out" "fired=zero-tolerance"
assert_contains "slop fixture: vocabulary rule fires" "$out" "rule=ai-slop/audit/rule-ai-vocabulary"
assert_contains "slop fixture: vocabulary fired condition carries threshold" "$out" "threshold 3.0"

out="$(bash "$DETECT" "$CLEAN" 2>&1)"
rc=$?
assert_exit "clean fixture: exit 0" 0 "$rc"
assert_not_contains "clean fixture: no findings" "$out" "Finding:"
assert_contains "clean fixture: summary reports zero" "$out" "Summary total: 0 findings"

out="$(bash "$DETECT" "$MARKED" 2>&1)"
assert_not_contains "line marker: em dash on marked line not flagged" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "line marker: declined count nonzero" "$out" "declined=1"

out="$(bash "$DETECT" "$FENCED" 2>&1)"
assert_not_contains "fences: fenced and inline-code em dashes not flagged" "$out" "Finding:"

out="$(bash "$DETECT" "$FILEMARK" 2>&1)"
assert_not_contains "file marker: whole file exempt" "$out" "Finding:"
assert_contains "file marker: counted as declined file" "$out" "(1 files declined)"

out="$(bash "$DETECT" --paths-file "$TEST_TMPDIR/nope" 2>&1)"
rc=$?
assert_exit "unreadable paths-file: exit 2" 2 "$rc"

out="$(bash "$DETECT" --bogus 2>&1)"
rc=$?
assert_exit "unknown option: exit 2" 2 "$rc"

pf="$TEST_TMPDIR/paths.txt"
printf '%s\n%s\n' "$SLOP" "$CLEAN" >"$pf"
out="$(bash "$DETECT" --paths-file "$pf" --offset 0 --limit 1 2>&1)"
assert_contains "chunking: limit 1 scans one file" "$out" "across 1 files scanned"

cfgdir="$TEST_TMPDIR/repo/.claude"
mkdir -p "$cfgdir"
cp "$SLOP" "$TEST_TMPDIR/repo/allowed.md"
cat >"$cfgdir/ai-slop.json" <<'EOF'
{ "em_dash_allowed_paths": ["allowed.md"], "threshold_ai_vocabulary": 999 }
EOF
out="$(cd "$TEST_TMPDIR/repo" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" "$TEST_TMPDIR/repo/allowed.md" 2>&1)"
assert_not_contains "config: em_dash_allowed_paths exempts the document" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_not_contains "config: raised threshold silences vocabulary rule" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"

out="$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" --show-config 2>&1)"
assert_contains "show-config: names the supplying layer" "$out" "$cfgdir/ai-slop.json"
assert_contains "show-config: effective threshold shown" "$out" "threshold_ai_vocabulary=999"

# Portability probe: identical output under LC_ALL=C and the default locale.
a="$(bash "$DETECT" "$SLOP" 2>&1)"
b="$(LC_ALL=C bash "$DETECT" "$SLOP" 2>&1)"
if [[ "$a" == "$b" ]]; then
  pass "portability: output identical under LC_ALL=C"
else
  fail "portability: output identical under LC_ALL=C" "identical" "differs"
fi

# --- Result ---------------------------------------------------------------------

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed"
  exit 0
else
  echo "$FAILED of $CASE_NUM cases FAILED"
  exit 1
fi
