#!/usr/bin/env bash
# Regression tests for diff-vs-base.sh (self-contained, offline — ships with the plugin).
#
# Every fixture is a local repo whose "remote" is a bare repo on disk, so no
# network is touched. Branch names are explicit (never init.defaultBranch) and the
# non-`main` fixtures make the assertions unambiguous about WHICH fallback ran.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/diff-vs-base.sh"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
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

# Fixture repos must never inherit an outer hook chain's exported git env.
git_env_reset() { unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR; }

# make_fixture <name> <branch> — bare origin whose HEAD is <branch>, plus a clone-ish
# work repo one commit ahead of the pushed tip. Echoes the work-repo path.
make_fixture() {
  local name="$1" branch="$2"
  local bare="$TEST_TMPDIR/$name.git" work="$TEST_TMPDIR/$name"
  git_env_reset
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD "refs/heads/$branch"
  mkdir -p "$work"
  git -C "$work" init -q
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config user.name "test"
  # Fixtures must not inherit a developer's global core.autocrlf: it makes git warn
  # about LF->CRLF rewrites and would change the byte counts these cases assert on.
  git -C "$work" config core.autocrlf false
  git -C "$work" checkout -q -b "$branch"
  printf 'base\n' >"$work/base.txt"
  git -C "$work" add base.txt
  git -C "$work" commit -q -m base
  git -C "$work" remote add origin "$bare"
  git -C "$work" push -q origin "$branch"
  printf '%s\n' "$work"
}

add_commit_ahead() {
  printf 'one\ntwo\nthree\n' >"$1/ahead.txt"
  git -C "$1" add ahead.txt
  git -C "$1" commit -q -m ahead
}

# Git >= 2.49 may create refs/remotes/origin/HEAD on fetch/push
# (remote.<name>.followRemoteHEAD defaults to "create"), so the fallback fixtures
# clear it explicitly rather than assuming it was never written.
drop_origin_head() { git -C "$1" symbolic-ref -q -d refs/remotes/origin/HEAD >/dev/null 2>&1 || true; }

run_in() { (cd "$1" && git_env_reset && bash "$SCRIPT"); }

# --- Case 1: --help ---
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: origin/HEAD resolves (first branch of the chain) ---
W2=$(make_fixture case2 trunk)
git -C "$W2" remote set-head origin -a >/dev/null 2>&1
add_commit_ahead "$W2"
rc=0
OUT=$(run_in "$W2") || rc=$?
assert_exit "origin/HEAD path exits 0" 0 "$rc"
assert_contains "origin/HEAD path reports the changed file" "$OUT" "1 file changed"
assert_contains "origin/HEAD path reports the insertions" "$OUT" "3 insertions"

# --- Case 3: range resolves but is empty -> prints NOTHING, not "unavailable" ---
W3=$(make_fixture case3 trunk)
git -C "$W3" remote set-head origin -a >/dev/null 2>&1
rc=0
OUT=$(run_in "$W3") || rc=$?
assert_exit "empty range exits 0" 0 "$rc"
assert_eq "empty range prints nothing" "" "$OUT"

# --- Case 4: no origin/HEAD -> ls-remote --symref resolves the default branch ---
# The default branch is `trunk`, so `origin/main` cannot satisfy this case.
W4=$(make_fixture case4 trunk)
drop_origin_head "$W4"
add_commit_ahead "$W4"
rc=0
OUT=$(run_in "$W4") || rc=$?
assert_exit "ls-remote path exits 0" 0 "$rc"
assert_contains "ls-remote path reports the changed file" "$OUT" "1 file changed"

# --- Case 5: no origin/HEAD and an unreachable remote -> origin/main fallback ---
W5=$(make_fixture case5 main)
drop_origin_head "$W5"
add_commit_ahead "$W5"
git -C "$W5" remote set-url origin "$TEST_TMPDIR/no-such-remote.git"
rc=0
OUT=$(run_in "$W5") || rc=$?
assert_exit "origin/main path exits 0" 0 "$rc"
assert_contains "origin/main path reports the changed file" "$OUT" "1 file changed"

# --- Case 6: nothing resolves -> "unavailable", still exit 0 ---
W6="$TEST_TMPDIR/case6"
git_env_reset
mkdir -p "$W6"
git -C "$W6" init -q
git -C "$W6" config user.email "test@example.com"
git -C "$W6" config user.name "test"
git -C "$W6" config core.autocrlf false
git -C "$W6" commit -q --allow-empty -m init
rc=0
OUT=$(run_in "$W6") || rc=$?
assert_exit "no-base path exits 0" 0 "$rc"
assert_eq "no-base path prints unavailable" "unavailable" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
