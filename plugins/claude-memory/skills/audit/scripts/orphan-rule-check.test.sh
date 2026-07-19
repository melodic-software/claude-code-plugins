#!/usr/bin/env bash
# Regression tests for orphan-rule-check.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/orphan-rule-check.sh"

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

# Fixture git repos must never inherit an outer hook chain's exported git env —
# otherwise fixture commits mutate the REAL repo.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Build a fixture repo with three rules + one referencing surface ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/.claude/rules"

# always-loaded (no frontmatter), referenced by CLAUDE.md => NOT orphan
printf '# Referenced Rule\n\nbody\n' >"$REPO/.claude/rules/referenced.md"
# always-loaded (no frontmatter), referenced nowhere => ORPHAN
printf '# Orphan Rule\n\nbody\n' >"$REPO/.claude/rules/orphan.md"
# path-scoped (has paths:), referenced nowhere => EXEMPT (not flagged)
printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Scoped Rule\n' >"$REPO/.claude/rules/scoped.md"
# referencing surface
printf '# Project\n\nSee referenced.md for details.\n' >"$REPO/CLAUDE.md"

(cd "$REPO" && git add -A && git commit -q -m "fixture")

# --- Case 2: report flags ONLY the orphan ---

rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_exit "report exits 0 (advisory)" 0 "$rc"
assert_contains "flags orphan.md" "$OUT" "orphan.md"
assert_not_contains "does NOT flag referenced.md" "$OUT" "referenced.md"
assert_not_contains "does NOT flag path-scoped scoped.md" "$OUT" "scoped.md"

# --- Case 3: --count returns 1 ---

OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 1" "1" "$OUT"

# --- Case 4: once referenced, orphan clears ---

printf '\nAlso see orphan.md.\n' >>"$REPO/CLAUDE.md"
(cd "$REPO" && git add -A && git commit -q -m "reference orphan")
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 0 after referencing" "0" "$OUT"

# --- Case 5: clean repo report message ---

OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean repo reports no orphans" "$OUT" "No orphan"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
