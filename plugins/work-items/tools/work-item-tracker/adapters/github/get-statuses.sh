#!/usr/bin/env bash
# get-statuses --field <name> <id>... — CONTRACT.md "Verbs (core public surface)". Read-only.
# Reads each item's value of one single-select issue field (the core passes "Work status"), as
# GraphQL Issue.issueFieldValues answers it: one query per repository per 100 items. An item
# whose field is unset, or that the answer leaves out, reads null.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: get-statuses --field <name> <id>..."
wit_help_if_requested "$usage" "$@"

field="" ids=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --field)
    [[ $# -ge 2 && -n "$2" && -z "$field" ]] || wit_usage_error "--field needs one non-empty value"
    field="$2"
    shift 2
    ;;
  -*) wit_usage_error "unknown argument: $1" ;;
  *)
    wit_require_github_id "$1" || wit_usage_error "not a github item id: $1"
    ids+=("$1")
    shift
    ;;
  esac
done
[[ -n "$field" ]] || wit_usage_error "$usage"
wit_require_graphql_session "get-statuses"

# One JSON object per id: {id, repo, number}, grouped by repository.
rows="$(for id in "${ids[@]+"${ids[@]}"}"; do
  wit_require_github_id "$id"
  jq -nc --arg id "$id" --arg repo "$WIT_ID_OWNER/$WIT_ID_REPO" --argjson n "$WIT_ID_NUMBER" \
    '{id: $id, repo: $repo, number: $n}'
done | jq -sc 'group_by(.repo)')"

statuses='{}'
while IFS= read -r group; do
  [[ -n "$group" ]] || continue
  repo="$(jq -r '.[0].repo' <<<"$group")"
  count="$(jq 'length' <<<"$group")"
  for ((i = 0; i < count; i += 100)); do
    chunk="$(jq -c --argjson i "$i" '.[$i:$i + 100]' <<<"$group")"
    # Aliases are built from validated issue numbers only.
    aliases="$(jq -r 'map("i\(.number): issue(number: \(.number)) { issueFieldValues(first: 25) { nodes { ... on IssueFieldSingleSelectValue { name field { ... on IssueFieldSingleSelect { name } } } } } }") | join(" ")' <<<"$chunk")"
    # shellcheck disable=SC2016  # GraphQL variables, not bash expansions
    wit_run_gh read api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" \
      -f query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { $aliases } }"
    statuses="$(jq -c --argjson acc "$statuses" --argjson chunk "$chunk" --arg f "$field" '
      .data.repository as $r
      | $acc + (reduce $chunk[] as $c ({}; .[$c.id] =
          ([($r["i\($c.number)"].issueFieldValues.nodes // [])[] | select(.field.name? == $f) | .name] | first)))' \
      <<<"$WIT_GH_OUT")" || {
      echo "get-statuses: the field value answer for $repo is not JSON" >&2
      exit "$EX_INTERNAL"
    }
  done
done < <(jq -c '.[]' <<<"$rows")

jq -nc --arg sv "$WIT_SCHEMA_VERSION" --argjson statuses "$statuses" '{schema_version: $sv, statuses: $statuses}'
