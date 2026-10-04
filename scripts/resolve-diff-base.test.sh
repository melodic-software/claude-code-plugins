#!/usr/bin/env bash
# Unit tests for resolve-diff-base.sh: the ref it writes to GITHUB_OUTPUT per
# event, and the reason it logs.
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/resolve-diff-base.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# resolve <event>: run the script; OUT is what it printed, REF the ref it wrote
# (empty for the whole tree), RC its exit status.
resolve() {
  local gho="$TMP_ROOT/gho"
  : >"$gho"
  RC=0
  OUT="$(env GITHUB_OUTPUT="$gho" GITHUB_EVENT_NAME="$1" BASE_REF=main bash "$SCRIPT" 2>&1)" || RC=$?
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
resolve schedule
expect "a schedule run tests the whole tree" "" "A schedule run has no diff base; this schedule run tests the whole tree."
resolve workflow_dispatch
expect "a dispatch run tests the whole tree" "" "this workflow_dispatch run tests the whole tree."
resolve merge_group
expect "a merge-group run tests the whole tree" "" "this merge_group run tests the whole tree."

test_harness::report
