#!/usr/bin/env bash
# Regression tests for conflict-scan.sh (self-contained — ships with the plugin).
# The must-not-flag cases are the point of this suite: false positives are the
# failure mode for a conflict detector, so each suppression rule is pinned here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/conflict-scan.sh"

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
if ! command -v awk >/dev/null 2>&1; then
  echo "SKIP: awk not installed" >&2
  exit 0
fi

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: the worked example — mandate vs prohibition across two files ----
MANDATE="$TEST_TMPDIR/skill-body.md"
cat >"$MANDATE" <<'EOF'
Mandatory gate: show dry-run output, then `AskUserQuestion`, then apply.
EOF
PROHIBIT="$TEST_TMPDIR/user-claude.md"
cat >"$PROHIBIT" <<'EOF'
Ask questions inline; never use the AskUserQuestion tool unless explicitly asked to use it.
EOF
rc=0
OUT=$(bash "$SCRIPT" "$MANDATE" "$PROHIBIT") || rc=$?
assert_exit "conflict scan exits 0 (advisory)" 0 "$rc"
assert_contains "worked example pairs mandate with prohibition" "$OUT" \
  "$MANDATE:1|$PROHIBIT:1|AskUserQuestion"
assert_contains "prohibition side's exception clause is flagged, not dropped" "$OUT" "exception-B"
assert_eq "worked example yields exactly one pair" "1" "$(bash "$SCRIPT" --count "$MANDATE" "$PROHIBIT")"

# --- Case 3 (MUST NOT FLAG): same-file pair is not cross-surface -------------
# The repo's sharpest false positive: a self-arbitrating absolute sitting beside
# a directive that presupposes exactly its exception, both in one file.
SAMEFILE="$TEST_TMPDIR/same-file.md"
cat >"$SAMEFILE" <<'EOF'
When asking the user a question (inline or via AskUserQuestion), include your recommendation.
Ask questions inline; never use the AskUserQuestion tool unless explicitly asked to use it.
EOF
assert_eq "same-file mandate/prohibition pair not reported" "0" "$(bash "$SCRIPT" --count "$SAMEFILE")"

# --- Case 4 (MUST NOT FLAG): an explicit opt-in gate is arbitration ----------
GATED="$TEST_TMPDIR/gated.md"
cat >"$GATED" <<'EOF'
Render the round via `AskUserQuestion` only when the plugin's use_ask_user_question user config is on.
EOF
assert_eq "config-gated mandate suppressed against a prohibition" "0" \
  "$(bash "$SCRIPT" --count "$GATED" "$PROHIBIT")"

# --- Case 5 (MUST NOT FLAG): prohibition trailing the entity, different object
# "…via `AskUserQuestion` once … Do not gate per repo." The prohibition governs
# per-repo gating, not the tool. Whole-line matching reads this as a conflict.
TRAILING="$TEST_TMPDIR/trailing.md"
cat >"$TRAILING" <<'EOF'
Show the whole-batch plan, then `AskUserQuestion` once, then apply once. Do not gate per repo.
EOF
OUT=$(bash "$SCRIPT" "$TRAILING" "$MANDATE")
assert_not_contains "trailing prohibition about another object yields no pair" "$OUT" "|AskUserQuestion|"

# --- Case 6 (MUST NOT FLAG): distant prohibition about an unrelated object ----
DISTANT="$TEST_TMPDIR/distant.md"
cat >"$DISTANT" <<'EOF'
Branches checked out in a linked worktree: never offer them for deletion, and route the user to the worktree tool to clean up first; deletion is confirmed via `AskUserQuestion` per the cleanup context file.
EOF
OUT=$(bash "$SCRIPT" "$DISTANT" "$MANDATE")
assert_not_contains "distant prohibition does not flip the entity's polarity" "$OUT" "|AskUserQuestion|"

# --- Case 7 (MUST NOT FLAG): two surfaces that AGREE are not a conflict ------
AGREE="$TEST_TMPDIR/agree.md"
cat >"$AGREE" <<'EOF'
Use `AskUserQuestion` to confirm the destructive step before applying.
EOF
assert_eq "two mandates on one entity yield no pair" "0" "$(bash "$SCRIPT" --count "$AGREE" "$MANDATE")"

# --- Case 8 (MUST NOT FLAG): different entities are different observables ----
OTHER="$TEST_TMPDIR/other-entity.md"
cat >"$OTHER" <<'EOF'
Never use the WebFetch tool for authenticated URLs.
EOF
assert_eq "disagreement about a different entity yields no pair" "0" \
  "$(bash "$SCRIPT" --count "$OTHER" "$MANDATE")"

# --- Case 9 (MUST NOT FLAG): permissive language is not a mandate ------------
PERMISSIVE="$TEST_TMPDIR/permissive.md"
cat >"$PERMISSIVE" <<'EOF'
The user may override via `AskUserQuestion` only when they explicitly accept skipping the step.
EOF
assert_eq "permissive 'may override' is not a mandate" "0" \
  "$(bash "$SCRIPT" --count "$PERMISSIVE" "$PROHIBIT")"

# --- Case 10: clean input ----------------------------------------------------
CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
Run npm test before committing.
API handlers live in src/api/handlers/.
EOF
assert_contains "clean input message" "$(bash "$SCRIPT" "$CLEAN")" "No conflict candidates found."
assert_eq "clean input count is 0" "0" "$(bash "$SCRIPT" --count "$CLEAN")"

# --- Case 11: a single file can never produce a cross-surface pair -----------
assert_eq "one file alone yields no pair" "0" "$(bash "$SCRIPT" --count "$MANDATE")"

# --- Case 12: nonexistent path skipped, not an error ------------------------
rc=0
OUT=$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.md") || rc=$?
assert_exit "nonexistent path exits 0" 0 "$rc"
assert_contains "nonexistent path yields clean message" "$OUT" "No conflict candidates found."

# --- Case 13: no file arguments ---------------------------------------------
rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "no-args exits 0" 0 "$rc"
assert_eq "no-args count is 0" "0" "$(bash "$SCRIPT" --count)"

# --- Case 14: rows are de-duplicated ----------------------------------------
DUPE="$TEST_TMPDIR/dupe.md"
cat >"$DUPE" <<'EOF'
Mandatory: `AskUserQuestion` and again `AskUserQuestion` on one line.
EOF
assert_eq "repeated entity on one line yields one pair" "1" "$(bash "$SCRIPT" --count "$DUPE" "$PROHIBIT")"

# --- Case 15: window is configurable and narrowing it drops distant tokens ---
WIDE="$TEST_TMPDIR/wide.md"
cat >"$WIDE" <<'EOF'
Never do that thing over there for some other reason entirely, and separately confirm via `AskUserQuestion`.
EOF
assert_eq "a 5-char window drops the distant prohibition" "0" \
  "$(CONFLICT_SCAN_WINDOW=5 bash "$SCRIPT" --count "$WIDE" "$AGREE")"

# --- Case 16: missing grep exits 2 ------------------------------------------
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
