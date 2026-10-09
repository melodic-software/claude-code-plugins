#!/usr/bin/env bash
# Resolve the ref every diff-scoped step of pr-require-checks.yml diffs against,
# for the `select-tests` job's "Resolve the diff base" step.
#
#   scripts/resolve-diff-base.sh
#
# Run from the checkout, with full history. Reads GITHUB_EVENT_NAME, BASE_REF
# and MERGE_GROUP_BASE_SHA; writes `ref=<base>` to $GITHUB_OUTPUT, or nothing
# for the whole tree. Always exits 0: every failure resolves toward the whole
# tree.
#
# - pull_request: origin/$BASE_REF.
# - merge_group: the queue's base, MERGE_GROUP_BASE_SHA
#   (github.event.merge_group.base_sha), so the group's own diff selects what
#   runs, as on its pull request. The whole tree when that commit is missing
#   or is not an ancestor of HEAD, and when the group's diff touches a plugin
#   or marketplace manifest: a release bumps those, and a release tests the
#   whole tree.
# - anything else (schedule, dispatch): the whole tree.
set -uo pipefail

event=${GITHUB_EVENT_NAME:-}
output=${GITHUB_OUTPUT:-/dev/null}

whole() {
  echo "::notice::$1; this $event run tests the whole tree."
  exit 0
}

case "$event" in
pull_request)
  echo "ref=origin/${BASE_REF:-}" >>"$output"
  ;;
merge_group)
  base=${MERGE_GROUP_BASE_SHA:-}
  [[ "$base" =~ ^[0-9a-f]{40}$ ]] || whole "The merge group carries no base SHA"
  git merge-base --is-ancestor "$base" HEAD 2>/dev/null ||
    whole "The merge group's base ${base:0:9} is not an ancestor of HEAD in this clone"
  manifest=$(git diff --name-only "$base" HEAD -- \
    .claude-plugin/marketplace.json 'plugins/*/.claude-plugin/plugin.json' | head -n 1)
  [[ -z "$manifest" ]] ||
    whole "The merge group changes $manifest, as a release does"
  echo "::notice::Diff base: ${base:0:9}, the merge group's base."
  echo "ref=$base" >>"$output"
  ;;
*)
  whole "A $event run has no diff base"
  ;;
esac
exit 0
