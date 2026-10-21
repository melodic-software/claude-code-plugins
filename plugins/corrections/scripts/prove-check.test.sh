#!/usr/bin/env bash
# Regression tests for prove-check.sh.
# Black-box against a throwaway git fixture under a mktemp dir: a repository
# whose first commit plants a violation (a deferred-work marker) and whose second commit
# reverts it. No network.
#
# Cases: the check fails at the violation and passes after its revert (exit 0);
# a check that passes on both refs (exit 1); a check that fails on both
# (exit 1); a bad argument (exit 2); no worktree left behind.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/prove-check.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  [[ -n "${2:-}" ]] && printf '  %s\n' "$2"
}

if ! command -v git >/dev/null 2>&1; then
  echo "1..0 # SKIP git not available"
  exit 0
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# The engine's own temporary worktrees go under a private TMPDIR, so the
# "nothing left behind" case can look at exactly what it created.
export TMPDIR="$TEST_TMPDIR/tmp"
mkdir -p "$TMPDIR"

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
{
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config core.autocrlf false
  printf 'clean\n' >"$REPO/notes.txt"
  git -C "$REPO" add notes.txt
  git -C "$REPO" commit -qm base
  printf 'TODO fix me\n' >"$REPO/notes.txt"
  git -C "$REPO" commit -qam "plant violation"
  git -C "$REPO" tag violation
  printf 'clean\n' >"$REPO/notes.txt"
  git -C "$REPO" commit -qam "revert violation"
} >/dev/null 2>&1

# run <args...>: run the engine from inside the fixture; sets OUT, ERR, RC.
run() {
  local o="$TEST_TMPDIR/out" e="$TEST_TMPDIR/err"
  (cd "$REPO" && bash "$ENGINE" "$@") >"$o" 2>"$e"
  RC=$?
  OUT="$(<"$o")"
  ERR="$(<"$e")"
}

CHECK_NO_TODO='! grep -q TODO notes.txt'

# 1. Fails at the violation, passes after the revert.
run --check "$CHECK_NO_TODO" --old violation
if ((RC == 0)) && [[ "$OUT" == *"exit 1"* && "$OUT" == *"exit 0"* ]]; then
  pass "check fails at the violation and passes after its revert (exit 0)"
else
  fail "violation then revert should prove" "rc=$RC out=$OUT err=$ERR"
fi

# 2. Passes on both refs.
run --check 'true' --old violation
if ((RC == 1)); then
  pass "check that passes on both refs exits 1"
else
  fail "pass on both should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

# 3. Fails on both refs.
run --check 'false' --old violation
if ((RC == 1)); then
  pass "check that fails on both refs exits 1"
else
  fail "fail on both should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

# 4. Bad arguments.
run --check "$CHECK_NO_TODO" --bogus
rc_flag=$RC
run --check "$CHECK_NO_TODO"
rc_missing=$RC
run --check "$CHECK_NO_TODO" --old no-such-ref
rc_ref=$RC
if ((rc_flag == 2 && rc_missing == 2 && rc_ref == 2)); then
  pass "bad argument exits 2"
else
  fail "usage errors should exit 2" "flag=$rc_flag missing=$rc_missing ref=$rc_ref"
fi

# 5. No worktree left behind, after a proof, a failed proof and a usage error.
worktrees="$(git -C "$REPO" worktree list | wc -l)"
leftover="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 | wc -l)"
if ((worktrees == 1 && leftover == 0)); then
  pass "no worktree left behind"
else
  fail "worktrees or temp dirs remain" "worktrees=$worktrees leftover=$leftover"
fi

if ((FAILED > 0)); then
  printf '%d of %d failed\n' "$FAILED" "$CASE_NUM"
  exit 1
fi
printf 'all %d passed\n' "$CASE_NUM"
