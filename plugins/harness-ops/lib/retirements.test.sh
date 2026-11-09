#!/usr/bin/env bash
# Runs harness-ops' own retirements.yaml through its check-retirements.sh copy
# against fixture repositories: the morning_brief records clean only the
# block, keep the file's other keys, and the demoted records stay report-only.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/check-retirements.sh"
MANIFEST="$SCRIPT_DIR/../retirements.yaml"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
COUNT=0
pass() {
  COUNT=$((COUNT + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  COUNT=$((COUNT + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

OUT=""
RC=0
run() {
  OUT="$(bash "$HELPER" --manifest "$MANIFEST" --root "$ROOT" "$@" 2>/dev/null)"
  RC=$?
}

ROOT="$TEST_TMPDIR/repo"
mkdir -p "$ROOT/docs/conventions"
git -C "$ROOT" init -q 2>/dev/null || mkdir -p "$ROOT/.git"
TEAM="$ROOT/docs/conventions/harness-ops.yaml"
LOCAL="$ROOT/docs/conventions/harness-ops.local.yaml"
printf 'registry_dir: tools/observability/claude-troubleshooting\n\nmorning_brief:\n  plan: max\n  budget: 20\n\nverification:\n  command: npm test\n' >"$TEAM"
printf 'morning_brief:\n  subscription: max20\n' >"$LOCAL"

run
assert_eq "detection exits 1 on the active block leftovers" 1 "$RC"
assert_eq "r002/r003 report-only, r004/r005 active, as kind and status" \
  "harness-ops-r002 file report-only|harness-ops-r003 file report-only|harness-ops-r004 block active|harness-ops-r005 block active" \
  "$(printf '%s\n' "$OUT" | awk -F '\t' '{ printf "%s%s %s %s", sep, $1, $2, $5; sep = "|" }')"

run --clean harness-ops-r004
assert_eq "r004 clean without --i-migrated is refused" 2 "$RC"

run --clean harness-ops-r004 --i-migrated
assert_eq "r004 clean exits 0" 0 "$RC"
expected="$TEST_TMPDIR/team-expected"
printf 'registry_dir: tools/observability/claude-troubleshooting\n\nverification:\n  command: npm test\n' >"$expected"
if cmp -s "$expected" "$TEAM"; then
  pass "r004 removes the morning_brief block and keeps registry_dir and verification byte for byte"
else
  fail "r004 removes the morning_brief block and keeps registry_dir and verification byte for byte" "$(cat "$TEAM")"
fi

run --clean harness-ops-r005 --i-migrated
assert_eq "r005 clean exits 0" 0 "$RC"
if [[ -e "$LOCAL" ]]; then
  fail "r005 removes a harness-ops.local.yaml that held only the block" "still present"
else
  pass "r005 removes a harness-ops.local.yaml that held only the block"
fi

run
assert_eq "detection is clean afterwards" 0 "$RC"
assert_eq "no row is left, report-only ones included" "" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$COUNT"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$COUNT" >&2
exit 1
