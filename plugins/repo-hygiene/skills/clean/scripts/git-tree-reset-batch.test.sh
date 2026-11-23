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

rc=0
bash "$BATCH" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

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
if clean_skip_matches "$REPO_KEY" '/fleet/acme/keepme'; then
  pass "absolute-path skip matches exact toplevel"
else
  fail "absolute-path skip matches exact toplevel" "match" "no-match"
fi

if clean_skip_matches "$REPO_KEY" 'eepme'; then
  fail "partial trailing segment must NOT match" "no-match" "match"
else
  pass "partial trailing segment 'eepme' does not match 'keepme'"
fi
OTHER_KEY="$(clean_path_key '/fleet/acme/other-keepme')"
if clean_skip_matches "$OTHER_KEY" 'keepme'; then
  fail "sibling 'other-keepme' must NOT be skipped by 'keepme'" "no-match" "match"
else
  pass "sibling 'other-keepme' is not matched by bare 'keepme'"
fi
if clean_skip_matches "$REPO_KEY" 'other/keepme'; then
  fail "wrong owner path must NOT match" "no-match" "match"
else
  pass "wrong-owner 'other/keepme' does not match"
fi

if [[ "$is_windows" == "true" ]]; then
  if clean_skip_matches "$(clean_path_key '<drive>:/Repos/Acme/KeepMe')" 'acme\keepme'; then
    pass "Windows: skip match is case-insensitive"
  else
    fail "Windows: skip match is case-insensitive" "match" "no-match"
  fi
else
  skip_case "case-fold assertion is Windows-only"
fi

mk_git_shim() {
  mkdir -p "$1"
  cat >"$1/git"
  chmod +x "$1/git"
}

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
  git -C "$dir" checkout -b feat/x >/dev/null 2>&1
  git -C "$dir" config branch.feat/x.remote .
  git -C "$dir" config branch.feat/x.merge refs/heads/main
  printf '%s' "$dir"
}

CLEAN_REPO="$(make_repo clean-repo)"
SKIP_REPO="$(make_repo keepme)"
DIRTY_REPO="$(make_repo dirty-repo)"
echo local-edit >>"$DIRTY_REPO/tracked.txt"

out="$(bash "$BATCH" --dry-run \
  --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --repo "$DIRTY_REPO" \
  --skip 'acme\keepme' 2>&1)" || true
assert_contains "dry-run reports mode" "$out" "Mode: dry-run"
assert_contains "clean repo would reset" "$out" "would-reset"
assert_contains "skip-listed repo is skipped" "$out" "skip-list"
assert_contains "dirty repo skipped by default" "$out" "dirty (uncommitted or untracked changes)"
assert_not_contains "matched backslash skip is not reported unmatched" "$out" "UnmatchedSkip: acme\\keepme"

out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --skip 'no/such-repo' 2>&1)" || true
assert_contains "unmatched skip entry surfaced" "$out" "UnmatchedSkip: no/such-repo"

rc=0
out="$(bash "$BATCH" --apply --repo "$DIRTY_REPO" 2>&1)" || rc=$?
assert_exit "apply over a skipped-only batch exits 0" 0 "$rc"
assert_contains "dirty repo skipped on apply" "$out" "skipped"
if grep -q "local-edit" "$DIRTY_REPO/tracked.txt"; then
  pass "dirty repo's uncommitted edit PRESERVED (default skip prevents data loss)"
else
  fail "dirty repo's uncommitted edit preserved" "present" "lost"
fi

rc=0
out="$(bash "$BATCH" --apply --include-dirty --repo "$DIRTY_REPO" 2>&1)" || rc=$?
assert_exit "apply --include-dirty exits 0" 0 "$rc"
assert_contains "include-dirty resets the dirty repo" "$out" "done"
if grep -q "local-edit" "$DIRTY_REPO/tracked.txt"; then
  fail "include-dirty discards the uncommitted edit" "discarded" "still-present"
else
  pass "include-dirty reset discarded the uncommitted edit (opt-in honored)"
fi

