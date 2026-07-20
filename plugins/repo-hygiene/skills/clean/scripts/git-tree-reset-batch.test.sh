#!/usr/bin/env bash
# Tests for git-tree-reset-batch.sh and the separator-agnostic skip matcher.
#
# The headline cases reproduce the data-loss incident this feature closes:
#   - clean_skip_matches as a PURE STRING FUNCTION: a skip entry written with
#     Windows backslashes must match a forward-slash repo key (the exact bug).
#     This is deterministic on the Linux CI runner, where a backslash is a legal
#     filename byte, not a separator — the only way to prove the fix reliably.
#   - integration: a skip-listed repo is skipped; a dirty repo is skipped by
#     default and reset only with --include-dirty; an unmatched skip is surfaced.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

BATCH="$SCRIPT_DIR/git-tree-reset-batch.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

is_windows=false
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*) is_windows=true ;;
*) ;;
esac

# --- 1. --help ---
rc=0
bash "$BATCH" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# --- 2. no repos is a usage error (exit 2) ---
rc=0
bash "$BATCH" >/dev/null 2>&1 || rc=$?
assert_exit "no repos exits 2" 2 "$rc"

# --- 3. clean_skip_matches: the exact mixed-separator bug, as a pure function ---
# repo_key is what enumeration produces: a rev-parse toplevel (forward slashes)
# run through clean_path_key. On Linux that leaves case intact.
REPO_KEY="$(clean_path_key '/fleet/acme/keepme')"

# A skip entry written with Windows backslashes (the incident's failing case).
if clean_skip_matches "$REPO_KEY" 'acme\keepme'; then
  pass "backslash skip entry matches forward-slash repo key (the incident bug, now fixed)"
else
  fail "backslash skip entry matches forward-slash repo key" "match" "no-match"
fi

# Forward-slash short form and bare repo name also match.
if clean_skip_matches "$REPO_KEY" 'acme/keepme'; then
  pass "forward-slash owner/repo skip matches"
else
  fail "forward-slash owner/repo skip matches" "match" "no-match"
fi
if clean_skip_matches "$REPO_KEY" 'keepme'; then
  pass "bare repo-name skip matches on segment boundary"
else
  fail "bare repo-name skip matches" "match" "no-match"
fi
# Full absolute path with backslashes matches the forward-slash toplevel.
if clean_skip_matches "$REPO_KEY" '/fleet/acme/keepme'; then
  pass "absolute-path skip matches exact toplevel"
else
  fail "absolute-path skip matches exact toplevel" "match" "no-match"
fi

# --- 4. clean_skip_matches: no over-matching (segment boundary anchored) ---
if clean_skip_matches "$REPO_KEY" 'eepme'; then
  fail "partial trailing segment must NOT match" "no-match" "match"
else
  pass "partial trailing segment 'eepme' does not match 'keepme'"
fi
# A sibling repo sharing a suffix name must not be caught.
OTHER_KEY="$(clean_path_key '/fleet/acme/other-keepme')"
if clean_skip_matches "$OTHER_KEY" 'keepme'; then
  fail "sibling 'other-keepme' must NOT be skipped by 'keepme'" "no-match" "match"
else
  pass "sibling 'other-keepme' is not matched by bare 'keepme'"
fi
# Wrong owner path does not match.
if clean_skip_matches "$REPO_KEY" 'other/keepme'; then
  fail "wrong owner path must NOT match" "no-match" "match"
else
  pass "wrong-owner 'other/keepme' does not match"
fi

# --- 5. clean_path_key: case folding only on Windows ---
if [[ "$is_windows" == "true" ]]; then
  if clean_skip_matches "$(clean_path_key 'C:/Repos/Acme/KeepMe')" 'acme\keepme'; then
    pass "Windows: skip match is case-insensitive"
  else
    fail "Windows: skip match is case-insensitive" "match" "no-match"
  fi
else
  skip_case "case-fold assertion is Windows-only"
fi

# --- Integration fixtures ---
# make_repo <name> — a repo under an owner dir (acme/<name>) on a feature branch
# whose upstream is local main. Nesting under an owner segment lets the skip-list
# integration test exercise a mixed-separator owner/repo entry (acme\<name>). The
# local upstream (branch.remote=".") means no shared-remote push contention.
make_repo() {
  local name="$1"
  local dir="$TEST_TMPDIR/acme/$name"
  git init "$dir" >/dev/null 2>&1
  git -C "$dir" config user.email "t@example.com"
  git -C "$dir" config user.name "Test"
  echo tracked >"$dir/tracked.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -m init >/dev/null
  git -C "$dir" branch -M main
  # Feature branch tracking local main so the default-branch guard does not block
  # the reset (isolates the batch-layer behavior under test).
  git -C "$dir" checkout -b feat/x >/dev/null 2>&1
  git -C "$dir" config branch.feat/x.remote .
  git -C "$dir" config branch.feat/x.merge refs/heads/main
  printf '%s' "$dir"
}

