#!/usr/bin/env bash
# test-scope: plugins/corrections/scripts/fixtures/prove-check-turn-end/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

export TMPDIR="$TEST_TMPDIR/tmp"
mkdir -p "$TMPDIR"

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
{
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config tag.gpgsign false
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

run() {
  local o="$TEST_TMPDIR/out" e="$TEST_TMPDIR/err"
  (cd "$REPO" && bash "$ENGINE" "$@") >"$o" 2>"$e"
  RC=$?
  OUT="$(<"$o")"
  ERR="$(<"$e")"
}

CHECK_NO_TODO='! grep -q TODO notes.txt'

run --check "$CHECK_NO_TODO" --old violation
if ((RC == 0)) && [[ "$OUT" == *"exit 1"* && "$OUT" == *"exit 0"* ]]; then
  pass "check fails at the violation and passes after its revert (exit 0)"
else
  fail "violation then revert should prove" "rc=$RC out=$OUT err=$ERR"
fi

run --check 'true' --old violation
if ((RC == 1)); then
  pass "check that passes on both refs exits 1"
else
  fail "pass on both should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

run --check 'false' --old violation
if ((RC == 1)); then
  pass "check that fails on both refs exits 1"
else
  fail "fail on both should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

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

git -C "$REPO" diff violation^ violation >"$TEST_TMPDIR/plant.patch"
printf 'not a patch\n' >"$TEST_TMPDIR/bad.patch"
clean() {
  local n left
  n="$(git -C "$REPO" worktree list | wc -l)"
  left="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 | wc -l)"
  if ((n == 1 && left == 0)); then
    pass "$1"
  else
    fail "$1" "worktrees=$n leftover=$left"
  fi
}

run --check "$CHECK_NO_TODO" --plant "$TEST_TMPDIR/plant.patch"
planted="$(sed -n 's/^old (planted \([0-9a-f]*\)).*/\1/p' <<<"$OUT")"
if ((RC == 0)) && [[ -n "$planted" && "$OUT" == *"exit 1"* && "$OUT" == *"exit 0"* ]]; then
  pass "planted violation fails the check, current code passes it (exit 0)"
else
  fail "planted proof should hold" "rc=$RC out=$OUT err=$ERR"
fi
if [[ -n "$planted" ]] && ! grep -q "$planted" < <(git -C "$REPO" rev-list --all --reflog); then
  pass "the plant commit is reachable from no ref or reflog"
else
  fail "plant commit still reachable" "planted=$planted"
fi
clean "no worktree left behind after a planted proof"

run --check 'awk '\''!/TODO/'\'' notes.txt >n.tmp && mv n.tmp notes.txt && git diff --quiet' --plant "$TEST_TMPDIR/plant.patch"
if ((RC == 0)); then
  pass "a rewrite-then-diff check proves against a plant"
else
  fail "rewrite-then-diff check should prove" "rc=$RC out=$OUT err=$ERR"
fi
run --check 'git diff --quiet HEAD' --plant "$TEST_TMPDIR/plant.patch"
if ((RC == 1)) && [[ "$OUT" == "old (planted "*"exit 0"* ]]; then
  pass "the planted side has no uncommitted change"
else
  fail "planted side should be a clean commit" "rc=$RC out=$OUT err=$ERR"
fi

run --check 'true' --plant "$TEST_TMPDIR/plant.patch"
if ((RC == 1)); then
  pass "check that passes on the plant exits 1"
else
  fail "pass on the plant should exit 1" "rc=$RC out=$OUT err=$ERR"
fi
clean "no worktree left behind after a failed planted proof"

run --check "$CHECK_NO_TODO" --plant "$TEST_TMPDIR/bad.patch"
rc_bad=$RC
run --check "$CHECK_NO_TODO" --plant "$TEST_TMPDIR/missing.patch"
rc_missing=$RC
run --check "$CHECK_NO_TODO" --plant "$TEST_TMPDIR/plant.patch" --old violation
rc_both=$RC
if ((rc_bad == 2 && rc_missing == 2 && rc_both == 2)); then
  pass "unusable plant exits 2"
else
  fail "plant usage errors should exit 2" "bad=$rc_bad missing=$rc_missing both=$rc_both"
fi
clean "no worktree left behind after a plant that does not apply"

FIXTURE="$SCRIPT_DIR/fixtures/prove-check-turn-end"
CHECK_ALL_RAN='grep -qE "([0-9]+) of \1 items ran"'
run_outside_repo() {
  local o="$TEST_TMPDIR/out" e="$TEST_TMPDIR/err"
  (cd "$TMPDIR" && bash "$ENGINE" "$@") >"$o" 2>"$e"
  RC=$?
  OUT="$(<"$o")"
  ERR="$(<"$e")"
}

run_outside_repo --check "$CHECK_ALL_RAN" --fixture "$FIXTURE"
if ((RC == 0)) && [[ "$OUT" == *"with-mistake ($FIXTURE/with-mistake): exit 1 (expected non-zero)"* &&
  "$OUT" == *"without-mistake ($FIXTURE/without-mistake): exit 0 (expected 0)"* ]]; then
  pass "fixture check fails on with-mistake and passes on without-mistake (exit 0), outside a repository"
else
  fail "fixture proof should hold" "rc=$RC out=$OUT err=$ERR"
fi

run --check ': >touched; grep -qE "([0-9]+) of \1 items ran" stdin' --fixture "$FIXTURE"
if ((RC == 0)) && [[ ! -e "$FIXTURE/with-mistake/touched" && ! -e "$FIXTURE/without-mistake/touched" ]]; then
  pass "the check runs in a copy of each fixture input and leaves the fixture unchanged"
else
  fail "fixture check should run in a copy" "rc=$RC out=$OUT err=$ERR"
fi

run --check 'true' --fixture "$FIXTURE"
if ((RC == 1)) && [[ "$ERR" == *"$FIXTURE/with-mistake"*"expected non-zero, observed 0"* ]]; then
  pass "check that passes on with-mistake exits 1 and names the input"
else
  fail "pass on with-mistake should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

run --check 'false' --fixture "$FIXTURE"
if ((RC == 1)) && [[ "$ERR" == *"$FIXTURE/without-mistake"*"expected 0, observed 1"* ]]; then
  pass "check that fails on without-mistake exits 1 and names the input"
else
  fail "fail on without-mistake should exit 1" "rc=$RC out=$OUT err=$ERR"
fi

mkdir -p "$TEST_TMPDIR/one-sided/with-mistake"
run --check "$CHECK_ALL_RAN" --fixture "$TEST_TMPDIR/one-sided"
rc_side=$RC err_side=$ERR
run --check "$CHECK_ALL_RAN" --fixture "$TEST_TMPDIR/no-such-fixture"
rc_dir=$RC
run --check "$CHECK_ALL_RAN" --fixture "$FIXTURE" --old violation
rc_old=$RC
run --check "$CHECK_ALL_RAN" --fixture "$FIXTURE" --new HEAD
rc_new=$RC
if ((rc_side == 2 && rc_dir == 2 && rc_old == 2 && rc_new == 2)) &&
  [[ "$err_side" == *"$TEST_TMPDIR/one-sided/without-mistake"* ]]; then
  pass "unusable fixture exits 2 and names the missing input"
else
  fail "fixture usage errors should exit 2" "side=$rc_side dir=$rc_dir old=$rc_old new=$rc_new err=$err_side"
fi
clean "no temporary directory left behind after a fixture proof"

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
