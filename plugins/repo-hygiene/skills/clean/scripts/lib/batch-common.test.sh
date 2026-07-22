#!/usr/bin/env bash
# Tests for lib/batch-common.sh — fleet-clean shared plumbing.
#
# Headline cases cover the field-observed defects closed at the batch layer:
#   - path normalization: `ghq list -p` backslash paths -> git-friendly forward
#     slashes (deterministic on the Linux CI runner, where `\` is a legal byte).
#   - resolve/dedup: the same repo named two ways is processed once; a non-repo
#     input is recorded, not silently dropped.
#   - shared-object-store dedup: linked worktrees collapse to one common dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
# shellcheck source=batch-common.sh
source "$SCRIPT_DIR/batch-common.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

# --- 1. batch_normalize_input: backslash -> forward slash, CR + trailing slash ---
got="$(batch_normalize_input 'D:\work\acme\keepme')"
assert_contains "backslash path normalized to forward slashes" "$got" 'D:/work/acme/keepme'
backslash=$'\134'
assert_not_contains "no backslash remains" "$got" "$backslash"

got="$(batch_normalize_input $'D:/work/acme/keepme\r')"
if [[ "$got" == 'D:/work/acme/keepme' ]]; then
  pass "trailing CR stripped"
else
  fail "trailing CR stripped" 'D:/work/acme/keepme' "$got"
fi

got="$(batch_normalize_input 'D:/work/acme/keepme/')"
if [[ "$got" == 'D:/work/acme/keepme' ]]; then
  pass "trailing slash collapsed"
else
  fail "trailing slash collapsed" 'D:/work/acme/keepme' "$got"
fi

# --- 2. batch_resolve_repos: dedup by canonical toplevel ---
git init "$TEST_TMPDIR/repoA" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repoA" config user.email t@example.com
git -C "$TEST_TMPDIR/repoA" config user.name Test
git init "$TEST_TMPDIR/repoB" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repoB" config user.email t@example.com
git -C "$TEST_TMPDIR/repoB" config user.name Test

# repoA named twice (once via a nested subdir) + repoB once => 2 unique.
mkdir -p "$TEST_TMPDIR/repoA/sub"
batch_resolve_repos "$TEST_TMPDIR/repoA" "$TEST_TMPDIR/repoA/sub" "$TEST_TMPDIR/repoB"
if [[ "${#BATCH_TOPS[@]}" -eq 2 ]]; then
  pass "duplicate repo (named two ways) deduped to 2 unique tops"
else
  fail "dedup to 2 unique tops" 2 "${#BATCH_TOPS[@]}"
fi

# --- 3. batch_resolve_repos: invalid inputs recorded, not dropped ---
mkdir -p "$TEST_TMPDIR/plaindir"
batch_resolve_repos "$TEST_TMPDIR/repoA" "$TEST_TMPDIR/plaindir" "$TEST_TMPDIR/nope"
if [[ "${#BATCH_TOPS[@]}" -eq 1 ]]; then
  pass "one valid repo resolved"
else
  fail "one valid repo resolved" 1 "${#BATCH_TOPS[@]}"
fi
if [[ "${#BATCH_INVALID[@]}" -eq 2 ]]; then
  pass "two invalid inputs recorded"
else
  fail "two invalid inputs recorded" 2 "${#BATCH_INVALID[@]}"
fi
reasons="$(printf '%s\n' "${BATCH_INVALID_REASONS[@]}")"
assert_contains "plain dir reported not-a-git-repo" "$reasons" "not-a-git-repo"
assert_contains "missing path reported not-a-directory" "$reasons" "not-a-directory"

# --- 4. batch_add_gitdir: linked worktrees collapse to one shared object store ---
git -C "$TEST_TMPDIR/repoA" commit --allow-empty -m init >/dev/null 2>&1
git -C "$TEST_TMPDIR/repoA" worktree add "$TEST_TMPDIR/repoA-wt" -b wt >/dev/null 2>&1
batch_reset_gitdirs
batch_add_gitdir "$TEST_TMPDIR/repoA"
rc_main=$?
batch_add_gitdir "$TEST_TMPDIR/repoA-wt"
rc_wt=$?
assert_exit "main clone is a new common dir (rc 0)" 0 "$rc_main"
assert_exit "linked worktree dedups to the same common dir (rc 2)" 2 "$rc_wt"
if [[ "${#BATCH_GITDIR_KEYS[@]}" -eq 1 ]]; then
  pass "worktree + main clone collapse to one shared object store"
else
  fail "one shared object store" 1 "${#BATCH_GITDIR_KEYS[@]}"
fi

# A second independent repo is a distinct common dir.
git -C "$TEST_TMPDIR/repoB" commit --allow-empty -m init >/dev/null 2>&1
batch_add_gitdir "$TEST_TMPDIR/repoB"
if [[ "${#BATCH_GITDIR_KEYS[@]}" -eq 2 ]]; then
  pass "independent repo is a distinct common dir"
else
  fail "distinct common dir" 2 "${#BATCH_GITDIR_KEYS[@]}"
fi

# --- 5. batch_read_lines_into: CR-stripped, non-empty ---
printf 'a\r\n\nb\n' >"$TEST_TMPDIR/lines.txt"
LINES=()
batch_read_lines_into LINES "$TEST_TMPDIR/lines.txt"
if [[ "${#LINES[@]}" -eq 2 && "${LINES[0]}" == a && "${LINES[1]}" == b ]]; then
  pass "read_lines_into strips CR and empties"
else
  fail "read_lines_into strips CR and empties" "a,b" "${LINES[*]}"
fi

[[ $FAILED -eq 0 ]] || exit 1
echo "batch-common.test.sh: all passed"