echo scratch >"$CLEAN_REPO/scratch.txt"
rc=0
out="$(bash "$BATCH" --apply --repo "$CLEAN_REPO" --include-dirty 2>&1)" || rc=$?
assert_exit "clean-repo apply exits 0" 0 "$rc"
assert_contains "clean repo reports done" "$out" "done"
assert_file_absent "apply removed the untracked scratch file" "$CLEAN_REPO/scratch.txt"

DEFAULT_REPO="$(make_repo default-branch-repo)"
git -C "$DEFAULT_REPO" checkout main >/dev/null 2>&1
git -C "$DEFAULT_REPO" config branch.main.remote .
git -C "$DEFAULT_REPO" config branch.main.merge refs/heads/main
out="$(bash "$BATCH" --dry-run --repo "$DEFAULT_REPO" 2>&1)" || true
assert_contains "default-branch repo blocked" "$out" "default-branch (pass --force-default-branch)"
assert_contains "summary counts the block" "$out" "blocked=1"

LIST="$TEST_TMPDIR/repos.txt"
printf '%s\n%s\n' "$CLEAN_REPO" "$SKIP_REPO" >"$LIST"
out="$(bash "$BATCH" --dry-run --repos-from "$LIST" --skip 'keepme' 2>&1)" || true
assert_contains "repos-from enumerates the listed repos" "$out" "Repos: 2"
assert_contains "repos-from honors the skip list" "$out" "skip-list"

mkdir -p "$TEST_TMPDIR/not-a-repo"
out="$(bash "$BATCH" --dry-run --repo "$TEST_TMPDIR/not-a-repo" 2>&1)" || true
assert_contains "non-git input reported blocked" "$out" "not-a-git-repo"

out="$(printf '%s\n' "$CLEAN_REPO" | bash "$BATCH" --dry-run --repos-from - 2>&1)" || true
assert_contains "stdin list enumerates one repo" "$out" "Repos: 1"
assert_contains "stdin list repo would reset" "$out" "would-reset"

SKIPFILE="$TEST_TMPDIR/skips.txt"
printf '%s\n' 'acme\keepme' >"$SKIPFILE"
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --skip-from "$SKIPFILE" 2>&1)" || true
assert_contains "skip-from file skips the listed repo" "$out" "skip-list"
assert_not_contains "skip-from matched entry not reported unmatched" "$out" "UnmatchedSkip:"

FAIL_REPO="$(make_repo reset-fail-repo)"
REAL_GIT="$(command -v git)"
SHIM="$TEST_TMPDIR/git-shim"
mk_git_shim "$SHIM" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "reset" ]]; then
  echo "fatal: simulated reset --hard failure" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
rc=0
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --apply --repo "$FAIL_REPO" 2>&1)" || rc=$?
assert_exit "child reset failure makes the batch exit 1" 1 "$rc"
assert_contains "failed repo reported as failed" "$out" "failed"
assert_contains "summary counts the failure" "$out" "failed=1"

CLEAN_FAIL_REPO="$(make_repo clean-fail-repo)"
CLEAN_SHIM="$TEST_TMPDIR/git-clean-fail-shim"
mk_git_shim "$CLEAN_SHIM" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "clean" ]]; then
  echo "fatal: simulated clean failure (non-locked cause)" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
rc=0
out="$(PATH="$CLEAN_SHIM:$PATH" bash "$BATCH" --apply --repo "$CLEAN_FAIL_REPO" 2>&1)" || rc=$?
assert_exit "child clean failure (exit 7) makes the batch exit 1" 1 "$rc"
assert_contains "exit-7 repo reported as failed" "$out" "failed"
assert_contains "exit-7 reason names the partial apply" "$out" "clean failed after a successful reset"
assert_contains "summary counts the exit-7 failure" "$out" "failed=1"

UNREMOVABLE_REPO="$(make_repo unremovable-repo)"
UNREMOVABLE_SHIM="$TEST_TMPDIR/git-unremovable-shim"
mk_git_shim "$UNREMOVABLE_SHIM" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "clean" ]]; then
  echo "warning: failed to remove obj/locked.bin: Device or resource busy" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