CLEAN_REPO="$(make_repo clean-repo)"
SKIP_REPO="$(make_repo keepme)"
DIRTY_REPO="$(make_repo dirty-repo)"
# Give the dirty repo an uncommitted tracked edit — the incident's exact shape.
echo local-edit >>"$DIRTY_REPO/tracked.txt"

# --- 6. dry-run: skip-listed repo skipped, clean+dirty classified ---
out="$(bash "$BATCH" --dry-run \
  --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --repo "$DIRTY_REPO" \
  --skip 'acme\keepme' 2>&1)" || true
assert_contains "dry-run reports mode" "$out" "Mode: dry-run"
assert_contains "clean repo would reset" "$out" "would-reset"
assert_contains "skip-listed repo is skipped" "$out" "skip-list"
assert_contains "dirty repo skipped by default" "$out" "dirty (uncommitted or untracked changes)"
# keepme was skipped via a backslash short form → it must NOT be reported unmatched.
assert_not_contains "matched backslash skip is not reported unmatched" "$out" "UnmatchedSkip: acme\\keepme"

# --- 7. unmatched skip entry is surfaced (no silent skip failure) ---
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --skip 'no/such-repo' 2>&1)" || true
assert_contains "unmatched skip entry surfaced" "$out" "UnmatchedSkip: no/such-repo"

# --- 8. apply: dirty repo skipped by default preserves its uncommitted edit ---
rc=0
out="$(bash "$BATCH" --apply --repo "$DIRTY_REPO" 2>&1)" || rc=$?
assert_exit "apply over a skipped-only batch exits 0" 0 "$rc"
assert_contains "dirty repo skipped on apply" "$out" "skipped"
if grep -q "local-edit" "$DIRTY_REPO/tracked.txt"; then
  pass "dirty repo's uncommitted edit PRESERVED (default skip prevents data loss)"
else
  fail "dirty repo's uncommitted edit preserved" "present" "lost"
fi

# --- 9. apply --include-dirty: dirty repo IS reset, edit discarded ---
rc=0
out="$(bash "$BATCH" --apply --include-dirty --repo "$DIRTY_REPO" 2>&1)" || rc=$?
assert_exit "apply --include-dirty exits 0" 0 "$rc"
assert_contains "include-dirty resets the dirty repo" "$out" "done"
if grep -q "local-edit" "$DIRTY_REPO/tracked.txt"; then
  fail "include-dirty discards the uncommitted edit" "discarded" "still-present"
else
  pass "include-dirty reset discarded the uncommitted edit (opt-in honored)"
fi

# --- 10. clean repo actually resets an untracked file away on apply ---
echo scratch >"$CLEAN_REPO/scratch.txt"
rc=0
out="$(bash "$BATCH" --apply --repo "$CLEAN_REPO" --include-dirty 2>&1)" || rc=$?
assert_exit "clean-repo apply exits 0" 0 "$rc"
assert_contains "clean repo reports done" "$out" "done"
assert_file_absent "apply removed the untracked scratch file" "$CLEAN_REPO/scratch.txt"

# --- 11. default-branch repo is blocked without --force-default-branch ---
DEFAULT_REPO="$(make_repo default-branch-repo)"
git -C "$DEFAULT_REPO" checkout main >/dev/null 2>&1
git -C "$DEFAULT_REPO" config branch.main.remote .
git -C "$DEFAULT_REPO" config branch.main.merge refs/heads/main
out="$(bash "$BATCH" --dry-run --repo "$DEFAULT_REPO" 2>&1)" || true
assert_contains "default-branch repo blocked" "$out" "default-branch (pass --force-default-branch)"
assert_contains "summary counts the block" "$out" "blocked=1"

# --- 12. --repos-from ingests a newline-delimited list (ghq list shape) ---
LIST="$TEST_TMPDIR/repos.txt"
printf '%s\n%s\n' "$CLEAN_REPO" "$SKIP_REPO" >"$LIST"
out="$(bash "$BATCH" --dry-run --repos-from "$LIST" --skip 'keepme' 2>&1)" || true
assert_contains "repos-from enumerates the listed repos" "$out" "Repos: 2"
assert_contains "repos-from honors the skip list" "$out" "skip-list"

# --- 13. non-git input reported as blocked, not silently dropped ---
mkdir -p "$TEST_TMPDIR/not-a-repo"
out="$(bash "$BATCH" --dry-run --repo "$TEST_TMPDIR/not-a-repo" 2>&1)" || true
assert_contains "non-git input reported blocked" "$out" "not-a-git-repo"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-tree-reset-batch.sh tests passed"
