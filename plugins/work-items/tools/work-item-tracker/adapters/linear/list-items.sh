#!/usr/bin/env bash
# list-items — Linear adapter. Returns RAW candidates in the {items:[…]} envelope.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract", "Exit codes".
#
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: list-items.sh [--state open|closed|all] [--repo <workspace>/<TEAMKEY>]'
wit_help_if_requested "$USAGE" "$@"

STATE="open"
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    STATE="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
case "$STATE" in
open | closed | all) ;;
*) wit_usage_error "--state must be one of: open, closed, all" ;;
esac

wit_need_linear_config

# --repo may only NARROW within the declared scope, never widen to an undeclared team.
# Without it, every declared team is listed — the whole declared scope.
if [[ -n "$REPO" ]]; then
  [[ "$REPO" =~ $WIT_LINEAR_SCOPE_RE ]] ||
    wit_usage_error "--repo must be <workspace>/<TEAMKEY>: $REPO"
  wit_linear_scope_in_scope "$REPO" ||
    wit_usage_error "--repo '$REPO' is not in config.linear.scopes (the declared scope)"
  TEAMS="$(jq -cn --arg r "$REPO" '[$r | split("/")[1]]')"
else
  TEAMS="$(jq -c '[.[] | split("/")[1]]' <<<"$WIT_LINEAR_SCOPES")"
fi

# State filtering happens CORE-SIDE, after normalization, rather than in the GraphQL
# filter. The open/closed split is defined by config.linear.done_state_types, which the
# normalizer already applies — pushing it into the query would mean encoding that same
# classification a second time in a different language, and the two would drift.
QUERY='query($teams: [String!], $first: Int!, $after: String) {
  issues(filter: { team: { key: { in: $teams } } }, first: $first, after: $after) {
    nodes { '"$WIT_LINEAR_ISSUE_FIELDS"' }
    pageInfo { hasNextPage endCursor }
  }
}'

ITEMS='[]'
CURSOR=""
COUNT=0
while :; do
  wit_linear_gql "$QUERY" \
    "$(jq -cn --argjson t "$TEAMS" --argjson f "$WIT_LINEAR_PAGE_SIZE" --arg a "$CURSOR" \
      '{teams: $t, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
    "listing issues"
  PAGE="$(jq -c '.issues // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    ONE="$(wit_linear_normalize "$node")" || {
      printf 'list-items.sh: could not normalize a linear issue\n' >&2
      exit "$EX_INTERNAL"
    }
    KEEP="$(jq -r --arg s "$STATE" 'if $s == "all" or .state == $s then "yes" else "no" end' <<<"$ONE")"
    [[ "$KEEP" == "yes" ]] || continue
    ITEMS="$(jq -c --argjson acc "$ITEMS" --argjson one "$ONE" '$acc + [$one]' <<<'null')"
  done < <(jq -c '.nodes[]?' <<<"$PAGE")
  COUNT=$((COUNT + $(jq '.nodes | length' <<<"$PAGE")))
  [[ "$(jq -r '.pageInfo.hasNextPage // false' <<<"$PAGE")" == "true" ]] || break
  CURSOR="$(jq -r '.pageInfo.endCursor // ""' <<<"$PAGE")"
  [[ -n "$CURSOR" ]] || break
  # The declared ceiling from capabilities.json. Exceeding it is a DOCUMENTED
  # truncation, not an error — but never a silent one.
  if ((COUNT >= WIT_LINEAR_LIST_ITEMS_MAX)); then
    printf 'list-items.sh: reached the declared ceiling of %s items; results are truncated\n' \
      "$WIT_LINEAR_LIST_ITEMS_MAX" >&2
    break
  fi
done

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --argjson items "$ITEMS" \
  '{schema_version: $sv, items: $items}'
