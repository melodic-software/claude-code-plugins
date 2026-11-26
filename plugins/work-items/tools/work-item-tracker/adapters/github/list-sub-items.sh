#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-sub-items <parent-id> [--state open|closed|all]" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: list-sub-items <parent-id> [--state open|closed|all]"
shift
state="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    state="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
case "$state" in
open | closed | all) ;;
*) wit_usage_error "--state must be open|closed|all (got: $state)" ;;
esac
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"
target_repo="$WIT_ID_OWNER/$WIT_ID_REPO"

wit_require_graphql_session "list-sub-items"
wit_run_gh read issue view "$WIT_ID_NUMBER" -R "$target_repo" --json subIssues
scoped="$(jq -c --arg repo "$target_repo" '
  def node_repo:
    (.repository.nameWithOwner? // null)
    // (((.url // "") | split("/")) as $seg
        | if ($seg | length) >= 5 and $seg[-2] == "issues"
          then ($seg[-4:-2] | join("/"))
          else null
          end);
  ($repo | ascii_downcase) as $want
  | [(.subIssues.nodes // [])[] | {n: .number, r: node_repo}] as $nodes
  | {
      nums: [$nodes[] | select(.r != null and (.r | ascii_downcase) == $want) | .n],
      unattributed: [$nodes[] | select(.r == null) | (.n // "?") | tostring]
    }
' <<<"$WIT_GH_OUT")"
child_nums="$(jq -c '.nums' <<<"$scoped")"

unattributed="$(jq -r '.unattributed | join(", ")' <<<"$scoped")"
if [[ -n "$unattributed" ]]; then
  printf '%s: dropped subIssues node(s) with no derivable repo (number: %s); neither repository.nameWithOwner nor the node url parsed, so the subIssues projection may have changed (#3825)\n' \
    "$(basename "${BASH_SOURCE[0]}")" "$unattributed" >&2
fi

if [[ "$child_nums" == "[]" ]]; then
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: [], truncated: false}'
  exit 0
fi

items_env="$(bash "$WIT_GH_ADAPTER_DIR/list-items.sh" --state "$state" --repo "$target_repo")" || exit "$?"
jq -c --argjson nums "$child_nums" --arg pid "$id" '{
  schema_version: .schema_version,
  items: [
    .items[]
    | select((.id | split("#")[-1] | tonumber) as $n | $nums | index($n))
    | .parent_id = $pid
  ],
  truncated: .truncated
}' <<<"$items_env"
