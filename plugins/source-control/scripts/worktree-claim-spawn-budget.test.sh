#!/usr/bin/env bash
# Spawn-budget regression test for worktree-claim.sh (#10562). The process
# count of one call must not grow with the number of registered worktrees, and
# stale --batch's must not grow with the number of paths. Before #10562 every
# registered worktree cost three forks (two command substitutions for the
# lexical collapse, one for `cd && pwd -P`), so one call in a repository with
# 1,243 linked worktrees took about 4 s.
#
# strace and not xtrace or a PATH shim, for the reason
# hooks/worktree-gates-spawn-budget.test.sh gives: a command substitution is a
# fork that never execs, which only a clone/fork trace counts.
#
# WHAT IS ASSERTED: the count with LARGE worktrees is at most the count with
# SMALL worktrees plus SLACK, never an absolute ceiling, so constant work added
# elsewhere in the script cannot fail this suite while a per-worktree fork
# (three for each of the extra worktrees before the fix) always does.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM="$SCRIPT_DIR/worktree-claim.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v strace >/dev/null 2>&1 || skip_suite "strace not available (Linux-only; worktree-claim.test.sh carries the portable coverage)"
# A strace that cannot attach reports nothing, which would pass every bound.
if ! strace -f -qq -e trace=execve -o /dev/null /bin/true >/dev/null 2>&1; then
  skip_suite "strace cannot ptrace here (container seccomp or /proc/sys/kernel/yama/ptrace_scope)"
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

SMALL=3
LARGE=40
# Nothing in the claim helper forks per worktree or per path, so the counts are
# equal; the slack only absorbs a stray constant fork, far below the 3 * 37
# a per-worktree regression adds.
SLACK=2
HOST=budgethost
CFG="$TEST_TMPDIR/config"
mkdir -p "$CFG/projects/-proj"

# mkrepo <name> <linked-count>: a repository with <linked-count> linked
# worktrees side by side under one parent, as a worktree root holds them, each
# locked with a lane reason from this host so stale runs every check, the
# transcript scan included.
mkrepo() {
  local repo="$TEST_TMPDIR/$1" wts="$TEST_TMPDIR/$1-wts" i
  git -C "$TEST_TMPDIR" init -q -b main "$1" >/dev/null 2>&1
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m seed
  mkdir -p "$wts"
  for ((i = 0; i < $2; i++)); do
    git -C "$repo" worktree add -q "$wts/wt-$i" -b "b-$i" >/dev/null 2>&1
    git -C "$repo" worktree lock --reason \
      "worktree-claim.sh: lane active on $HOST session s-$1-$i since 2026-01-01T00:00:00Z; unlock when the owning lane is done" \
      "$wts/wt-$i"
  done
}
mkrepo small "$SMALL"
mkrepo large "$LARGE"

# paths_file <name> <count>: the first <count> worktree paths of <name>, NUL-delimited.
paths_file() {
  local f="$TEST_TMPDIR/$1-$2.paths" i
  for ((i = 0; i < $2; i++)); do printf '%s\0' "$TEST_TMPDIR/$1-wts/wt-$i"; done >"$f"
  printf '%s' "$f"
}
EMPTY_IN="$TEST_TMPDIR/empty"
: >"$EMPTY_IN"

CREATIONS=0
# measure <stdin-file> <args...>: fill CREATIONS for one run, from a directory
# outside both repositories.
measure() {
  local in="$1" trace
  shift
  trace="$(mktemp "$TEST_TMPDIR/trace.XXXXXX")"
  (cd "$TEST_TMPDIR" && CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST" \
    strace -f -qq -e trace=clone,clone3,fork,vfork -o "$trace" \
    bash "$CLAIM" "$@" <"$in" >/dev/null 2>&1)
  CREATIONS=$(grep -cE '(clone3?|v?fork)\(' "$trace")
  rm -f "$trace"
}

# assert_flat <label> <small-stdin> <large-stdin> <small-args> -- <large-args>
assert_flat() {
  local label="$1" small_in="$2" large_in="$3" small large
  shift 3
  local -a small_args=() large_args=()
  while [[ "$1" != -- ]]; do
    small_args+=("$1")
    shift
  done
  shift
  large_args=("$@")
  measure "$small_in" "${small_args[@]}"
  small=$CREATIONS
  measure "$large_in" "${large_args[@]}"
  large=$CREATIONS
  if ((small > 0 && large <= small + SLACK)); then
    pass "$label: process creations do not grow ($large vs $small, slack $SLACK)"
  else
    fail "$label: process creations" "<= $((small + SLACK)) (and a non-empty trace)" "$large"
  fi
}

S="$TEST_TMPDIR/small"
L="$TEST_TMPDIR/large"
assert_flat "stale, $SMALL vs $LARGE worktrees" "$EMPTY_IN" "$EMPTY_IN" \
  stale "$S-wts/wt-0" --repo-dir "$S" -- stale "$L-wts/wt-0" --repo-dir "$L"
assert_flat "check-enter, $SMALL vs $LARGE worktrees" "$EMPTY_IN" "$EMPTY_IN" \
  check-enter "$S-wts/wt-0" --repo-dir "$S" --session-id other -- \
  check-enter "$L-wts/wt-0" --repo-dir "$L" --session-id other
assert_flat "report, $SMALL vs $LARGE worktrees" "$EMPTY_IN" "$EMPTY_IN" \
  report --repo-dir "$S" -- report --repo-dir "$L"
assert_flat "stale --batch, $SMALL vs $LARGE paths" "$(paths_file large "$SMALL")" "$(paths_file large "$LARGE")" \
  stale --batch --repo-dir "$L" -- stale --batch --repo-dir "$L"

[[ $FAILED -eq 0 ]] || exit 1
