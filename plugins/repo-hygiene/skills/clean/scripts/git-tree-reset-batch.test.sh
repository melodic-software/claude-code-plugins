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

# --- 14. --repos-from - reads the list from stdin (the primary ghq-list flow) ---
out="$(printf '%s\n' "$CLEAN_REPO" | bash "$BATCH" --dry-run --repos-from - 2>&1)" || true
assert_contains "stdin list enumerates one repo" "$out" "Repos: 1"
assert_contains "stdin list repo would reset" "$out" "would-reset"

# --- 15. --skip-from FILE applies skip entries from a file ---
SKIPFILE="$TEST_TMPDIR/skips.txt"
printf '%s\n' 'acme\keepme' >"$SKIPFILE"
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --skip-from "$SKIPFILE" 2>&1)" || true
assert_contains "skip-from file skips the listed repo" "$out" "skip-list"
assert_not_contains "skip-from matched entry not reported unmatched" "$out" "UnmatchedSkip:"

# --- 16. a child reset failure (exit 5) propagates to failed count + exit 1 ---
# Intercept only `git reset` via a PATH shim (delegating every other subcommand
# to real git); the single-repo child exits 5, which the batch must surface as a
# `failed` outcome, count it, and exit non-zero.
FAIL_REPO="$(make_repo reset-fail-repo)"
REAL_GIT="$(command -v git)"
SHIM="$TEST_TMPDIR/git-shim"
mkdir -p "$SHIM"
cat >"$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "reset" ]]; then
  echo "fatal: simulated reset --hard failure" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"
rc=0
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --apply --repo "$FAIL_REPO" 2>&1)" || rc=$?
assert_exit "child reset failure makes the batch exit 1" 1 "$rc"
assert_contains "failed repo reported as failed" "$out" "failed"
assert_contains "summary counts the failure" "$out" "failed=1"

# --- 17. a child clean failure after a successful reset (exit 7) is a failure ---
# Shim only `git clean` to exit non-zero with a NON-locked-file message: the child
# reset --hard succeeds, then git clean fails for a reason other than locked files
# (UNREMOVABLE=0) → child exit 7, a partial destructive apply. The batch must treat
# it as `failed` (not `blocked`), count it, and exit non-zero — never report a
# reset-but-not-cleaned repo as a completed batch.
CLEAN_FAIL_REPO="$(make_repo clean-fail-repo)"
CLEAN_SHIM="$TEST_TMPDIR/git-clean-fail-shim"
mkdir -p "$CLEAN_SHIM"
cat >"$CLEAN_SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "clean" ]]; then
  echo "fatal: simulated clean failure (non-locked cause)" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$CLEAN_SHIM/git"
rc=0
out="$(PATH="$CLEAN_SHIM:$PATH" bash "$BATCH" --apply --repo "$CLEAN_FAIL_REPO" 2>&1)" || rc=$?
assert_exit "child clean failure (exit 7) makes the batch exit 1" 1 "$rc"
assert_contains "exit-7 repo reported as failed" "$out" "failed"
assert_contains "exit-7 reason names the partial apply" "$out" "clean failed after a successful reset"
assert_contains "summary counts the exit-7 failure" "$out" "failed=1"

# --- 18. an incomplete clean (child Unremovable>0, exit 0) is surfaced, not hidden ---
# Shim `git clean` to print a 'failed to remove' warning and exit non-zero: the
# child counts it as UNREMOVABLE=1 and, by design, still exits 0 (locked/in-use
# files are non-fatal). The batch must keep the repo in the reset (success) bucket
# yet name the incomplete clean in the per-repo Reason so an operator never reads
# it as a fully realigned tree.
UNREMOVABLE_REPO="$(make_repo unremovable-repo)"
UNREMOVABLE_SHIM="$TEST_TMPDIR/git-unremovable-shim"
mkdir -p "$UNREMOVABLE_SHIM"
cat >"$UNREMOVABLE_SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "clean" ]]; then
  echo "warning: failed to remove obj/locked.bin: Device or resource busy" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$UNREMOVABLE_SHIM/git"
