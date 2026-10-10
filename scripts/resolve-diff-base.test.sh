#!/usr/bin/env bash
# Unit tests for resolve-diff-base.sh: the ref it writes to GITHUB_OUTPUT per
# event, and the reason it logs. The merge-group cases run in a throwaway
# repository with a side branch, so ancestry is real.
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/resolve-diff-base.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

repo="$TMP_ROOT/repo"
mkdir -p "$repo"
git_test_config "$repo" init -q -b main
for i in 1 2; do
  printf '%s\n' "$i" >"$repo/f"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -qm "c$i"
done
BASE="$(git -C "$repo" rev-parse HEAD~1)"
git_test_config "$repo" checkout -q -b side "$BASE"
printf 'side\n' >"$repo/g"
git_test_config "$repo" add -A
git_test_config "$repo" commit -qm side
SIDE="$(git -C "$repo" rev-parse HEAD)"
git_test_config "$repo" checkout -q main

# resolve <event> [merge-group base]: run the script in the repository; OUT is
# what it printed, REF the ref it wrote (empty for the whole tree), RC its exit.
resolve() {
  local gho="$TMP_ROOT/gho"
  : >"$gho"
  RC=0
  OUT="$(cd "$repo" && env GITHUB_OUTPUT="$gho" GITHUB_EVENT_NAME="$1" BASE_REF=main \
    MERGE_GROUP_BASE_SHA="${2:-}" bash "$SCRIPT" 2>&1)" || RC=$?
  REF="$(sed -n 's/^ref=//p' "$gho")"
}

# expect <label> <ref or ""> <text the output must hold>
expect() {
  if [[ "$RC" -eq 0 && "$REF" == "$2" && "$OUT" == *"$3"* ]]; then
    ok "$1"
  else
    fail "$1: expected rc 0, ref '$2' and output holding '$3'; got rc $RC, ref '$REF', output:
$OUT"
  fi
}

resolve pull_request
expect "a pull request diffs against its base branch" "origin/main" ""
resolve merge_group "$BASE"
expect "a merge group diffs against the queue's base" "$BASE" "the merge group's base"
resolve merge_group ""
expect "a merge group with no base SHA tests the whole tree" "" "carries no base SHA; this merge_group run tests the whole tree."
resolve merge_group "$SIDE"
expect "a base that is not an ancestor tests the whole tree" "" "is not an ancestor of HEAD"
resolve merge_group "0000000000000000000000000000000000000000"
expect "a base the clone lacks tests the whole tree" "" "is not an ancestor of HEAD"
resolve schedule
expect "a schedule run tests the whole tree" "" "A schedule run has no diff base; this schedule run tests the whole tree."
resolve workflow_dispatch
expect "a dispatch run tests the whole tree" "" "this workflow_dispatch run tests the whole tree."

# A release bumps plugin manifests, so a group whose diff touches one tests the
# whole tree, whatever else it changes.
# commit_on_main <path>: commit a change to <path> on main.
commit_on_main() {
  mkdir -p "$repo/$(dirname "$1")"
  printf '{"version":"%s"}\n' "$RANDOM" >"$repo/$1"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -qm "touch $1"
}
PRE="$(git -C "$repo" rev-parse HEAD)"
commit_on_main plugins/demo/.claude-plugin/plugin.json
resolve merge_group "$PRE"
expect "a group that bumps a plugin manifest tests the whole tree" "" "plugins/demo/.claude-plugin/plugin.json"
PRE="$(git -C "$repo" rev-parse HEAD)"
commit_on_main .claude-plugin/marketplace.json
resolve merge_group "$PRE"
expect "a group that changes the marketplace manifest tests the whole tree" "" "this merge_group run tests the whole tree."
PRE="$(git -C "$repo" rev-parse HEAD)"
commit_on_main plugins/demo/hooks/hooks.json
resolve merge_group "$PRE"
expect "a group that changes other plugin JSON diffs against the queue's base" "$PRE" "the merge group's base"

test_harness::report
