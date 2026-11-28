#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: list-items.sh [--state open|closed|all] [--repo <workspace>/<TEAMKEY>] [--label <name>]'
wit_help_if_requested "$USAGE" "$@"

STATE="open"
REPO=""
LABEL=""
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
  --label)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--label needs a value"
    LABEL="$2"
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

if [[ -n "$REPO" ]]; then
  [[ "$REPO" =~ $WIT_LINEAR_SCOPE_RE ]] ||
    wit_usage_error "--repo must be <workspace>/<TEAMKEY>: $REPO"
  wit_linear_scope_in_scope "$REPO" ||
    wit_usage_error "--repo '$REPO' is not in config.linear.scopes (the declared scope)"
  TEAMS="$(jq -cn --arg r "$REPO" '[$r | split("/")[1]]')"
else
  TEAMS="$(jq -c '[.[] | split("/")[1]]' <<<"$WIT_LINEAR_SCOPES")"
fi

FILTER="$(jq -cn --argjson t "$TEAMS" --arg s "$STATE" --argjson dt "$WIT_LINEAR_DONE_TYPES" --arg l "$LABEL" '
  {team: {key: {in: $t}}}
  + (if $s == "open" then {state: {type: {nin: $dt}}} # spellchecker:disable-line
     elif $s == "closed" then {state: {type: {in: $dt}}}
     else {} end)
  + (if $l == "" then {} else {labels: {some: {name: {eq: $l}}}} end)')"
QUERY='query($filter: IssueFilter!, $first: Int!, $after: String) {
  issues(filter: $filter, first: $first, after: $after) {
    nodes { '"$WIT_LINEAR_ISSUE_FIELDS"' }
    pageInfo { hasNextPage endCursor }
  }
}'

ITEMS='[]'
CURSOR=""
COUNT=0
TRUNCATED=false
while :; do
  FIRST=$((WIT_LINEAR_LIST_ITEMS_MAX + 1 - COUNT))
  ((FIRST > WIT_LINEAR_PAGE_SIZE)) && FIRST="$WIT_LINEAR_PAGE_SIZE"
  wit_linear_gql "$QUERY" \
    "$(jq -cn --argjson filter "$FILTER" --argjson f "$FIRST" --arg a "$CURSOR" \
      '{filter: $filter, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
    "listing issues"
  PAGE="$(jq -c '.issues // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    COUNT=$((COUNT + 1))
    if ((COUNT > WIT_LINEAR_LIST_ITEMS_MAX)); then
      TRUNCATED=true
      break
    fi
    ONE="$(wit_linear_normalize "$node")" || {
      printf 'list-items.sh: could not normalize a linear issue\n' >&2
      exit "$EX_INTERNAL"
    }
    [[ "$STATE" == all || "$(jq -r '.state' <<<"$ONE")" == "$STATE" ]] || continue
    ITEMS="$(jq -c --argjson one "$ONE" '. + [$one]' <<<"$ITEMS")" || {
      printf 'list-items.sh: could not accumulate a normalized issue — refusing to report a partial list as complete\n' >&2
      exit "$EX_INTERNAL"
    }
  done < <(jq -c '.nodes[]?' <<<"$PAGE")
  if [[ "$TRUNCATED" == true ]]; then
    printf 'list-items.sh: reached the declared ceiling of %s items; results are truncated\n' \
      "$WIT_LINEAR_LIST_ITEMS_MAX" >&2
    break
  fi
  [[ "$(jq -r '.pageInfo.hasNextPage // false' <<<"$PAGE")" == "true" ]] || break
  CURSOR="$(jq -r '.pageInfo.endCursor // ""' <<<"$PAGE")"
  [[ -n "$CURSOR" ]] || break
done

jq -c --arg sv "$WIT_SCHEMA_VERSION" --argjson truncated "$TRUNCATED" \
  '{schema_version: $sv, items: ., truncated: $truncated}' <<<"$ITEMS" || {
  printf 'list-items.sh: could not emit the item envelope\n' >&2
  exit "$EX_INTERNAL"
}
