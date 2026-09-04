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
got="$(batch_normalize_input 'D:\work\acme\keepme')" # portability-ok: a Windows drive path fixture, not a GNU grep \w class — the backslashes are the input this case normalizes
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

# --- 5. batch_read_lines_into: CR-stripped, non-empty, rc 0 ---
printf 'a\r\n\nb\n' >"$TEST_TMPDIR/lines.txt"
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/lines.txt" || rc=$?
assert_exit "CR-stripped file is success (rc 0)" 0 "$rc"
if [[ "${#LINES[@]}" -eq 2 && "${LINES[0]}" == a && "${LINES[1]}" == b ]]; then
  pass "read_lines_into strips CR and empties"
else
  fail "read_lines_into strips CR and empties" "a,b" "${LINES[*]}"
fi

# expect_single_a <rc label> <case label> <rc> — the read reported success and
# left exactly the one entry `a` in the global LINES the call populated.
expect_single_a() {
  local rc_label="$1" case_label="$2" rc="$3"
  assert_exit "$rc_label" 0 "$rc"
  if [[ "${#LINES[@]}" -eq 1 && "${LINES[0]}" == a ]]; then
    pass "$case_label"
  else
    fail "$case_label" "a" "${LINES[*]}"
  fi
}

# --- 5b. empty file, trailing blank, missing final newline: all rc 0 ---
: >"$TEST_TMPDIR/empty.txt"
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/empty.txt" || rc=$?
assert_exit "empty file is success (rc 0)" 0 "$rc"
if [[ "${#LINES[@]}" -eq 0 ]]; then
  pass "empty file appends nothing"
else
  fail "empty file appends nothing" 0 "${#LINES[@]}"
fi

printf 'a\n\n' >"$TEST_TMPDIR/trail.txt"
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/trail.txt" || rc=$?
expect_single_a "trailing blank line is success (rc 0)" "trailing blank keeps the preceding entry" "$rc"

printf 'a' >"$TEST_TMPDIR/noeol.txt"
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/noeol.txt" || rc=$?
expect_single_a "unterminated final line is success (rc 0)" "unterminated final line is kept" "$rc"

# Stdin (`-`): ordinary EOF is success, including a trailing blank.
LINES=()
rc=0
batch_read_lines_into LINES - < <(printf 'a\n\n') || rc=$?
expect_single_a "stdin trailing blank is success (rc 0)" "stdin trailing blank keeps the preceding entry" "$rc"

# --- 5c. missing / non-regular / unopenable named sources return 1 ---
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/no-such-list.txt" || rc=$?
assert_exit "missing named source returns 1" 1 "$rc"
if [[ "${#LINES[@]}" -eq 0 ]]; then
  pass "missing source appends nothing"
else
  fail "missing source appends nothing" 0 "${#LINES[@]}"
fi

mkdir -p "$TEST_TMPDIR/not-a-file"
LINES=()
rc=0
batch_read_lines_into LINES "$TEST_TMPDIR/not-a-file" || rc=$?
assert_exit "directory (non-regular) returns 1" 1 "$rc"

UNREAD="$TEST_TMPDIR/unreadable.txt"
printf 'a\n' >"$UNREAD"
chmod 000 "$UNREAD" 2>/dev/null || true
if [[ -r "$UNREAD" ]]; then
  skip_case "unopenable regular file: chmod 000 not enforced on this filesystem (CAP_DAC_OVERRIDE); missing/non-regular cases already cover rc 1"
else
  LINES=()
  rc=0
  batch_read_lines_into LINES "$UNREAD" || rc=$?
  assert_exit "unopenable regular file returns 1" 1 "$rc"
fi
chmod 644 "$UNREAD" 2>/dev/null || true

# Fixed fd 3 (not Bash `{fd}`, which allocates from 10 up) so a named source
# still opens when the runner's soft nofile ceiling is 10. Codex flagged the
# missing case on #3641 after `{fd}` failed under that ulimit.
printf 'keep\n' >"$TEST_TMPDIR/lowfd.txt"
if (ulimit -n 10) >/dev/null 2>&1; then
  LINES=()
  rc=0
  out="$(
    bash -c '
      ulimit -n 10 || exit 125
      # shellcheck source=batch-common.sh
      source "$1"
      LINES=()
      batch_read_lines_into LINES "$2" || exit $?
      printf "%s\n" "${LINES[0]}"
    ' bash "$SCRIPT_DIR/batch-common.sh" "$TEST_TMPDIR/lowfd.txt"
  )" || rc=$?
  if [[ $rc -eq 125 ]]; then
    skip_case "ulimit -n 10 refused on this host"
  else
    assert_exit "named source opens under ulimit -n 10" 0 "$rc"
    if [[ "$out" == "keep" ]]; then
      pass "low-fd read yields the line"
    else
      fail "low-fd read yields the line" "keep" "$out"
    fi
  fi
else
  skip_case "cannot lower ulimit -n on this host"
fi

[[ $FAILED -eq 0 ]] || exit 1
echo "batch-common.test.sh: all passed"
