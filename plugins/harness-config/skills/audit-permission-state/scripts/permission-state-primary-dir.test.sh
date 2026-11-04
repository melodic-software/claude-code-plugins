#!/usr/bin/env bash
# Where permission-state.sh looks for the two project files, run over real git
# trees with no fixture-root seam. Each expected location is the one the settings
# page gives: the shared file in the session's primary working directory
# (settings#where-claude-code-keeps-the-local-file-in-a-git-repository), the local
# file at the repository root, resolved through a worktree to the main checkout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# The local file stays beside the shared file on Windows; these cases are about
# the repository-root anchor, so they pin a non-Windows platform through the seam.
export PERMISSION_STATE_OSTYPE=linux-gnu

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq and git are required" >&2
  exit 0
fi

# A fixture never inherits the caller's git environment.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

BASE="$(cd "$TEST_TMPDIR" && pwd -P)"
ROOT="$BASE/repo"
mkdir -p "$ROOT/.claude" "$ROOT/sub/.claude" "$ROOT/bare-sub" "$BASE/home" "$BASE/outside/.claude" "$BASE/elsewhere/.claude"
git -C "$ROOT" init -q
git -C "$ROOT" -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -q --allow-empty -m fixture
git -C "$ROOT" worktree add -q "$BASE/wt" -b fixture-wt
mkdir -p "$BASE/wt/.claude"

jq -n '{permissions:{allow:["Bash(root-shared)"]}}' >"$ROOT/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(root-local)"]}}' >"$ROOT/.claude/settings.local.json"
jq -n '{permissions:{allow:["Bash(sub-shared)"]}}' >"$ROOT/sub/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(wt-shared)"]}}' >"$BASE/wt/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(outside-shared)"]}}' >"$BASE/outside/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(elsewhere-shared)"]}}' >"$BASE/elsewhere/.claude/settings.json"

# run_in <dir> [env assignments]: the reader started from <dir>.
run_in() {
  local dir="$1"
  shift
  (
    cd "$dir" || exit 1
    env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_REMOTE -u CLAUDE_PROJECT_DIR -u PERMISSION_STATE_FIXTURE_DIR -u PERMISSION_STATE_STARTDIR \
      HOME="$BASE/home" \
      PERMISSION_STATE_MANAGED_PATH="$BASE/policy/managed-settings.json" \
      PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
      "$@" bash "$SCRIPT"
  )
}

# --- A session at the repository root reads the root's shared file -----------
OUT="$(run_in "$ROOT")"
assert_contains "root session: shared file at the root" "$OUT" "project settings present $ROOT/.claude/settings.json"
assert_contains "root session: its rule is read" "$OUT" "rule project settings allow Bash(root-shared)"

# --- A session in a subdirectory reads that subdirectory's shared file ---------
OUT="$(run_in "$ROOT/sub")"
assert_contains "subdirectory session: shared file in the subdirectory" "$OUT" "project settings present $ROOT/sub/.claude/settings.json"
assert_contains "subdirectory session: its rule is read" "$OUT" "rule project settings allow Bash(sub-shared)"
assert_not_contains "subdirectory session: the root's shared rule is not in effect" "$OUT" "Bash(root-shared)"
# The root is matched by its tail: git spells it differently from the shell on Windows.
assert_eq "subdirectory session: the local file stays at the root" 1 "$(count_matching "$OUT" '^local settings present .*/repo/\.claude/settings\.local\.json$')"
assert_contains "subdirectory session: the local rule is read" "$OUT" "rule local settings allow Bash(root-local)"

# --- With no shared file there, the root's does not stand in for it ------------
OUT="$(run_in "$ROOT/bare-sub")"
assert_contains "no shared file here: reported absent at this directory" "$OUT" "project settings absent $ROOT/bare-sub/.claude/settings.json"
assert_not_contains "no shared file here: the root's rule is not claimed" "$OUT" "Bash(root-shared)"

# --- A worktree session: shared file in the worktree, local at the main checkout
OUT="$(run_in "$BASE/wt")"
assert_contains "worktree session: shared file in the worktree" "$OUT" "project settings present $BASE/wt/.claude/settings.json"
assert_contains "worktree session: its rule is read" "$OUT" "rule project settings allow Bash(wt-shared)"
assert_eq "worktree session: local file at the main checkout" 1 "$(count_matching "$OUT" '^local settings present .*/repo/\.claude/settings\.local\.json$')"
assert_contains "worktree session: the basis line says so" "$OUT" "main checkout, resolved through this worktree"

# --- Outside a repository: the working directory, whatever the environment says
OUT="$(run_in "$BASE/outside" CLAUDE_PROJECT_DIR="$BASE/elsewhere")"
assert_contains "outside a repository: shared file here" "$OUT" "project settings present $BASE/outside/.claude/settings.json"
assert_not_contains "outside a repository: CLAUDE_PROJECT_DIR is not a second input" "$OUT" "Bash(elsewhere-shared)"
assert_contains "outside a repository: the local file sits beside it" "$OUT" "local settings absent $BASE/outside/.claude/settings.local.json"

report_and_exit
