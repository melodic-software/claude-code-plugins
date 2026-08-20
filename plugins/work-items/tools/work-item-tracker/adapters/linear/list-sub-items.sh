#!/usr/bin/env bash
# list-sub-items — Linear adapter. RAW enumeration of a container's DIRECT children.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract". Closed children and nested-container children are KEPT: the
# closed-children invariant check and sub-map traversal both need them, and frontier
# filtering is the separate core-side step.
#
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: list-sub-items.sh <parent-id> [--state open|closed|all]'
wit_help_if_requested "$USAGE" "$@"

PARENT_ID="${1:-}"
[[ -n "$PARENT_ID" ]] || wit_usage_error "$USAGE"
shift
STATE="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$PARENT_ID" || wit_usage_error "not a linear item id: $PARENT_ID"
case "$STATE" in
open | closed | all) ;;
*) wit_usage_error "--state must be one of: open, closed, all" ;;
esac

wit_need_linear_config
wit_linear_require_scoped_id "$PARENT_ID"

# The container itself is fetched first so a missing parent is exit 5 rather than an
# empty child list — "no such container" and "a container with no children" are
# different answers, and the second is legitimately an empty array.
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
PARENT_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

# Linear's parent link is native and bidirectional (`Issue.children`), so children are
# read directly rather than intersected with a repo-wide list the way the GitHub adapter
# has to. A child in a team outside the declared scope is still returned: it IS a child
# of this container, and hiding it would make the closed-children invariant check pass
# on a container that still has open work under it.
QUERY='query($id: String!, $first: Int!, $after: String) {
  issue(id: $id) {
    children(first: $first, after: $after) {
      nodes { '"$WIT_LINEAR_ISSUE_FIELDS"' }
      pageInfo { hasNextPage endCursor }
    }
  }
}'

ITEMS='[]'
CURSOR=""
while :; do
  wit_linear_gql "$QUERY" \
    "$(jq -cn --arg id "$PARENT_UUID" --argjson f "$WIT_LINEAR_PAGE_SIZE" --arg a "$CURSOR" \
      '{id: $id, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
    "listing children of $PARENT_ID"
  PAGE="$(jq -c '.issue.children // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    ONE="$(wit_linear_normalize "$node")" || {
      printf 'list-sub-items.sh: could not normalize a child of %s\n' "$PARENT_ID" >&2
      exit "$EX_INTERNAL"
    }
    KEEP="$(jq -r --arg s "$STATE" 'if $s == "all" or .state == $s then "yes" else "no" end' <<<"$ONE")"
    [[ "$KEEP" == "yes" ]] || continue
    # Every child carries the container as parent_id. The normalizer already derives it
    # from the child's own `parent`, but it is forced here so a child whose selection
    # omitted the parent cannot emit a null and break sub-map traversal.
    ITEMS="$(jq -c --argjson acc "$ITEMS" --argjson one "$ONE" --arg p "$PARENT_ID" \
      '$acc + [$one + {parent_id: $p}]' <<<'null')"
  done < <(jq -c '.nodes[]?' <<<"$PAGE")
  [[ "$(jq -r '.pageInfo.hasNextPage // false' <<<"$PAGE")" == "true" ]] || break
  CURSOR="$(jq -r '.pageInfo.endCursor // ""' <<<"$PAGE")"
  [[ -n "$CURSOR" ]] || break
done

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --argjson items "$ITEMS" \
  '{schema_version: $sv, items: $items}'