rc=0
out="$(PATH="$UNREMOVABLE_SHIM:$PATH" bash "$BATCH" --apply --repo "$UNREMOVABLE_REPO" 2>&1)" || rc=$?
assert_exit "incomplete clean still exits 0 (locked files are non-fatal)" 0 "$rc"
assert_contains "incomplete-clean repo still reported done" "$out" "done"
assert_contains "incomplete clean named in the reason" "$out" "incomplete clean: 1 path(s) unremovable"
assert_contains "incomplete clean stays in the reset bucket" "$out" "reset=1"
assert_contains "incomplete clean is not a failure" "$out" "failed=0"

# --- 19. --include-dirty dry-run names the dirty repos it will discard ---
# The skill's batch confirmation must name the repos whose uncommitted/untracked
# edits --include-dirty discards. With the dirty guard bypassed, a plain dry-run
# would emit would-reset/none; the batch must instead read the child's TrackedDirty
# and name the count so the confirmation gate has the information it requires.
DIRTY_DRY_REPO="$(make_repo dirty-dry-repo)"
echo local-edit >>"$DIRTY_DRY_REPO/tracked.txt"
out="$(bash "$BATCH" --dry-run --include-dirty --repo "$DIRTY_DRY_REPO" 2>&1)" || true
assert_contains "include-dirty dry-run still plans the reset" "$out" "would-reset"
assert_contains "include-dirty dry-run names the discarded dirty edits" "$out" "uncommitted/untracked change(s) would be discarded"

# --- 20. --include-dirty dry-run names discarded UNPUSHED commits on a clean tree ---
# A repo with a clean working tree but unpushed commits (ahead of upstream) is
# skipped by the dirty guard by default; under --include-dirty it resets away those
# commits. TrackedDirty is 0, so only the child's AheadCount reveals the loss — the
# confirmation must name it, mirroring the tracked-edit case in test 19.
AHEAD_REPO="$(make_repo ahead-repo)"
echo committed-ahead >>"$AHEAD_REPO/tracked.txt"
git -C "$AHEAD_REPO" commit -aqm "unpushed commit ahead of upstream"
out="$(bash "$BATCH" --dry-run --include-dirty --repo "$AHEAD_REPO" 2>&1)" || true
assert_contains "include-dirty dry-run still plans the ahead repo reset" "$out" "would-reset"
assert_contains "include-dirty dry-run names the discarded unpushed commits" "$out" "1 unpushed commit(s) would be discarded"

# --- 21. read_lines_into keeps a FINAL line with no trailing newline (data-loss guard) ---
# A skip file written without a trailing newline (printf '%s', not '%s\n') must still
# protect its repo. The dropped-final-line bug silently empties a single-entry skip list,
# fires no UnmatchedSkip warning (the entry never enters the array), and resets the repo
# the operator meant to spare — the exact data-loss shape this feature exists to close.
NOEOL_SKIP="$TEST_TMPDIR/skips-noeol.txt"
printf '%s' 'acme\keepme' >"$NOEOL_SKIP" # deliberately no trailing newline
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --skip-from "$NOEOL_SKIP" 2>&1)" || true
assert_contains "unterminated skip entry still skips its repo" "$out" "skip-list"
assert_not_contains "unterminated matched skip not reported unmatched" "$out" "UnmatchedSkip:"
# A typo'd unterminated entry must still surface as UnmatchedSkip (guard stays active).
NOEOL_TYPO="$TEST_TMPDIR/skips-noeol-typo.txt"
printf '%s' 'no/such-repo' >"$NOEOL_TYPO" # no trailing newline
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --skip-from "$NOEOL_TYPO" 2>&1)" || true
assert_contains "unterminated typo skip surfaced as UnmatchedSkip" "$out" "UnmatchedSkip: no/such-repo"

# --- 22. --repos-from keeps a final unterminated line too (same shared helper) ---
NOEOL_REPOS="$TEST_TMPDIR/repos-noeol.txt"
printf '%s' "$CLEAN_REPO" >"$NOEOL_REPOS" # single repo path, no trailing newline
out="$(bash "$BATCH" --dry-run --repos-from "$NOEOL_REPOS" 2>&1)" || true
assert_contains "unterminated repos-from still enumerates the repo" "$out" "Repos: 1"
assert_contains "unterminated repos-from repo would reset" "$out" "would-reset"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-tree-reset-batch.sh tests passed"
