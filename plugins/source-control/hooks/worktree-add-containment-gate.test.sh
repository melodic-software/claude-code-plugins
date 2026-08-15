#!/usr/bin/env bash
# Regression tests for worktree-add-containment-gate.sh (PreToolUse Bash hook,
# #2611). Black-box: feed the hook real PreToolUse payloads against throwaway
# git fixtures and assert allow (exit 0) / block (exit 2) plus the block
# message's contents. Invoked from an UNRELATED cwd so any reliance on the test
# runner's working directory (instead of the payload's own `cwd`) would
# surface. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/worktree-add-containment-gate.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available (the hook itself fails open without it)"

TEST_TMPDIR="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR" "$UNRELATED"' EXIT

mkrepo() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  git -C "$repo" init -q -b main >/dev/null 2>&1
  printf '%s' "$repo"
}

REPO="$(mkrepo)"
EXT="$TEST_TMPDIR/external"
mkdir -p "$EXT"

# run <cwd> <command> [env pairs...] — one hook invocation; sets RC and ERR.
# The payload is built with jq so a command containing quotes survives intact,
# and env pairs prefix the hook process only. Every locating override is
# cleared first: the hook must judge the payload, not this harness's plugin
# environment.
RC=0
ERR=""
run() {
  local cwd="$1" cmd="$2"
  shift 2
  local payload
  if [[ -n "$cwd" ]]; then
    payload=$(jq -n --arg cwd "$cwd" --arg cmd "$cmd" \
      '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}')
  else
    payload=$(jq -n --arg cmd "$cmd" \
      '{session_id:"test",tool_name:"Bash",tool_input:{command:$cmd}}')
  fi
  ERR=$(cd "$UNRELATED" && printf '%s' "$payload" |
    env -u CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT -u CLAUDE_PLUGIN_DATA \
      -u CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CONTAINMENT_GATE_ENABLED \
      "$@" bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
}

assert_allow() {
  local label="$1" cwd="$2" cmd="$3"
  shift 3
  run "$cwd" "$cmd" "$@"
  assert_exit "$label" 0 "$RC"
}
assert_block() {
  local label="$1" cwd="$2" cmd="$3"
  shift 3
  run "$cwd" "$cmd" "$@"
  assert_exit "$label" 2 "$RC"
}

# --- Scope: commands the hook must never touch --------------------------------

assert_allow "a non-git command passes" "$REPO" "echo hello"
assert_allow "a git command that is not worktree passes" "$REPO" "git status"
assert_allow "git worktree list passes (not add)" "$REPO" "git worktree list"
assert_allow "git worktree remove passes (not add)" "$REPO" "git worktree remove wt"
# The pre-filter must not be fooled by the words appearing outside a git call.
assert_allow "echo naming git worktree add is not a git call" "$REPO" \
  "echo git worktree add $REPO/wt"

# --- The core verdicts ---------------------------------------------------------

assert_allow "an external absolute target passes silently" "$REPO" \
  "git worktree add $EXT/wt-ok -b feat/ok"
run "$REPO" "git worktree add $EXT/wt-quiet -b feat/quiet"
assert_silent "a conforming target produces no advisory (anti-noise, #2611)" "$ERR"

assert_block "an absolute target inside the repo blocks" "$REPO" \
  "git worktree add $REPO/wt-nested"
assert_block "a relative target resolves against the payload cwd and blocks" "$REPO" \
  "git worktree add wt-rel"
assert_allow "a relative target with NO payload cwd passes (unresolvable)" "" \
  "git worktree add wt-nobase"
assert_block "a target under .git blocks as a git directory" "$REPO" \
  "git worktree add $REPO/.git/wt-in-gitdir"

BARE="$TEST_TMPDIR/bare.git"
git init -q --bare "$BARE" >/dev/null 2>&1
assert_block "a target inside a bare repository blocks" "$UNRELATED" \
  "git worktree add $BARE/wt-in-bare"

# `..` after a nonexistent component resolves lexically INTO the repo; the
# nearest-existing-ancestor walk alone would stop at the missing component and
# miss it (same hazard the creation helper documents).
assert_block "'..' after a nonexistent component still blocks" "$UNRELATED" \
  "git worktree add $TEST_TMPDIR/nope/../${REPO##*/}/wt-dotdot"

# --- Base composition: -C, wrapper chdirs, segments ----------------------------

assert_block "git -C <repo> with a relative target blocks" "$UNRELATED" \
  "git -C $REPO worktree add wt-dash-c"
assert_allow "git -C <repo> with an external absolute target passes" "$REPO" \
  "git -C $REPO worktree add $EXT/wt-dash-c-ok"
assert_block "cumulative -C hops compose (git -C a -C b)" "$UNRELATED" \
  "git -C $TEST_TMPDIR -C ${REPO##*/} worktree add wt-two-hops"
assert_block "env -C <repo> wrapper chdir composes into the base" "$UNRELATED" \
  "env -C $REPO git worktree add wt-env-c"
assert_block "a later && segment is still judged" "$REPO" \
  "git status && git worktree add wt-seg"

# --- Fail-open: what the hook cannot resolve statically must pass --------------

# shellcheck disable=SC2016  # unexpanded expansions ARE the fixture
assert_allow "a \$VAR target is dynamic — allow" "$REPO" \
  'git worktree add $WT_DIR/wt'
# shellcheck disable=SC2016
assert_allow "a command-substitution target is dynamic — allow" "$REPO" \
  'git worktree add $(mktemp -d)/wt'
# shellcheck disable=SC2016
assert_allow "a dynamic -C value poisons the base — allow" "$REPO" \
  'git -C $SOMEWHERE worktree add wt'
assert_allow "a segment after cd is unjudgeable — allow" "$REPO" \
  "cd $TEST_TMPDIR && git worktree add wt-after-cd"
assert_allow "pushd relocates like cd — allow" "$REPO" \
  "pushd $TEST_TMPDIR && git worktree add wt-after-pushd"

# --- Option walking on `git worktree add` itself --------------------------------

assert_block "-b <branch> is consumed; the path after it is the target" "$REPO" \
  "git worktree add -b feat/x $REPO/wt-after-b"
assert_allow "-b <branch> with an external target passes" "$REPO" \
  "git worktree add -b feat/x $EXT/wt-after-b-ok"
assert_block "boolean options are stepped over" "$REPO" \
  "git worktree add --detach --quiet $REPO/wt-bools"
assert_block "-- ends option parsing; the next word is the target" "$REPO" \
  "git worktree add -- $REPO/wt-ddash"

# --- The block message ----------------------------------------------------------

run "$REPO" "git worktree add $REPO/wt-msg"
assert_contains "the block message names the resolved target" "$ERR" "$REPO/wt-msg"
assert_contains "the block message names what encloses it" "$ERR" "inside:"
assert_contains "the block message points at the skill alternative" "$ERR" "worktree create"
assert_contains "the block message names its kill switch" "$ERR" "worktree_add_containment_gate_enabled"
assert_contains "with nothing configured, the remedy is the git config key" "$ERR" \
  "git config --global melodic.worktreeroot"

# When the target repository carries melodic.worktreeroot, the message names
# that root — most specific first, same precedence as the creation helper.
KEYREPO="$(mkrepo)"
git -C "$KEYREPO" config melodic.worktreeroot "$TEST_TMPDIR/key-root"
run "$KEYREPO" "git worktree add $KEYREPO/wt-keyed"
assert_exit "a keyed repo still blocks the nested target" 2 "$RC"
assert_contains "the message names the git-key root" "$ERR" "$TEST_TMPDIR/key-root"

# The plugin option backs the message only when the key is absent.
run "$REPO" "git worktree add $REPO/wt-opt" \
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$TEST_TMPDIR/option-root"
assert_contains "absent the key, the message names the plugin-option root" "$ERR" \
  "$TEST_TMPDIR/option-root"
run "$KEYREPO" "git worktree add $KEYREPO/wt-keybeatsopt" \
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$TEST_TMPDIR/option-root"
assert_contains "the key outranks the plugin option in the message" "$ERR" \
  "$TEST_TMPDIR/key-root"
assert_not_contains "the outranked option root is not the named remedy" "$ERR" \
  "$TEST_TMPDIR/option-root"

# An unexpanded placeholder is an unset value, not a root to recommend.
# shellcheck disable=SC2016
run "$REPO" "git worktree add $REPO/wt-token" \
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT='${user_config.worktree_root}'
assert_exit "an unexpanded option placeholder still blocks" 2 "$RC"
assert_not_contains "an unexpanded placeholder is never recommended as the root" "$ERR" \
  'user_config'

# --- Kill switch ----------------------------------------------------------------

assert_allow "disabled by the kill switch, a nested target passes" "$REPO" \
  "git worktree add $REPO/wt-disabled" \
  CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CONTAINMENT_GATE_ENABLED=false

# --- Nothing was ever created: the hook only judges, git never ran --------------

assert_file_absent "no worktree materialized by any blocked case" "$REPO/wt-nested/.git"

[[ $FAILED -eq 0 ]] || exit 1
