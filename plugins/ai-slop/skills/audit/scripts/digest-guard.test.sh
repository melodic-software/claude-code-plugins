#!/usr/bin/env bash
# Self-contained tests for digest-guard.sh: fixtures are built inline in a
# tmpdir, and each refusal is checked to leave nothing behind.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/digest-guard.sh"
TEST_TMPDIR="$(cd -P "$(mktemp -d)" && pwd)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
unset AI_SLOP_STATE_ROOT

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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
# Runs the guard under a state root, leaving its exit status in RC and its
# stdout in OUT.
guard() {
  local root="$1"
  shift
  OUT="$(AI_SLOP_STATE_ROOT="$root" bash "$GUARD" "$@" 2>/dev/null)"
  RC=$?
}

ROOT="$TEST_TMPDIR/scratch"
OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$ROOT" "$OUTSIDE"
RUN="$ROOT/ai-slop-fix-20261029T120000Z"
DOC="$TEST_TMPDIR/doc.md"
printf 'one\n' >"$DOC"

# Case group 1: init, record and check.
guard "$ROOT" init "$RUN"
assert_eq "init: exit 0" "0" "$RC"
assert_eq "init: prints the run directory" "$RUN" "$OUT"
guard "$ROOT" init "$RUN"
assert_eq "init: an existing run directory is refused" "2" "$RC"
guard "$ROOT" record "$DOC" "$RUN"
assert_eq "record: exit 0" "0" "$RC"
assert_eq "record: one flat state file" "1" "$(find "$RUN/digests" -type f -name '*.sha256' | wc -l | tr -d ' ')"
assert_eq "record: no staging file left" "0" "$(find "$RUN/digests" -name '.tmp.*' | wc -l | tr -d ' ')"
guard "$ROOT" check "$DOC" "$RUN"
assert_eq "check: an unchanged file matches" "0 match" "$RC $OUT"
printf 'two\n' >>"$DOC"
guard "$ROOT" check "$DOC" "$RUN"
assert_eq "check: a changed file mismatches" "1 mismatch" "$RC $OUT"
guard "$ROOT" record "$DOC" "$RUN"
guard "$ROOT" check "$DOC" "$RUN"
assert_eq "check: a re-record matches again" "0 match" "$RC $OUT"
guard "$ROOT" check "$TEST_TMPDIR/other.md" "$RUN"
assert_eq "check: a missing file is refused" "2" "$RC"
printf 'x\n' >"$TEST_TMPDIR/unrecorded.md"
guard "$ROOT" check "$TEST_TMPDIR/unrecorded.md" "$RUN"
assert_eq "check: an unrecorded file is refused, not matched" "2" "$RC"
RUN2="$ROOT/ai-slop-fix-20261029T120000Z-2"
guard "$ROOT" record "$DOC" "$RUN2"
assert_eq "record: creates an absent run directory" "0 yes" "$RC $([[ -d "$RUN2/digests" ]] && echo yes || echo no)"

# Case group 2: what the guard refuses.
(cd "$TEST_TMPDIR" && AI_SLOP_STATE_ROOT="$ROOT" bash "$GUARD" record doc.md "$RUN" >/dev/null 2>&1)
assert_eq "a relative file path is refused" "2" "$?"
guard "$ROOT" record "$TEST_TMPDIR" "$RUN"
assert_eq "a directory is refused" "2" "$RC"
guard "$ROOT" record "$DOC" "$ROOT/digests"
assert_eq "a run directory with another name is refused" "2" "$RC"
guard "$ROOT" record "$DOC" "$OUTSIDE/ai-slop-fix-20261029T120000Z"
assert_eq "an absolute run directory outside the root is refused" "2" "$RC"
guard "$ROOT" record "$DOC" "$ROOT/../outside/ai-slop-fix-20261029T120000Z"
assert_eq "a .. run directory that leaves the root is refused" "2" "$RC"
guard "$ROOT" init "$ROOT/../outside/ai-slop-fix-20261029T120000Z"
assert_eq "init: a .. run directory that leaves the root is refused" "2" "$RC"
ln -s "$OUTSIDE" "$ROOT/escape"
guard "$ROOT" record "$DOC" "$ROOT/escape/ai-slop-fix-20261029T120000Z"
assert_eq "a symlinked parent that leaves the root is refused" "2" "$RC"
ln -s "$OUTSIDE" "$ROOT/ai-slop-fix-20261029T130000Z"
guard "$ROOT" record "$DOC" "$ROOT/ai-slop-fix-20261029T130000Z"
assert_eq "a symlinked run directory is refused" "2" "$RC"
RUN3="$ROOT/ai-slop-fix-20261029T140000Z"
mkdir "$RUN3"
ln -s "$OUTSIDE" "$RUN3/digests"
guard "$ROOT" record "$DOC" "$RUN3"
assert_eq "a symlinked digests directory is refused" "2" "$RC"
assert_eq "no refusal wrote outside the root" "" "$(ls -A "$OUTSIDE")"
guard "$ROOT" frob "$DOC" "$RUN"
assert_eq "an unknown subcommand is a usage error" "2" "$RC"
guard "$ROOT" record "$DOC"
assert_eq "a missing run directory argument is a usage error" "2" "$RC"

# Case group 3: with no AI_SLOP_STATE_ROOT, a copy staged as a CI lane stages it
# takes the lane's scratch directory as its root.
LANE="$TEST_TMPDIR/ws/.lane"
mkdir -p "$LANE/plugins/ai-slop/skills/audit/scripts" "$LANE/scratch"
cp "$GUARD" "$LANE/plugins/ai-slop/skills/audit/scripts/digest-guard.sh"
LANE_GUARD="$LANE/plugins/ai-slop/skills/audit/scripts/digest-guard.sh"
bash "$LANE_GUARD" record "$DOC" "$LANE/scratch/ai-slop-fix-20261029T120000Z" >/dev/null 2>&1
assert_eq "lane copy: a run directory in the scratch directory is accepted" "0" "$?"
bash "$LANE_GUARD" record "$DOC" "$OUTSIDE/ai-slop-fix-20261029T120000Z" >/dev/null 2>&1
assert_eq "lane copy: a run directory outside the scratch directory is refused" "2" "$?"
bash "$LANE_GUARD" record "$DOC" "$LANE/scratch/../../ai-slop-fix-20261029T120000Z" >/dev/null 2>&1
assert_eq "lane copy: a .. run directory that leaves the scratch directory is refused" "2" "$?"
assert_eq "lane copy: nothing written beside the lane directory" ".lane" "$(ls -A "$TEST_TMPDIR/ws")"
assert_eq "lane copy: nothing written outside the scratch directory" "" "$(ls -A "$OUTSIDE")"
# The lane runs the script by its shebang, with no bash <path> rule.
if [[ -x "$GUARD" ]]; then pass "the script is executable"; else fail "the script is executable" "-x" "not executable"; fi

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
