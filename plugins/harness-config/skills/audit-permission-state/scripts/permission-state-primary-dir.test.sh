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
mkdir -p "$BASE/wt/.claude" "$BASE/wt/sub"

jq -n '{permissions:{allow:["Bash(root-shared)"],deny:["Bash(root-deny)"]}}' >"$ROOT/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(root-local)"]}}' >"$ROOT/.claude/settings.local.json"
jq -n '{permissions:{allow:["Bash(sub-shared)"],deny:["Bash(sub-deny)"]}}' >"$ROOT/sub/.claude/settings.json"
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
assert_contains "root session: no second file to read" "$OUT" "project toplevel not-applicable -"
assert_eq "root session: the root's rule is reported once" 1 "$(count_matching "$OUT" 'Bash\(root-shared\)')"

# --- Below the root: a session started here and a root session after a Bash cd --
# look the same to the reader (tools-reference, what persists between commands),
# and each reads a different shared file (settings, the shared-file paragraph), so
# both files are reported and neither's deny rules go missing.
OUT="$(run_in "$ROOT/sub")"
assert_contains "below the root: shared file in this directory" "$OUT" "project settings present $ROOT/sub/.claude/settings.json"
assert_contains "below the root: its rule is read" "$OUT" "rule project settings allow Bash(sub-shared)"
assert_contains "below the root: its deny rule is read" "$OUT" "rule project settings deny Bash(sub-deny)"
# The root is matched by its tail: git spells it differently from the shell on Windows.
assert_eq "below the root: the root's shared file is read too" 1 "$(count_matching "$OUT" '^project toplevel present .*/repo/\.claude/settings\.json$')"
assert_contains "below the root: the root's deny rule is not omitted" "$OUT" "rule project toplevel deny Bash(root-deny)"
assert_not_contains "below the root: the root's rule is not filed under this directory" "$OUT" "rule project settings allow Bash(root-shared)"
assert_eq "below the root: a note names this directory and says both were read" 1 "$(count_matching "$OUT" "^NOTE: .*$ROOT/sub.*below the repository root.*reads both")"
assert_eq "subdirectory session: the local file stays at the root" 1 "$(count_matching "$OUT" '^local settings present .*/repo/\.claude/settings\.local\.json$')"
assert_contains "subdirectory session: the local rule is read" "$OUT" "rule local settings allow Bash(root-local)"
MERGED="$(printf '%s\n' "$OUT" | bash "$SCRIPT_DIR/permission-merge.sh" --merge-only)"
assert_contains "below the root: the merge keeps the root's deny" "$MERGED" "precedence_basis=uncontested Bash(root-deny)"
assert_contains "below the root: the merge keeps this directory's deny" "$MERGED" "precedence_basis=uncontested Bash(sub-deny)"

# --- With no shared file here, the root's is still labeled as the root's --------
OUT="$(run_in "$ROOT/bare-sub")"
assert_contains "no shared file here: reported absent at this directory" "$OUT" "project settings absent $ROOT/bare-sub/.claude/settings.json"
assert_contains "no shared file here: the root's deny rule is not omitted" "$OUT" "rule project toplevel deny Bash(root-deny)"
assert_not_contains "no shared file here: the root's rule is not filed under this directory" "$OUT" "rule project settings allow Bash(root-shared)"

# --- A root file that cannot be read makes the merge incomplete, not clean -------
BROKEN="$BASE/broken"
mkdir -p "$BROKEN/.claude" "$BROKEN/sub"
git -C "$BROKEN" init -q
printf '{not json' >"$BROKEN/.claude/settings.json"
OUT="$(run_in "$BROKEN/sub")"
assert_eq "broken root file: reported invalid" 1 "$(count_matching "$OUT" '^project toplevel invalid-json ')"
assert_contains "broken root file: the merge says it is incomplete" "$(printf '%s\n' "$OUT" | bash "$SCRIPT_DIR/permission-merge.sh" --merge-only)" "status=incomplete"

# --- A repository rooted at the home directory: the root file is the user file --
OUT="$(run_in "$ROOT/sub" HOME="$ROOT")"
assert_eq "root is home: the root file is not read as project" 1 "$(count_matching "$OUT" '^project toplevel not-applicable .*/repo/\.claude/settings\.json$')"
assert_contains "root is home: it is read as user" "$OUT" "rule user settings deny Bash(root-deny)"
assert_not_contains "root is home: it is not read twice" "$OUT" "rule project toplevel"

# --- A worktree session: shared file in the worktree, local at the main checkout
OUT="$(run_in "$BASE/wt")"
assert_contains "worktree session: shared file in the worktree" "$OUT" "project settings present $BASE/wt/.claude/settings.json"
assert_contains "worktree session: its rule is read" "$OUT" "rule project settings allow Bash(wt-shared)"
assert_contains "worktree session: no second file to read" "$OUT" "project toplevel not-applicable -"
assert_eq "worktree session: local file at the main checkout" 1 "$(count_matching "$OUT" '^local settings present .*/repo/\.claude/settings\.local\.json$')"
assert_contains "worktree session: the basis line says so" "$OUT" "main checkout, resolved through this worktree"

# --- Below a worktree's root: the worktree's shared file, not the main checkout's
OUT="$(run_in "$BASE/wt/sub")"
assert_contains "below a worktree root: the worktree's rule is read" "$OUT" "rule project toplevel allow Bash(wt-shared)"
assert_not_contains "below a worktree root: the main checkout's shared rule is not" "$OUT" "Bash(root-shared)"

# --- Outside a repository: the working directory, whatever the environment says
OUT="$(run_in "$BASE/outside" CLAUDE_PROJECT_DIR="$BASE/elsewhere")"
assert_contains "outside a repository: shared file here" "$OUT" "project settings present $BASE/outside/.claude/settings.json"
assert_not_contains "outside a repository: CLAUDE_PROJECT_DIR is not a second input" "$OUT" "Bash(elsewhere-shared)"
assert_contains "outside a repository: the local file sits beside it" "$OUT" "local settings absent $BASE/outside/.claude/settings.local.json"
assert_contains "outside a repository: no second file to read" "$OUT" "project toplevel not-applicable -"

report_and_exit
