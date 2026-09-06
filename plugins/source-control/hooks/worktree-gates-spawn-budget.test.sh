#!/usr/bin/env bash
# Spawn-budget regression tests for the three worktree gates (#3510).
#
# WHY strace AND NOT xtrace OR A PATH SHIM. The cost these gates were paying is
# a FORK THAT NEVER EXECS: a command substitution whose body carries a
# redirection of its own forks the substitution subshell and then forks AGAIN to
# run the command, where the same redirection hoisted onto a group holding one
# command lets bash exec in the substitution's own subshell. `set -x` sees the
# command either way and a PATH shim only ever sees the exec, so both are blind
# to the entire subject. `strace -f -e trace=clone,clone3,fork,vfork,execve`
# counts the creation itself, which is the number that maps to the Windows
# process-creation tax in #3508.
#
# WHAT IS ASSERTED — an UPPER BOUND, not an equality. A later change that
# removes more work (hook-utils.sh gaining a `_to` reader, say) must not fail
# this suite; a reverted hoist must. Each ceiling below is the measured count
# with every hoist in place, and reverting ANY ONE of the six hoists this suite
# guards raises at least one ceiling's case by 2 or more. The mutation check is
# recorded in the PR, not re-run here.
#
# The counts include hook-utils.sh's own share (the buffer_stdin substitution
# and hook::json_complete's `printf | jq -e .`), which these hooks cannot reach:
# the library is synced across 17 plugin copies by scripts/sync-hook-utils.sh
# and is out of scope for an in-file perf change.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=0
CASE_NUM=0
# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available (the hooks fail open without it)"
command -v strace >/dev/null 2>&1 || skip_suite "strace not available (Linux-only; the gates' behaviour suites carry the portable coverage)"
# ptrace is commonly restricted inside containers and on hardened hosts. A
# strace that cannot attach reports nothing, which would silently pass every
# ceiling — so probe once and skip the suite rather than assert on empty output.
if ! strace -f -qq -e trace=execve -o /dev/null /bin/true >/dev/null 2>&1; then
  skip_suite "strace cannot ptrace here (container seccomp or /proc/sys/kernel/yama/ptrace_scope)"
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO="$TEST_TMPDIR/repo"
OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$OUTSIDE" "$REPO"
git -C "$REPO" init -q -b main >/dev/null 2>&1
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
printf 'seed\n' >"$REPO/README"
git -C "$REPO" add README
git -C "$REPO" commit -q -m seed
mkdir -p "$REPO/sub"
# Present so the block message's root lookup runs its `git config --get-all`
# read, which is one of the hoists this suite guards.
git -C "$REPO" config melodic.worktreeroot "$OUTSIDE"

payload() { # payload <cwd> <command> <event>
  jq -n --arg cwd "$1" --arg cmd "$2" --arg ev "$3" \
    '{session_id:"budget",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:$ev,tool_name:"Bash",tool_input:{command:$cmd}}'
}

CREATIONS=0
EXECVES=0
# measure <hook-path> <payload>  — fill CREATIONS / EXECVES for one run. stdin
# arrives on a PIPE, the shape the harness uses.
measure() {
  local hook="$1" payload="$2" trace
  trace="$(mktemp "$TEST_TMPDIR/trace.XXXXXX")"
  printf '%s' "$payload" |
    strace -f -qq -e trace=clone,clone3,fork,vfork,execve -o "$trace" \
      bash "$hook" >/dev/null 2>/dev/null
  CREATIONS=$(grep -cE '(clone3?|v?fork)\(' "$trace")
  # The traced program's own execve is not a spawn the hook chose to make.
  EXECVES=$(($(grep -cE 'execve\(' "$trace") - 1))
  rm -f "$trace"
}

# assert_budget <label> <hook> <payload> <max-creations> <max-execve>
assert_budget() {
  local label="$1" hook="$2" pl="$3" maxc="$4" maxe="$5"
  measure "$hook" "$pl"
  if ((CREATIONS <= maxc)); then
    pass "$label: process creations within budget ($CREATIONS <= $maxc)"
  else
    fail "$label: process creations" "<= $maxc" "$CREATIONS"
  fi
  if ((EXECVES <= maxe)); then
    pass "$label: execve within budget ($EXECVES <= $maxe)"
  else
    fail "$label: execve" "<= $maxe" "$EXECVES"
  fi
}

CONTAIN="$SCRIPT_DIR/worktree-add-containment-gate.sh"
CLAIM="$SCRIPT_DIR/worktree-add-claim-gate.sh"
CREATE="$SCRIPT_DIR/worktree-create-gate.sh"

# ── containment gate (PreToolUse:Bash — the hook in #3510) ──────────────────
# The hot path: the matcher fired but this is not a `git worktree add`. Only the
# stdin buffer and ONE jq may run.
assert_budget "containment, non-add command" "$CONTAIN" \
  "$(payload "$OUTSIDE" 'git worktree list' PreToolUse)" 5 2

# A real add that lands outside every repository: two field reads plus the
# nearest-ancestor probes.
assert_budget "containment, add outside a repo" "$CONTAIN" \
  "$(payload "$OUTSIDE" "git worktree add $OUTSIDE/wt-ok -b b1" PreToolUse)" 14 5

# The deny path, including the block message's configured-root lookup.
assert_budget "containment, add into a working tree" "$CONTAIN" \
  "$(payload "$OUTSIDE" "git -C $REPO worktree add sub/nested" PreToolUse)" 16 6

# ── claim gate (PostToolUse:Bash) ───────────────────────────────────────────
assert_budget "claim, non-add command" "$CLAIM" \
  "$(payload "$OUTSIDE" 'git worktree list' PostToolUse)" 5 2

# A parsed add target: three field reads plus one worktree-claim.sh run.
assert_budget "claim, parsed add target" "$CLAIM" \
  "$(payload "$OUTSIDE" "git worktree add $OUTSIDE/wt-claim -b b2" PostToolUse)" 16 6

# ── create gate (WorktreeCreate) ────────────────────────────────────────────
# Refused before the helper runs, so the count is this hook's own field reads.
assert_budget "create, payload with no .name" "$CREATE" \
  "$(jq -n --arg cwd "$REPO" '{session_id:"budget",cwd:$cwd,hook_event_name:"WorktreeCreate",name:""}')" 7 4

[[ $FAILED -eq 0 ]] || exit 1
