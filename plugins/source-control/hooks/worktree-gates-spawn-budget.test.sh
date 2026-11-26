#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILED=0
CASE_NUM=0
# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available (the hooks fail open without it)"
command -v strace >/dev/null 2>&1 || skip_suite "strace not available (Linux-only; the gates' behavior suites carry the portable coverage)"
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
git -C "$REPO" config worktreeroot.path "$OUTSIDE"

payload() {
  jq -n --arg cwd "$1" --arg cmd "$2" --arg ev "$3" \
    '{session_id:"budget",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:$ev,tool_name:"Bash",tool_input:{command:$cmd}}'
}

CREATIONS=0
EXECVES=0
measure() {
  local hook="$1" payload="$2" trace
  trace="$(mktemp "$TEST_TMPDIR/trace.XXXXXX")"
  printf '%s' "$payload" |
    strace -f -qq -e trace=clone,clone3,fork,vfork,execve -o "$trace" \
      bash "$hook" >/dev/null 2>/dev/null
  CREATIONS=$(grep -E '(clone3?|v?fork)\(' "$trace" | grep -vc CLONE_THREAD)
  EXECVES=$(($(grep -cE 'execve\(' "$trace") - 1))
  rm -f "$trace"
}

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

assert_exact() {
  local label="$1" hook="$2" pl="$3" wantc="$4" wante="$5"
  measure "$hook" "$pl"
  if ((CREATIONS == wantc)); then
    pass "$label: exactly $CREATIONS process creations"
  else
    fail "$label: process creations" "$wantc" "$CREATIONS"
  fi
  if ((EXECVES == wante)); then
    pass "$label: exactly $EXECVES execve"
  else
    fail "$label: execve" "$wante" "$EXECVES"
  fi
}

CONTAIN="$SCRIPT_DIR/worktree-add-containment-gate.sh"
CLAIM="$SCRIPT_DIR/worktree-add-claim.sh"
CREATE="$SCRIPT_DIR/worktree-create-gate.sh"

assert_budget "containment, non-add command" "$CONTAIN" \
  "$(payload "$OUTSIDE" 'git worktree list' PreToolUse)" 7 2

assert_exact "containment, add outside a repo" "$CONTAIN" \
  "$(payload "$OUTSIDE" "git worktree add $OUTSIDE/wt-ok -b b1" PreToolUse)" 20 6

assert_exact "containment, git -C <repo> add (names root)" "$CONTAIN" \
  "$(payload "$OUTSIDE" "git -C $REPO worktree add sub/nested" PreToolUse)" 24 7

assert_exact "containment, add into a working tree" "$CONTAIN" \
  "$(payload "$REPO" "git worktree add sub/nested" PreToolUse)" 23 7

assert_budget "claim, non-add command" "$CLAIM" \
  "$(payload "$OUTSIDE" 'git worktree list' PostToolUse)" 7 2

assert_exact "claim, parsed add target" "$CLAIM" \
  "$(payload "$OUTSIDE" "git worktree add $OUTSIDE/wt-claim -b b2" PostToolUse)" 23 7

assert_budget "create, payload with no .name" "$CREATE" \
  "$(jq -n --arg cwd "$REPO" '{session_id:"budget",cwd:$cwd,hook_event_name:"WorktreeCreate",name:""}')" 13 4

HERESTRING_PAYLOAD='<<<[[:space:]]*"?\$\{?(INPUT|payload)\}?'
for gate in "$CONTAIN" "$CLAIM" "$CREATE"; do
  if grep -nE "$HERESTRING_PAYLOAD" "$gate" >/dev/null; then
    fail "${gate##*/}: payload fed to a reader by here-string" \
      "printf '%s' \"\$INPUT\" | jq (lib/hook-utils.sh, hook::jq_field)" \
      "$(grep -nE "$HERESTRING_PAYLOAD" "$gate" | head -n 1)"
  else
    pass "${gate##*/}: no here-string carries the payload"
  fi
done

[[ $FAILED -eq 0 ]] || exit 1
