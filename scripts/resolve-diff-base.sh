#!/usr/bin/env bash
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
  echo "::notice::Diff base: ${base:0:9}, the merge group's base."
  echo "ref=$base" >>"$output"
  ;;
*)
  whole "A $event run has no diff base"
  ;;
esac
exit 0
