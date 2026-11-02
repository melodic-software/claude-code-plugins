#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates with
# explicit pagination: fetches up to limits.list_items_max from capabilities.json
# (gh's own default silently truncates at 30). One row past the ceiling is requested
# so the envelope's `truncated` flag is exact rather than inferred from a full page.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <owner>/<repo>] [--label <name>]" "$@"

state="open" repo_override="" label_args=() search_cap=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    state="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
    repo_override="$2"
    shift 2
    ;;
  # Filtered by GitHub, so the ceiling counts only items carrying the label. gh serves a
  # labeled list from the search API (cli/cli pkg/cmd/issue/list/list.go, issueList),
  # which returns at most 1000 results, so a labeled read reaching that many cannot
  # prove it is complete and reports truncated.
  --label)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--label needs a value"
    label_args=(--label "$2")
    search_cap=1000
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
case "$state" in
open | closed | all) ;;
*) wit_usage_error "--state must be open|closed|all (got: $state)" ;;
esac

# $() swallows wit_run_gh's exit-on-error; propagate its code (see create-item.sh).
target_repo="$(wit_resolve_repo "$repo_override")" || exit "$?"
limit="$(jq -r '.limits.list_items_max' "$WIT_GH_ADAPTER_DIR/capabilities.json")"
wit_gh_load_wont_do_labels

# A session whose proxy refuses GraphQL reads REST (README "List items"): the issues
# endpoint pages at 100 and returns pull requests, which are dropped. It reads the label
# filter directly, not through search, so no search cap applies. Its
# issue_dependencies_summary counts blockers, so only an item with any (or with no
# summary) costs a blocked_by read, mapped onto the blockedBy nodes WIT_ITEM_JQ reads.
if wit_gh_session_refuses_graphql; then
  # REST splits `labels` on commas; such a label lists unfiltered and the core's exact match filters it.
  rest_label=()
  [[ -n "${label_args[1]:-}" && "${label_args[1]}" != *,* ]] && rest_label=(-f "labels=${label_args[1]}")
  # The accumulators reach jq on stdin, never as an argument: a page of REST issues
  # outgrows the per-argument size limit, and a failed jq exits rather than printing nothing.
  rows='[]' page=1
  while :; do
    wit_run_gh read api -X GET "repos/$target_repo/issues" -f state="$state" -f per_page=100 \
      -f page="$page" "${rest_label[@]+"${rest_label[@]}"}"
    page_len="$(jq 'length' <<<"$WIT_GH_OUT")" || exit "$EX_INTERNAL"
    rows="$(printf '%s\n%s' "$rows" "$WIT_GH_OUT" | jq -cs '.[0] + [.[1][] | select(has("pull_request") | not)
      | {number, title, state, assignees: [(.assignees // [])[] | {login}], labels: [(.labels // [])[] | {name}],
        type: (.type | if . == null then null else {name} end), html_url, created_at, issue_dependencies_summary}]')" ||
      exit "$EX_INTERNAL"
    ((page_len == 100 && $(jq 'length' <<<"$rows") <= limit)) || break
    page=$((page + 1))
  done
  rows="$(jq -c --argjson limit "$limit" '.[:$limit + 1]' <<<"$rows")" || exit "$EX_INTERNAL"
  nodes='{}'
  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    wit_run_gh read api --paginate "repos/$target_repo/issues/$number/dependencies/blocked_by?per_page=100"
    nodes="$(printf '%s\n%s' "$nodes" "$WIT_GH_OUT" | jq -cs --arg n "$number" --argjson wl "$WIT_GH_WONT_DO_LABELS" \
      '.[0] + {($n): [(.[1:] | add // [])[] | {state: (.state | ascii_upcase),
        stateReason: (.state_reason | if . == null then null else ascii_upcase end), reasonRead: true,
        wontDoLabel: any((.labels // [])[]; (if type == "string" then . else .name end | ascii_downcase) as $l
          | any($wl[]; . == $l))}]}')" || exit "$EX_INTERNAL"
  done <<<"$(jq -r --argjson limit "$limit" '.[:$limit][] | select((.issue_dependencies_summary.total_blocked_by // 1) > 0) | .number' <<<"$rows")"
  printf '%s\n%s' "$nodes" "$rows" |
    jq -cs --arg sv "$WIT_SCHEMA_VERSION" --arg or "$target_repo" --argjson limit "$limit" \
      ".[0] as \$nodes | .[1] | {schema_version: \$sv, items: [.[:\$limit][] | {number, title, state, assignees, labels,
        issueType: .type, blockedBy: {nodes: (\$nodes[.number | tostring] // [])}, url: .html_url,
        createdAt: .created_at} | $WIT_ITEM_JQ], truncated: (length > \$limit)}" || exit "$EX_INTERNAL"
  exit 0
fi

wit_run_gh read issue list -R "$target_repo" --state "$state" "${label_args[@]+"${label_args[@]}"}" \
  --limit "$((limit + 1))" --json number,title,state,assignees,labels,issueType,blockedBy,url,createdAt

printf '%s' "$WIT_GH_OUT" | wit_gh_annotate_blocker_reasons |
  jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$target_repo" --argjson limit "$limit" \
    --argjson cap "${search_cap:-null}" \
    "{schema_version: \$sv, items: [.[:\$limit][] | $WIT_ITEM_JQ],
      truncated: (length > \$limit or (\$cap != null and length >= \$cap))}"
