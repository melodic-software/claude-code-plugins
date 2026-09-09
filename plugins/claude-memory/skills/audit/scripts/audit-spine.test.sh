#!/usr/bin/env bash
# Regression tests for audit-spine.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-spine.sh"

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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 in: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

# --- Case 1: --help ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: a repo with one of each finding ---
# The auto-memory dir is resolved from the fixture repo's own identity, which has no
# memory directory on this machine, so the M lines report 0 and M2 reports nothing.

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/.claude/rules" "$REPO/sub"
printf '@AGENTS.md\n' >"$REPO/CLAUDE.md"
printf '# Root\n\nline a\nline b\n' >"$REPO/AGENTS.md"
printf '# Anonymous\n\nbody\n' >"$REPO/.claude/rules/anonymous.md"
printf -- '---\npaths:\n  - "**/*.py"\n---\n# Scoped\n' >"$REPO/.claude/rules/scoped.md"
printf 'nested\n' >"$REPO/sub/AGENTS.md"
(cd "$REPO" && git add -A && git commit -q -m fixture)

rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_eq "spine exits 0 with findings present" 0 "$rc"
assert_contains "header: rules split into always-loaded and path-scoped" "$OUT" "Rules files: 2 (always-loaded: 1, path-scoped: 1)"
assert_contains "header: root file named" "$OUT" "Project root file: CLAUDE.md"
assert_contains "header: root count is import-expanded (1 + 3)" "$OUT" "Root file loaded lines, @imports expanded (200 target): 4"
assert_contains "header: N1 count" "$OUT" "Nested AGENTS.md unwired (N1): 1"
assert_contains "header: RD1 count" "$OUT" "Orphan always-loaded rules (RD1): 1"
assert_contains "header: M2 count" "$OUT" "MEMORY.md index issues (M2): 0"
assert_contains "findings: N1 line folded in" "$OUT" "FAIL [N1]: sub/AGENTS.md"
assert_contains "findings: RD1 line folded in" "$OUT" "WARN [RD1]: .claude/rules/anonymous.md"

# --- Case 3: --summary prints the header only ---

OUT=$(cd "$REPO" && bash "$SCRIPT" --summary)
assert_contains "--summary keeps the header" "$OUT" "Nested AGENTS.md unwired (N1): 1"
assert_not_contains "--summary omits the findings block" "$OUT" "Findings:"

# --- Case 4: a clean repo says so ---

printf '@AGENTS.md\n' >"$REPO/sub/CLAUDE.md"
printf -- '---\ndescription: named\n---\n# Named\n\nbody\n' >"$REPO/.claude/rules/anonymous.md"
(cd "$REPO" && git add -A && git commit -q -m clean)
OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean spine reports no findings" "$OUT" "none from the deterministic spine"
assert_contains "clean N1 count" "$OUT" "Nested AGENTS.md unwired (N1): 0"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
