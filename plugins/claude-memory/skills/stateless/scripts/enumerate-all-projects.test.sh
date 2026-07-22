#!/usr/bin/env bash
# Regression tests for enumerate-all-projects.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/enumerate-all-projects.sh"

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

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: no projects directory at all -> note, exit 0 ---

H2="$TEST_TMPDIR/h2"
mkdir -p "$H2"
rc=0
OUT=$(HOME="$H2" bash "$SCRIPT") || rc=$?
assert_exit "missing projects root exits 0" 0 "$rc"
assert_contains "missing projects root reported" "$OUT" "No projects directory"

# --- Case 3: two project memory dirs with MEMORY.md + topic files are listed ---

H3="$TEST_TMPDIR/h3"
M3A="$H3/.claude/projects/C--proj-alpha/memory"
M3B="$H3/.claude/projects/C--proj-beta/memory"
mkdir -p "$M3A" "$M3B"
printf '# Index\n- one\n- two\n' >"$M3A/MEMORY.md"
printf 'topic\n' >"$M3A/debugging.md"
printf '# Index\n- one\n' >"$M3B/MEMORY.md"
rc=0
OUT=$(HOME="$H3" bash "$SCRIPT") || rc=$?
assert_exit "listing exits 0" 0 "$rc"
assert_contains "alpha dir listed" "$OUT" "C--proj-alpha/memory"
assert_contains "beta dir listed" "$OUT" "C--proj-beta/memory"
assert_contains "alpha MEMORY.md line count" "$OUT" "MEMORY.md:3"
assert_contains "alpha topic count" "$OUT" "topics:1"
assert_contains "beta topic count" "$OUT" "topics:0"

# --- Case 4: memory dir with no MEMORY.md reports absent, still listed ---

H4="$TEST_TMPDIR/h4"
M4="$H4/.claude/projects/C--proj-gamma/memory"
mkdir -p "$M4"
printf 'loose\n' >"$M4/loose.md"
rc=0
OUT=$(HOME="$H4" bash "$SCRIPT") || rc=$?
assert_exit "no-MEMORY.md store exits 0" 0 "$rc"
assert_contains "gamma dir listed" "$OUT" "C--proj-gamma/memory"
assert_contains "gamma MEMORY.md absent" "$OUT" "MEMORY.md:absent"
assert_contains "gamma topic count" "$OUT" "topics:1"

# --- Case 5: projects root exists but holds no memory dirs -> note, exit 0 ---

H5="$TEST_TMPDIR/h5"
mkdir -p "$H5/.claude/projects/C--proj-empty"
rc=0
OUT=$(HOME="$H5" bash "$SCRIPT") || rc=$?
assert_exit "no memory dirs exits 0" 0 "$rc"
assert_contains "no memory dirs reported" "$OUT" "No per-project memory directories"

# --- Case 6: CLAUDE_CONFIG_DIR relocates the tree ---

CFG="$TEST_TMPDIR/cfg"
M6="$CFG/projects/C--proj-relocated/memory"
mkdir -p "$M6"
printf '# Index\n' >"$M6/MEMORY.md"
H6="$TEST_TMPDIR/h6"
mkdir -p "$H6"
OUT=$(HOME="$H6" CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT")
assert_contains "relocated store listed" "$OUT" "C--proj-relocated/memory"
assert_not_contains "HOME tree not scanned when relocated" "$OUT" "$H6/.claude"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
