#!/usr/bin/env bash
# Regression tests for restatement-scan.py (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/restatement-scan.py"
FIXTURES="$(cd "$SCRIPT_DIR/../evals/fixtures" && pwd)"

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

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not installed" >&2
  exit 0
fi

scan() { python3 "$SCRIPT" "$@"; }

# --- help / empty ------------------------------------------------------------
rc=0
OUT=$(scan --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help names both families" "$OUT" "I29"

rc=0
OUT=$(scan --count) || rc=$?
assert_exit "no files --count exits 0" 0 "$rc"
assert_eq "no files --count is 0" "0" "$OUT"

# --- description-restatement (I29-a) ----------------------------------------
DESC="$FIXTURES/description-restatement.md"
rc=0
OUT=$(scan "$DESC") || rc=$?
assert_exit "description-restatement scan exits 0" 0 "$rc"
assert_contains "Purpose that restates the description is I29-a" "$OUT" "$DESC:7:I29-a"
assert_not_contains "Usage with unique content is not flagged" "$OUT" ":11:I29"
assert_eq "exactly one candidate on the description fixture" "1" "$(scan --count "$DESC")"

# --- sibling-section-restatement (I29-b) ------------------------------------
SIB="$FIXTURES/sibling-restatement.md"
OUT=$(scan "$SIB")
assert_contains "NOT-do that restates Cross-references is I29-b" "$OUT" "$SIB:13:I29-b"
assert_not_contains "Cross-references itself is never a finding" "$OUT" ":5:I29"
assert_eq "exactly one candidate on the sibling fixture" "1" "$(scan --count "$SIB")"

# --- partial overlap must not flag ------------------------------------------
PART="$FIXTURES/partial-overlap.md"
assert_eq "a Purpose that echoes then adds load-bearing content is silent" \
  "0" "$(scan --count "$PART")"

# --- inline fencing is not a standalone heading -----------------------------
INLINE="$FIXTURES/inline-fence-not-section.md"
assert_eq "a bolded What-is-NOT sub-block inside Purpose is silent" \
  "0" "$(scan --count "$INLINE")"

# --- short orientation is below the mechanical floor ------------------------
# #3186 parks "deliberate short restatement in a genuinely short skill" as a
# judgment call belonging in the model-graded lane. The scanner's length and
# token floors keep that case out of the deterministic set so a three-word
# Purpose used as orientation is not a finding.
SHORT="$TEST_TMPDIR/short.md"
cat >"$SHORT" <<'EOF'
---
description: "List open PRs. Use when: 'list prs'."
---

## Purpose

List open PRs.
EOF
assert_eq "a three-word Purpose used as orientation is silent" \
  "0" "$(scan --count "$SHORT")"

# --- body-scope: a restating description line is never a row ----------------
FM="$TEST_TMPDIR/frontmatter-only.md"
cat >"$FM" <<'EOF'
---
description: "Classify markdown noise. Use when: 'audit noise'."
---
EOF
assert_eq "frontmatter-only file produces no row" "0" "$(scan --count "$FM")"

# --- missing file is skipped, not an error ----------------------------------
rc=0
OUT=$(scan "$TEST_TMPDIR/no-such.md") || rc=$?
assert_exit "missing file exits 0" 0 "$rc"
assert_eq "missing file --count is 0" "0" "$(scan --count "$TEST_TMPDIR/no-such.md")"

# --- --body-only is accepted and is a no-op ---------------------------------
assert_eq "--body-only does not change the description fixture count" \
  "1" "$(scan --count --body-only "$DESC")"

if ((FAILED > 0)); then
  printf '%s\n' "FAILED: $FAILED/$CASE_NUM" >&2
  exit 1
fi
printf '%s\n' "All $CASE_NUM checks passed"
exit 0
