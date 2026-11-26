#!/usr/bin/env bash
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

wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
PARENT_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

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
SEEN=0
PAGES=0
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
    [[ "$STATE" == all || "$(jq -r '.state' <<<"$ONE")" == "$STATE" ]] || continue
    ITEMS="$(jq -c --argjson one "$ONE" --arg p "$PARENT_ID" \
      '. + [$one + {parent_id: $p}]' <<<"$ITEMS")" || {
      printf 'list-sub-items.sh: could not accumulate a child of %s — refusing to report a partial child list as complete\n' \
        "$PARENT_ID" >&2
      exit "$EX_INTERNAL"
    }
  done < <(jq -c '.nodes[]?' <<<"$PAGE")
  SEEN=$((SEEN + $(jq '(.nodes // []) | length' <<<"$PAGE" 2>/dev/null || echo 0)))
  PAGES=$((PAGES + 1))
  if ((SEEN > WIT_LINEAR_LIST_ITEMS_MAX || PAGES > WIT_LINEAR_LIST_ITEMS_MAX)); then
    printf 'list-sub-items.sh: the children of %s passed the declared ceiling of %s items; refusing to report a partial child list\n' \
      "$PARENT_ID" "$WIT_LINEAR_LIST_ITEMS_MAX" >&2
    exit "$EX_INTERNAL"
  fi
  [[ "$(jq -r '.pageInfo.hasNextPage // false' <<<"$PAGE")" == "true" ]] || break
  CURSOR="$(jq -r '.pageInfo.endCursor // ""' <<<"$PAGE")"
  [[ -n "$CURSOR" ]] || break
done

jq -c --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: ., truncated: false}' <<<"$ITEMS" || {
  printf 'list-sub-items.sh: could not emit the child envelope for %s\n' "$PARENT_ID" >&2
  exit "$EX_INTERNAL"
}
