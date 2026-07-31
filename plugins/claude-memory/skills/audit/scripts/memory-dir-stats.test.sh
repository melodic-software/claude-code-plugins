#!/usr/bin/env bash
# Regression tests for memory-dir-stats.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/memory-dir-stats.sh"

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

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

slug_of() {
  local root
  root=$(cd "$1" && (cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" 2>/dev/null ||
    git rev-parse --show-toplevel 2>/dev/null | tr -d '\r'))
  printf '%s' "$root" | sed 's/[:\\/.]/-/g'
}

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
SLUG=$(slug_of "$REPO")

# mem_dir_for <home> — create + echo the memory dir the resolver will pick for that HOME.
mem_dir_for() {
  local dir="$1/.claude/projects/$SLUG/memory"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# CLAUDE_CONFIG_DIR is unset per-run: the resolver honors it over $HOME, so leaving an
# ambient value in place would let the host machine's real config answer for the fixture.
run() { (cd "$REPO" && env -u CLAUDE_CONFIG_DIR HOME="$1" bash "$SCRIPT" "$2"); }

# --- Case 1: --help ---
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: bad flag and missing mode -> usage on stderr, exit 2, empty stdout ---
rc=0
OUT=$(bash "$SCRIPT" --bogus 2>"$TEST_TMPDIR/err") || rc=$?
assert_exit "bad flag exits 2" 2 "$rc"
assert_eq "bad flag prints nothing on stdout" "" "$OUT"
assert_contains "bad flag prints usage on stderr" "$(cat "$TEST_TMPDIR/err")" "Usage:"
rc=0
OUT=$(bash "$SCRIPT" 2>/dev/null) || rc=$?
assert_exit "missing mode exits 2" 2 "$rc"
assert_eq "missing mode prints nothing on stdout" "" "$OUT"

# --- Case 3: --md-count with N md files (MEMORY.md included, as the old inline `ls *.md` counted it) ---
H3="$TEST_TMPDIR/h3"
M3=$(mem_dir_for "$H3")
printf '# Index\n' >"$M3/MEMORY.md"
printf 'a\n' >"$M3/a.md"
printf 'b\n' >"$M3/b.md"
printf 'not markdown\n' >"$M3/notes.txt"
rc=0
OUT=$(run "$H3" --md-count) || rc=$?
assert_exit "--md-count exits 0" 0 "$rc"
assert_eq "--md-count counts every *.md (MEMORY.md + 2 topics)" "3" "$OUT"

# --- Case 4: --memory-lines with MEMORY.md present ---
printf 'one\ntwo\nthree\n' >"$M3/MEMORY.md"
rc=0
OUT=$(run "$H3" --memory-lines) || rc=$?
assert_exit "--memory-lines exits 0" 0 "$rc"
assert_eq "--memory-lines counts MEMORY.md lines" "3" "$OUT"

# --- Case 5: fresh project — no memory dir at all: both modes report 0, exit 0 ---
H5="$TEST_TMPDIR/h5"
mkdir -p "$H5"
rc=0
OUT=$(run "$H5" --md-count) || rc=$?
assert_exit "absent memory dir --md-count exits 0" 0 "$rc"
assert_eq "absent memory dir --md-count == 0" "0" "$OUT"
rc=0
OUT=$(run "$H5" --memory-lines) || rc=$?
assert_exit "absent MEMORY.md exits 0" 0 "$rc"
assert_eq "absent MEMORY.md --memory-lines == 0" "0" "$OUT"

# --- Case 6: memory dir exists but is empty (no MEMORY.md) ---
H6="$TEST_TMPDIR/h6"
mem_dir_for "$H6" >/dev/null
assert_eq "empty memory dir --md-count == 0" "0" "$(run "$H6" --md-count)"
assert_eq "empty memory dir --memory-lines == 0" "0" "$(run "$H6" --memory-lines)"

# --- Case 7: output contract — a single bare integer, nothing else, for every stat mode ---
for m in --md-count --memory-lines; do
  OUT=$(run "$H3" "$m")
  if [[ "$OUT" =~ ^[0-9]+$ ]]; then
    pass "$m emits exactly one bare integer"
  else
    fail "$m emits exactly one bare integer" "got: [$OUT]"
  fi
done

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