rc=0
out="$(PATH="$UNREMOVABLE_SHIM:$PATH" bash "$BATCH" --apply --repo "$UNREMOVABLE_REPO" 2>&1)" || rc=$?
assert_exit "incomplete clean still exits 0 (locked files are non-fatal)" 0 "$rc"
assert_contains "incomplete-clean repo still reported done" "$out" "done"
assert_contains "incomplete clean named in the reason" "$out" "incomplete clean: 1 path(s) unremovable"
assert_contains "incomplete clean stays in the reset bucket" "$out" "reset=1"
assert_contains "incomplete clean is not a failure" "$out" "failed=0"

DIRTY_DRY_REPO="$(make_repo dirty-dry-repo)"
echo local-edit >>"$DIRTY_DRY_REPO/tracked.txt"
out="$(bash "$BATCH" --dry-run --include-dirty --repo "$DIRTY_DRY_REPO" 2>&1)" || true
assert_contains "include-dirty dry-run still plans the reset" "$out" "would-reset"
assert_contains "include-dirty dry-run names the discarded dirty edits" "$out" "uncommitted/untracked change(s) would be discarded"

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
printf '%s' 'acme\keepme' >"$NOEOL_SKIP"
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --skip-from "$NOEOL_SKIP" 2>&1)" || true
assert_contains "unterminated skip entry still skips its repo" "$out" "skip-list"
assert_not_contains "unterminated matched skip not reported unmatched" "$out" "UnmatchedSkip:"
NOEOL_TYPO="$TEST_TMPDIR/skips-noeol-typo.txt"
printf '%s' 'no/such-repo' >"$NOEOL_TYPO"
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --skip-from "$NOEOL_TYPO" 2>&1)" || true
assert_contains "unterminated typo skip surfaced as UnmatchedSkip" "$out" "UnmatchedSkip: no/such-repo"

NOEOL_REPOS="$TEST_TMPDIR/repos-noeol.txt"
printf '%s' "$CLEAN_REPO" >"$NOEOL_REPOS"
out="$(bash "$BATCH" --dry-run --repos-from "$NOEOL_REPOS" 2>&1)" || true
assert_contains "unterminated repos-from still enumerates the repo" "$out" "Repos: 1"
assert_contains "unterminated repos-from repo would reset" "$out" "would-reset"

# --- 22b. source-open contract (#3482): trailing blank / empty / CR / missing ---
# A file ending `path\n\n` is ordinary EOF success. The sibling clean-batch used
# to map that helper rc 1 onto "file not found"; tree-batch must keep accepting
# it after dropping its duplicate `-f` precheck, and a truly missing file must
# still error as file-not-found.
TRAIL_REPOS="$TEST_TMPDIR/repos-trail.txt"
printf '%s\n\n' "$CLEAN_REPO" >"$TRAIL_REPOS"
rc=0
out="$(bash "$BATCH" --dry-run --repos-from "$TRAIL_REPOS" 2>&1)" || rc=$?
assert_exit "trailing-blank --repos-from is accepted (exit 0)" 0 "$rc"
assert_not_contains "trailing blank is not reported as file-not-found" "$out" "file not found"
assert_contains "trailing-blank list enumerates the repo" "$out" "Repos: 1"

: >"$TEST_TMPDIR/repos-empty.txt"
rc=0
out="$(bash "$BATCH" --dry-run --repos-from "$TEST_TMPDIR/repos-empty.txt" 2>&1)" || rc=$?
assert_exit "empty --repos-from is a usage error (exit 2)" 2 "$rc"
assert_not_contains "empty file is not reported missing" "$out" "file not found"
assert_contains "empty file reaches no-repos usage" "$out" "no repos given"

printf '%s\r\n' "$CLEAN_REPO" >"$TEST_TMPDIR/repos-cr.txt"
rc=0
out="$(bash "$BATCH" --dry-run --repos-from "$TEST_TMPDIR/repos-cr.txt" 2>&1)" || rc=$?
assert_exit "CR-terminated --repos-from is accepted (exit 0)" 0 "$rc"
assert_contains "CR-stripped list enumerates the repo" "$out" "Repos: 1"

rc=0
out="$(bash "$BATCH" --dry-run --repos-from "$TEST_TMPDIR/no-such-repos.txt" 2>&1)" || rc=$?
assert_exit "missing --repos-from exits 2" 2 "$rc"
assert_contains "missing file reported not found" "$out" "file not found:"

