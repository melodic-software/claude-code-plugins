#!/usr/bin/env bash
# Regression tests for instruction-scan.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-scan.sh"

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
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "unexpected substring: $3" ;;
    *) pass "$1" ;;
  esac
}

if ! command -v grep >/dev/null 2>&1; then
  echo "SKIP: grep not installed" >&2
  exit 0
fi

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: I6 bare prohibitions flagged -----------------------------------
I6F="$TEST_TMPDIR/i6.md"
cat >"$I6F" <<'EOF'
Never commit secrets to the repository.
Do not use bare Bash grants in auto mode.
Always run the tests before pushing.
EOF
rc=0
OUT=$(bash "$SCRIPT" "$I6F") || rc=$?
assert_exit "I6 scan exits 0 (advisory)" 0 "$rc"
assert_contains "flags 'Never' prohibition on line 1" "$OUT" "$I6F:1:I6"
assert_contains "flags 'Do not' prohibition on line 2" "$OUT" "$I6F:2:I6"
assert_not_contains "positive 'Always' instruction not flagged" "$OUT" ":3:I6"
assert_eq "two I6 candidates" "2" "$(bash "$SCRIPT" --count "$I6F")"

# --- Case 3: prohibition WITH rationale not flagged -------------------------
I6R="$TEST_TMPDIR/i6-rationale.md"
cat >"$I6R" <<'EOF'
Never force-push to main because it rewrites shared history.
Do not skip the lint step, since CI will reject the PR otherwise.
EOF
assert_eq "rationale-bearing prohibitions not flagged" "0" "$(bash "$SCRIPT" --count "$I6R")"

# --- Case 4: I10 reasoning-echo directives flagged --------------------------
I10F="$TEST_TMPDIR/i10.md"
cat >"$I10F" <<'EOF'
Show your thinking before giving the final answer.
Explain your reasoning step by step in the response.
Think out loud as you work through the problem.
Summarize the changes in two bullet points.
EOF
OUT=$(bash "$SCRIPT" "$I10F")
assert_contains "flags 'Show your thinking'" "$OUT" "$I10F:1:I10"
assert_contains "flags 'Explain your reasoning'" "$OUT" "$I10F:2:I10"
assert_contains "flags 'Think out loud'" "$OUT" "$I10F:3:I10"
assert_not_contains "benign summarize instruction not flagged" "$OUT" ":4:I10"
assert_eq "three I10 candidates" "3" "$(bash "$SCRIPT" --count "$I10F")"

# --- Case 5: clean file ------------------------------------------------------
CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
Use ES modules syntax.
Run npm test before committing.
API handlers live in src/api/handlers/.
EOF
assert_contains "clean file message" "$(bash "$SCRIPT" "$CLEAN")" "No instruction candidates found."
assert_eq "clean file count is 0" "0" "$(bash "$SCRIPT" --count "$CLEAN")"

# --- Case 6: multiple files aggregate ---------------------------------------
assert_eq "aggregate count across files" "5" "$(bash "$SCRIPT" --count "$I6F" "$I10F")"

# --- Case 7: nonexistent path skipped, not an error -------------------------
rc=0
OUT=$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.md") || rc=$?
assert_exit "nonexistent path exits 0" 0 "$rc"
assert_contains "nonexistent path yields clean message" "$OUT" "No instruction candidates found."

# --- Case 8: no file arguments ----------------------------------------------
rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "no-args exits 0" 0 "$rc"
assert_eq "no-args count is 0" "0" "$(bash "$SCRIPT" --count)"

# --- Case 9: missing grep exits 2 -------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" "$CLEAN" 2>&1) || rc=$?
assert_exit "exit 2 when grep missing" 2 "$rc"
assert_contains "grep required message" "$err_out" "grep required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
