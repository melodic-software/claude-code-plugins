#!/usr/bin/env bash
# Regression tests for worktree-create-gate.sh (WorktreeCreate hook).
# Black-box: feed the hook a real WorktreeCreate payload against throwaway git
# fixtures and assert on its stdout contract, its placement, and its refusals.
# No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/worktree-create-gate.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if command -v cygpath >/dev/null 2>&1; then
  TEST_TMPDIR_NATIVE="$(cygpath -m "$TEST_TMPDIR")"
else
  TEST_TMPDIR_NATIVE="$TEST_TMPDIR"
fi

mkrepo() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    printf 'seed\n' >"$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm init
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

# payload <name> <cwd> — the exact shape 2.1.224 sends, field order included.
payload() {
  printf '{"session_id":"s1","transcript_path":"t","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' \
    "$2" "$1"
}

# --------------------------------------------------------------------------
# Placement
# --------------------------------------------------------------------------

REPO="$(mkrepo)"
ROOT="$TEST_TMPDIR_NATIVE/external-root"

OUT="$(payload "feat/gate-basic" "$REPO" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>/dev/null)"
STATUS=$?
assert_exit "a configured root creates the worktree" 0 "$STATUS"
assert_contains "the path is under the configured root" "$OUT" "external-root"
assert_eq "stdout is the path and nothing else" "1" "$(printf '%s\n' "$OUT" | grep -c .)"

# The whole point: the worktree is registered, and it is NOT inside the repo.
assert_contains "git registered the worktree at the printed path" \
  "$(git -C "$REPO" worktree list)" "external-root"
assert_not_contains "nothing landed in the in-repo default" \
  "$(git -C "$REPO" worktree list)" ".claude/worktrees"

# --------------------------------------------------------------------------
# Unconfigured root falls back to plugin data, which is still outside the repo
# --------------------------------------------------------------------------

REPO2="$(mkrepo)"
DATA_DIR="$(mktemp -d "$TEST_TMPDIR/dataXXXXXX")"
if command -v cygpath >/dev/null 2>&1; then
  DATA_DIR_NATIVE="$(cygpath -m "$DATA_DIR")"
else
  DATA_DIR_NATIVE="$DATA_DIR"
fi

OUT="$(payload "feat/gate-fallback" "$REPO2" |
  CLAUDE_PLUGIN_DATA="$DATA_DIR_NATIVE" bash "$HOOK" 2>/dev/null)"
assert_contains "an unconfigured root falls back to the plugin data dir" "$OUT" "worktrees"
assert_not_contains "the fallback is not inside the repository" "$OUT" "$(basename "$REPO2")/"

# An unexpanded placeholder is an unset value, not a directory name.
REPO3="$(mkrepo)"
OUT="$(payload "feat/gate-token" "$REPO3" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT='${user_config.worktree_root}' \
    CLAUDE_PLUGIN_DATA="$DATA_DIR_NATIVE" bash "$HOOK" 2>/dev/null)"
assert_not_contains "an unexpanded placeholder is not used as a directory" "$OUT" 'user_config'
assert_contains "an unexpanded placeholder falls through to the data dir" "$OUT" "worktrees"

# --------------------------------------------------------------------------
# Refusals — every one fails the creation rather than falling through
# --------------------------------------------------------------------------

REPO4="$(mkrepo)"
# CLAUDE_PLUGIN_DATA is unset explicitly, not merely left alone: in a general
# subprocess it is NOT scoped to the invoking plugin — this machine's carries an
# unrelated plugin's data directory — so an inherited value would silently satisfy
# the fallback and make this case unfalsifiable. A real hook process gets the
# correctly-scoped value; a test harness does not.
OUT="$(payload "feat/gate-noroot" "$REPO4" | env -u CLAUDE_PLUGIN_DATA bash "$HOOK" 2>/dev/null)"
STATUS=$?
assert_exit "no root and no data dir refuses" 1 "$STATUS"
assert_silent "a refusal prints no path" "$OUT"

OUT="$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate"}' "$REPO4" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>/dev/null)"
STATUS=$?
assert_exit "a payload with no .name refuses rather than guessing" 1 "$STATUS"
assert_silent "a nameless payload prints no path" "$OUT"

# A name git rejects as a branch must fail here, not land a half-made worktree.
REPO5="$(mkrepo)"
OUT="$(payload "feat/bad..name" "$REPO5" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>/dev/null)"
STATUS=$?
assert_exit "an illegal branch name fails the creation" 1 "$STATUS"
assert_silent "an illegal name prints no path" "$OUT"

# --------------------------------------------------------------------------
# Disabled
# --------------------------------------------------------------------------

REPO6="$(mkrepo)"
OUT="$(payload "feat/gate-off" "$REPO6" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED=false \
    CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>/dev/null)"
STATUS=$?
assert_exit "disabled exits 0 so Claude Code uses its own default" 0 "$STATUS"
assert_silent "disabled prints no path — an empty stdout is what yields the default" "$OUT"
assert_eq "disabled creates nothing" "1" \
  "$(git -C "$REPO6" worktree list | grep -c .)"

ERR="$(payload "feat/gate-off" "$REPO6" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED=false \
    CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>&1 >/dev/null)"
assert_contains "disabled says so on stderr, the only channel that cannot corrupt the path" \
  "$ERR" "disabled"

# --------------------------------------------------------------------------
# The payload reader
# --------------------------------------------------------------------------

# Field order must not matter, and the reader must not be defeated by another
# field whose value happens to contain the string it looks for.
REPO7="$(mkrepo)"
OUT="$(printf '{"name":"feat/gate-order","hook_event_name":"WorktreeCreate","cwd":"%s","transcript_path":"x-name-cwd-y"}' "$REPO7" |
  CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT="$ROOT" bash "$HOOK" 2>/dev/null)"
assert_contains "field order does not matter" "$OUT" "gate-order"

[[ $FAILED -eq 0 ]] || exit 1