TRAIL_SKIP="$TEST_TMPDIR/skips-trail.txt"
printf 'keepme\n\n' >"$TRAIL_SKIP"
rc=0
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --repo "$SKIP_REPO" --skip-from "$TRAIL_SKIP" 2>&1)" || rc=$?
assert_exit "trailing-blank --skip-from is accepted (exit 0)" 0 "$rc"
assert_not_contains "trailing-blank skip-from is not file-not-found" "$out" "file not found"
assert_contains "trailing-blank skip-from still skips" "$out" "skip-list"

rc=0
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" --skip-from "$TEST_TMPDIR/no-such-skips.txt" 2>&1)" || rc=$?
assert_exit "missing --skip-from exits 2" 2 "$rc"
assert_contains "missing skip-from reported not found" "$out" "file not found:"

UNREAD_LIST="$TEST_TMPDIR/unreadable-repos.txt"
printf '%s\n' "$CLEAN_REPO" >"$UNREAD_LIST"
chmod 000 "$UNREAD_LIST" 2>/dev/null || true
if [[ -r "$UNREAD_LIST" ]]; then
  skip_case "unopenable --repos-from: chmod 000 not enforced on this filesystem (CAP_DAC_OVERRIDE)"
else
  rc=0
  out="$(bash "$BATCH" --dry-run --repos-from "$UNREAD_LIST" 2>&1)" || rc=$?
  assert_exit "unopenable --repos-from exits 2" 2 "$rc"
  assert_contains "unopenable file reported not found" "$out" "file not found:"
fi
chmod 644 "$UNREAD_LIST" 2>/dev/null || true

# --- 23. a single --repo consumes consecutive paths (shell-glob-after-expansion) ---
# `--repo ~/repos/*` reaches the script as ONE --repo flag followed by N positional
# paths (the shell expanded the glob before exec). A single --repo must ingest every
# one of them, which the pre-fix single-arg arm could not: it took the first path and
# the second hit the unknown-arg default (exit 2). Simulate the expanded glob with two
# explicit consecutive paths after one --repo.
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" "$SKIP_REPO" 2>&1)" || true
assert_contains "single --repo ingests both consecutive glob paths" "$out" "Repos: 2"

out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" "$SKIP_REPO" --skip 'keepme' 2>&1)" || true
assert_contains "greedy --repo still enumerates both paths" "$out" "Repos: 2"
assert_contains "greedy --repo stops at --skip (parsed as a flag, not a path)" "$out" "skip-list"
assert_not_contains "--skip value 'keepme' was not swallowed as a repo path" "$out" "UnmatchedSkip: keepme"

# --- 25. empty CHILD_PASS / first-seen REPO_KEYS under set -u must not abort ---
# Default dry-run passes no --force-default-branch/--include-deps/--include-secrets/
# --include-dirty, so CHILD_PASS stays (). key_seen also walks REPO_KEYS while it
# is still empty on the first input. Bare "${arr[@]}" aborts on bash 4.0-4.3.
out="$(bash "$BATCH" --dry-run --repo "$CLEAN_REPO" 2>&1)" || true
assert_not_contains "empty CHILD_PASS and REPO_KEYS do not unbound-variable abort" "$out" "unbound variable"
assert_contains "empty-pass-through dry-run still classifies the repo" "$out" "would-reset"

# --- 26. --repo with no path (immediately at a flag or end of args) is a usage error ---
# A bare --repo followed by another flag has no path to consume; it must fail loud
# (exit 2), not silently absorb the following flag as a directory path (the pre-fix
# single-arg arm did the latter, classifying e.g. `--skip` as a blocked non-directory).
rc=0
bash "$BATCH" --dry-run --repo --skip 'x' >/dev/null 2>&1 || rc=$?
assert_exit "--repo immediately followed by a flag exits 2" 2 "$rc"
rc=0
bash "$BATCH" --dry-run --repo >/dev/null 2>&1 || rc=$?
assert_exit "trailing --repo with no path exits 2" 2 "$rc"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-tree-reset-batch.sh tests passed"
