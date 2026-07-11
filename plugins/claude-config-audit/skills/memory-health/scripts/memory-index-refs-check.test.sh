#!/usr/bin/env bash
# Regression tests for memory-index-refs-check.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/memory-index-refs-check.sh"

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

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

slug_of() {
  local root
  root=$(cd "$1" && (cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" 2>/dev/null \
    || git rev-parse --show-toplevel 2>/dev/null | tr -d '\r'))
  printf '%s' "$root" | sed 's/[:\\/.]/-/g'
}

# A fixture repo; the script resolves the memory dir via its sibling resolver, which
# derives the dir from the cwd repo root + HOME. Each case gets its own HOME.
REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
SLUG=$(slug_of "$REPO")

# mem_dir_for <home> — create + echo the memory dir the resolver will pick for that HOME.
mem_dir_for() {
  local dir="$1/.claude/projects/$SLUG/memory"
  mkdir -p "$dir"
  printf '%s' "$dir"
}
run() { (cd "$REPO" && HOME="$1" bash "$SCRIPT" "${2:-}"); }

# --- Case 1: --help ---
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: clean index (all links resolve, no orphans) ---
H2="$TEST_TMPDIR/h2"
M2=$(mem_dir_for "$H2")
printf '# Index\n- [a.md](a.md)\n- [b.md](b.md)\n' >"$M2/MEMORY.md"
printf 'a\n' >"$M2/a.md"
printf 'b\n' >"$M2/b.md"
OUT=$(run "$H2")
assert_contains "clean index reports OK" "$OUT" "integrity OK"
assert_eq "clean count == 0" "0" "$(run "$H2" --count)"

# --- Case 3: missing target (index links absent file) ---
H3="$TEST_TMPDIR/h3"
M3=$(mem_dir_for "$H3")
printf '# Index\n- [a.md](a.md)\n- [gone.md](gone.md)\n' >"$M3/MEMORY.md"
printf 'a\n' >"$M3/a.md"
OUT=$(run "$H3")
assert_contains "flags M2-missing" "$OUT" "M2-missing"
assert_contains "names the missing file" "$OUT" "gone.md"

# --- Case 4: orphan topic file (present, not indexed) ---
H4="$TEST_TMPDIR/h4"
M4=$(mem_dir_for "$H4")
printf '# Index\n- [a.md](a.md)\n' >"$M4/MEMORY.md"
printf 'a\n' >"$M4/a.md"
printf 'orphan\n' >"$M4/loose.md"
OUT=$(run "$H4")
assert_contains "flags M2-orphan" "$OUT" "M2-orphan"
assert_contains "names the orphan file" "$OUT" "loose.md"
assert_eq "orphan count == 1" "1" "$(run "$H4" --count)"

# --- Case 5: orphan opt-out marker suppresses ---
H5="$TEST_TMPDIR/h5"
M5DIR=$(mem_dir_for "$H5")
printf '# Index\n- [a.md](a.md)\n' >"$M5DIR/MEMORY.md"
printf 'a\n' >"$M5DIR/a.md"
printf 'staging\n<!-- memory-index-orphan-ignore -->\n' >"$M5DIR/staging.md"
OUT=$(run "$H5")
assert_not_contains "opt-out orphan not flagged" "$OUT" "staging.md"
assert_eq "opt-out count == 0" "0" "$(run "$H5" --count)"

# --- Case 6: no MEMORY.md (fresh) ---
H6="$TEST_TMPDIR/h6"
mem_dir_for "$H6" >/dev/null
rc=0
OUT=$(run "$H6") || rc=$?
assert_exit "fresh exits 0" 0 "$rc"
assert_contains "fresh reports no MEMORY.md" "$OUT" "No MEMORY.md"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
