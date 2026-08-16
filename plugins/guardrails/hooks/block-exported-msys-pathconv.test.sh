#!/usr/bin/env bash
# Contract test for block-exported-msys-pathconv.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash/PowerShell
# JSON on stdin, asserts on exit code (2 = blocked, 0 = allowed). The Windows
# lane is forced via OSTYPE=msys so Linux CI exercises the same matcher the
# Git Bash host would. Self-contained — no host-repo assertion library.
#
# The behavioral claim under test — that only the EXPORTED form suppresses MSYS
# argv conversion, while a bare assignment and a per-command prefix do not — is
# a Git-Bash-runtime fact and cannot be faked on Linux. It is recorded in the
# hook's header with the `git rev-parse --sq-quote` measurement that established
# it. What this suite asserts is that the MATCHER draws the line in that place.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-exported-msys-pathconv.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Force the Windows host gate even on Linux CI.
run_win() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "MSYS_NO_PATHCONV"
    assert_contains "$label → fix names the prefix form" "$out" "PER-COMMAND PREFIX"
  fi
}

run_win_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(pwsh_command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# Non-Windows host: neither variable has any effect — must never block.
run_posix_host() {
  local label="$1" command="$2"
  local rc
  env OSTYPE=linux-gnu bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" 0 "$rc"
}

# --- 1. Host gate ------------------------------------------------------------
run_posix_host "Linux host: exported suppressor allowed" 'export MSYS_NO_PATHCONV=1; git status'
run_posix_host "Linux host: ordinary command allowed" 'echo hello'

# --- 2. The defect shape (blocked) -------------------------------------------
run_win "export MSYS_NO_PATHCONV=1 (blocked)" 'export MSYS_NO_PATHCONV=1; git status' 2
run_win "export MSYS2_ARG_CONV_EXCL (blocked)" "export MSYS2_ARG_CONV_EXCL='*'; git status" 2
run_win "the real #2870 incident shape (blocked)" \
  'unset GIT_DIR GIT_WORK_TREE; export MSYS_NO_PATHCONV=1; cd /d/worktrees/calib && git worktree add --detach /d/worktrees/ccp-measure2 origin/main' 2
run_win "export chained with && (blocked)" \
  'cd "<repo-root>" && export MSYS_NO_PATHCONV=1 && git show "origin/main:.github/workflows/ci.yml"' 2
run_win "export of both variables at once (blocked)" \
  "export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'; git status" 2
run_win "export with a leading unrelated assignment (blocked)" \
  'export FOO=bar MSYS_NO_PATHCONV=1; git status' 2
run_win "declare -x form (blocked)" 'declare -x MSYS_NO_PATHCONV=1; git status' 2
run_win "typeset -x form (blocked)" 'typeset -x MSYS2_ARG_CONV_EXCL=1; git status' 2
run_win "export at the very start of the command (blocked)" 'export MSYS_NO_PATHCONV=1' 2

# --- 3. The SAFE idioms (allowed) --------------------------------------------
# These are the measured 193 real uses the guard must not touch. A per-command
# prefix scopes suppression to one command; a bare assignment does nothing at
# all. Firing on either would make the guard noise and get it disabled.
run_win "per-command prefix (allowed)" \
  'MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml"' 0
run_win "per-command prefix, both variables (allowed)" \
  "MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' git show 'origin/main:.claude/settings.json'" 0
run_win "per-command prefix mid-chain (allowed)" \
  'cd "<repo-root>" && MSYS_NO_PATHCONV=1 git show "origin/main:.github/x.yml" | head -5' 0
run_win "bare assignment, not exported (allowed)" 'MSYS_NO_PATHCONV=1; git status' 0
run_win "bare assignment with && (allowed)" 'MSYS2_ARG_CONV_EXCL=1 && git status' 0

# --- 3b. A prefix on a CHILD SHELL leaks, so it blocks -----------------------
# The prefix scopes to one PROCESS; when that process is an interpreter, "one
# process" is every command in the script. Verified behaviorally on a Git Bash
# host: `MSYS_NO_PATHCONV=1 bash -c 'git ... /d/a; git ... /d/b'` leaves BOTH
# unconverted, where the same prefix on `git` directly converts the second.
run_win "prefix on bash -c (blocked)" \
  "MSYS_NO_PATHCONV=1 bash -c 'git worktree add /d/worktrees/x'" 2
run_win "env prefix on bash -c (blocked)" \
  "env MSYS_NO_PATHCONV=1 bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on sh -c (blocked)" \
  "MSYS2_ARG_CONV_EXCL='*' sh -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on an absolute bash path (blocked)" \
  "MSYS_NO_PATHCONV=1 /usr/bin/bash -c 'git worktree add /d/worktrees/x'" 2
# ...but a prefix on a NON-shell command word stays allowed: that is the safe
# idiom the corpus uses 193 times, and narrowing it would be the false-positive
# tail that gets a guard disabled.
run_win "prefix on git itself stays allowed" \
  'MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml"' 0
run_win "prefix on gh stays allowed" \
  "MSYS_NO_PATHCONV=1 gh pr view 2878 --json body" 0
# The real corpus command that a first draft of this matcher wrongly blocked:
# the `sh` in `show` and the `s` of `settings.json` are not shell command words.
# Kept as a regression pin because it is exactly the shape a substring matcher
# gets wrong, and a false positive here is the failure mode that gets a guard
# switched off.
run_win "prefix on git show with a path containing 'sh' stays allowed" \
  "cd <repo-root> && MSYS_NO_PATHCONV=1 git show 'origin/main:.claude/settings.json'" 0
run_win "prefix on a command whose name merely ends in sh stays allowed" \
  "MSYS_NO_PATHCONV=1 refresh --all" 0
# ...and the matcher must not hang on it. An ERE draft backtracked
# catastrophically on this exact string; the token walk is linear.

# --- 4. Mentions that are not settings (allowed) -----------------------------
# The variable name appears constantly in this repo's own docs, issues, commit
# messages and greps. None of those set anything.
run_win "grep for the variable name (allowed)" \
  'grep -rn "MSYS_NO_PATHCONV" docs/' 0
run_win "prose in a commit message (allowed)" \
  'git commit -m "docs: never export MSYS_NO_PATHCONV, use the prefix form"' 0
run_win "gh issue body mentioning it (allowed)" \
  'gh issue create --title "MSYS2_ARG_CONV_EXCL leaks across a command string" --body-file b.md' 0
run_win "unset, not export (allowed)" 'unset MSYS_NO_PATHCONV; git status' 0
run_win "a similarly named variable (allowed)" 'export MSYS_NO_PATHCONV_NOTES=1; git status' 0
run_win "echo of the name (allowed)" 'echo "MSYS_NO_PATHCONV"' 0

# --- 5. Commands that never name either variable (allowed, fast path) --------
run_win "ordinary git worktree add with an MSYS path (allowed)" \
  'git worktree add --detach /d/worktrees/x origin/main' 0
run_win "ordinary command (allowed)" 'ls -la /c/Users' 0

# The path-shape matcher this guard deliberately does NOT use would fire on the
# case above — 81% of real `git worktree add` calls carry an /x/-form path, and
# in an ordinary shell MSYS converts every one of them correctly. Asserting the
# allow here is asserting the design decision, not an incidental behavior.

# --- 6. PowerShell surface ---------------------------------------------------
# PowerShell has no `export`, but an agent can invoke bash from it.
run_win_pwsh "PowerShell wrapping bash -c with an export (blocked)" \
  "bash -c 'export MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x'" 2
run_win_pwsh "ordinary PowerShell (allowed)" 'Get-ChildItem <repo-root>' 0

# --- 7. Fail-closed inputs ---------------------------------------------------
run_win "over-length command naming the variable fails closed" \
  "export MSYS_NO_PATHCONV=1; echo $(printf 'x%.0s' {1..17000})" 2

rc=0
env OSTYPE=msys bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

rc=0
env OSTYPE=msys bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

# --- 8. Kill switch ----------------------------------------------------------
rc=0
env OSTYPE=msys CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED=false \
  bash "$HOOK" <<<"$(command_json 'export MSYS_NO_PATHCONV=1; git status')" >/dev/null 2>&1 || rc=$?
assert_exit "kill switch disables the guard" 0 "$rc"

report
