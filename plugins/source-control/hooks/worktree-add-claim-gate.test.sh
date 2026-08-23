#!/usr/bin/env bash
# Regression tests for worktree-add-claim-gate.sh (PostToolUse Bash hook,
# #2882). After a plain `git worktree add`, the hook must lock the new tree
# with a session-distinct reason and must not rewrite a helper-created
# reason. Invoked from an unrelated cwd. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/worktree-add-claim-gate.sh"

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
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m seed
  printf '%s' "$repo"
}

REPO="$(mkrepo)"
EXT="$TEST_TMPDIR/external"
mkdir -p "$EXT"

HELPER_REASON='worktree-create.sh: lane active on testhost since 2026-08-15T08:46:04Z; unlock when the owning lane is done'

RC=0
OUT=""
run() {
  local cwd="$1" cmd="$2" sid="${3:-hook-session}"
  shift 3 || true
  local payload
  payload=$(jq -n --arg cwd "$cwd" --arg cmd "$cmd" --arg sid "$sid" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')
  OUT=$(cd "$UNRELATED" && printf '%s' "$payload" |
    env -u CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_GATE_ENABLED \
      "$@" bash "$HOOK" 2>/dev/null)
  RC=$?
}

# --- Scope: commands the hook must never touch --------------------------------

run "$REPO" "git status" "s-status"
assert_exit "a git command that is not worktree add is a no-op" 0 "$RC"
assert_silent "non-add produces no additionalContext" "$OUT"

# Leave an unlocked decoy; echo must not claim it (review: substring pre-filter).
git -C "$REPO" worktree add -q "$EXT/wt-decoy" -b feat/decoy
run "$REPO" "echo git worktree add $EXT/wt-decoy" "s-echo"
assert_exit "echo naming git worktree add is not a git call" 0 "$RC"
decoy=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-decoy" 'index($0, p)')
assert_not_contains "echo does not lock an existing unclaimed tree" "$decoy" "locked"
assert_silent "echo produces no additionalContext" "$OUT"

# --- After a plain add, the new tree is claimed with the session id -----------

git -C "$REPO" worktree add -q "$EXT/wt-hook" -b feat/hook
run "$REPO" "git worktree add $EXT/wt-hook -b feat/hook" "sess-hook-one"
assert_exit "claim hook exits 0 after a real add" 0 "$RC"
stanza=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-hook" 'index($0, p)')
assert_contains "the hook-locked tree is locked" "$stanza" "locked"
assert_contains "the hook reason names the session" "$stanza" "sess-hook-one"
assert_contains "the hook reason uses the claim prefix" "$stanza" "worktree-claim.sh"
assert_contains "the hook tells the agent it claimed" "$OUT" "claimed unlocked worktree"

# Re-running does not rewrite.
run "$REPO" "git worktree add $EXT/wt-hook -b feat/hook" "sess-hook-two"
assert_exit "second hook pass is still exit 0" 0 "$RC"
stanza2=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-hook" 'index($0, p)')
assert_contains "original session reason survived the second pass" "$stanza2" "sess-hook-one"
assert_not_contains "a later session did not overwrite the reason" "$stanza2" "sess-hook-two"

# --- Helper-created reason is left untouched ----------------------------------

git -C "$REPO" worktree add -q "$EXT/wt-helped" -b feat/helped
git -C "$REPO" worktree lock --reason "$HELPER_REASON" "$EXT/wt-helped"
run "$REPO" "git worktree add $EXT/wt-helped -b feat/helped" "sess-other"
assert_exit "hook does not fail on an already-claimed helper tree" 0 "$RC"
helped=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-helped" 'index($0, p)')
assert_contains "helper reason is still the helper string" "$helped" "$HELPER_REASON"
assert_not_contains "helper reason was not rewritten by the hook" "$helped" "worktree-claim.sh"

# --- Kill switch --------------------------------------------------------------

git -C "$REPO" worktree add -q "$EXT/wt-off" -b feat/off
run "$REPO" "git worktree add $EXT/wt-off -b feat/off" "sess-off" \
  CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_GATE_ENABLED=false
assert_exit "disabled hook exits 0" 0 "$RC"
off=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-off" 'index($0, p)')
assert_not_contains "disabled hook does not lock" "$off" "locked"

# --- Two hook sessions produce different reasons ------------------------------

REPO2="$(mkrepo)"
git -C "$REPO2" worktree add -q "$EXT/wt-a" -b feat/a
run "$REPO2" "git worktree add $EXT/wt-a -b feat/a" "alpha"
git -C "$REPO2" worktree add -q "$EXT/wt-b" -b feat/b
run "$REPO2" "git worktree add $EXT/wt-b -b feat/b" "beta"
sa=$(git -C "$REPO2" worktree list --porcelain | awk -v RS= -v p="wt-a" 'index($0, p)')
sb=$(git -C "$REPO2" worktree list --porcelain | awk -v RS= -v p="wt-b" 'index($0, p)')
assert_contains "first hook session is alpha" "$sa" "session alpha since"
assert_contains "second hook session is beta" "$sb" "session beta since"

# Only the parsed add target is claimed — a sibling unclaimed tree stays
# unlocked so a concurrent session can still claim it.
git -C "$REPO2" worktree add -q "$EXT/wt-keep" -b feat/keep
git -C "$REPO2" worktree add -q "$EXT/wt-take" -b feat/take
run "$REPO2" "git worktree add $EXT/wt-take -b feat/take" "taker"
keep=$(git -C "$REPO2" worktree list --porcelain | awk -v RS= -v p="wt-keep" 'index($0, p)')
take=$(git -C "$REPO2" worktree list --porcelain | awk -v RS= -v p="wt-take" 'index($0, p)')
assert_not_contains "sibling unclaimed tree is not stolen" "$keep" "locked"
assert_contains "parsed add target is claimed" "$take" "taker"

# git -C targets the other repository, not the payload cwd.
REPO_A="$(mkrepo)"
REPO_B="$(mkrepo)"
git -C "$REPO_A" worktree add -q "$EXT/wt-cwd-unclaimed" -b feat/cwd-u
git -C "$REPO_B" worktree add -q "$EXT/wt-dashc" -b feat/dashc
run "$REPO_A" "git -C $REPO_B worktree add $EXT/wt-dashc -b feat/dashc" "dashc-sess"
cwd_u=$(git -C "$REPO_A" worktree list --porcelain | awk -v RS= -v p="wt-cwd-unclaimed" 'index($0, p)')
dashc=$(git -C "$REPO_B" worktree list --porcelain | awk -v RS= -v p="wt-dashc" 'index($0, p)')
assert_not_contains "payload-cwd unclaimed tree is not claimed by git -C" "$cwd_u" "locked"
assert_contains "git -C add target is claimed in the other repo" "$dashc" "dashc-sess"

[[ $FAILED -eq 0 ]] || exit 1
