#!/usr/bin/env bash
# Regression tests for nested-agents-check.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/nested-agents-check.sh"

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
commit_all() {
  (cd "$1" && git add -A && git commit -q -m "${2:-fixture}")
}

# --- Case 1: --help, bad argument, outside a repo ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
rc=0
bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "a bad argument exits 2" 2 "$rc"
NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
rc=0
(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT") >/dev/null 2>&1 || rc=$?
assert_eq "outside a git repo exits 1" 1 "$rc"

# --- Case 2: the mix this check exists for ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/shimmed" "$REPO/bare" "$REPO/linked" "$REPO/localonly" "$REPO/deep/a/b" "$REPO/vendor/x" "$REPO/node_modules/y"
printf 'root agents\n' >"$REPO/AGENTS.md" # root-level: not examined
printf 'shimmed\n' >"$REPO/shimmed/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/shimmed/CLAUDE.md" # wired by import
printf 'bare\n' >"$REPO/bare/AGENTS.md"          # UNWIRED
printf 'linked\n' >"$REPO/linked/AGENTS.md"
ln -s AGENTS.md "$REPO/linked/CLAUDE.md" # wired by symlink
printf 'localonly\n' >"$REPO/localonly/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/localonly/CLAUDE.local.md" # wired by a gitignored local file
printf 'CLAUDE.local.md\n' >"$REPO/.gitignore"
printf 'deep\n' >"$REPO/deep/a/b/AGENTS.md"
printf '# Notes\n\nSee @hub.md for the rest.\n' >"$REPO/deep/a/b/CLAUDE.md"
printf '@AGENTS.md\n' >"$REPO/deep/a/b/hub.md"      # wired through one hop
printf 'vendored\n' >"$REPO/vendor/x/AGENTS.md"     # skipped tree
printf 'module\n' >"$REPO/node_modules/y/AGENTS.md" # skipped tree
commit_all "$REPO"

rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_eq "report exits 0 (advisory)" 0 "$rc"
assert_contains "flags the bare nested AGENTS.md" "$OUT" "FAIL [N1]: bare/AGENTS.md"
assert_not_contains "an @AGENTS.md shim wires it" "$OUT" "shimmed/AGENTS.md"
assert_not_contains "a symlinked CLAUDE.md wires it" "$OUT" "linked/AGENTS.md"
assert_not_contains "a gitignored CLAUDE.local.md shim wires it" "$OUT" "localonly/AGENTS.md"
assert_not_contains "a one-hop import chain wires it" "$OUT" "deep/a/b/AGENTS.md"
assert_not_contains "a vendored tree is not examined" "$OUT" "vendor/x/AGENTS.md"
assert_not_contains "node_modules is not examined" "$OUT" "node_modules/y/AGENTS.md"
assert_not_contains "the root AGENTS.md is not examined" "$OUT" "FAIL [N1]: AGENTS.md"

OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 1" "1" "$OUT"
rc=0
(cd "$REPO" && bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_eq "--check exits 1 with a finding" 1 "$rc"

# --- Case 3: a sibling CLAUDE.md that does not import it is still unwired ---

printf '# Bare\n\nNo import here.\n' >"$REPO/bare/CLAUDE.md"
commit_all "$REPO" "sibling without import"
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "a sibling CLAUDE.md with no import does not wire it" "1" "$OUT"

# --- Case 4: adding the shim clears the finding ---

printf '@AGENTS.md\n' >"$REPO/bare/CLAUDE.md"
commit_all "$REPO" "add shim"
OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean repo reports none" "$OUT" "No unwired nested AGENTS.md"
rc=0
(cd "$REPO" && bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_eq "--check exits 0 when clean" 0 "$rc"

# --- Case 5: an untracked nested AGENTS.md is not examined ---

mkdir -p "$REPO/untracked"
printf 'untracked\n' >"$REPO/untracked/AGENTS.md"
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "untracked files are outside discovery" "0" "$OUT"

# --- Case 6: a repo with no nested AGENTS.md at all ---

NONE="$TEST_TMPDIR/none"
make_repo "$NONE"
printf '# Root\n' >"$NONE/CLAUDE.md"
commit_all "$NONE"
OUT=$(cd "$NONE" && bash "$SCRIPT" --count)
assert_eq "no nested AGENTS.md => 0" "0" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
