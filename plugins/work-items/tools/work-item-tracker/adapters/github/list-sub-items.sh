#!/usr/bin/env bash
# list-sub-items <parent-id> [--state open|closed|all] — adapter contract
# (CONTRACT.md "Adapter contract"). Enumerates a container's DIRECT children as
# full normalized item objects (same envelope as list-items), each with
# parent_id set to the container. Raw enumeration: it does NOT drop closed or
# nested-container children — the closed-children invariant and sub-map
# traversal both need them (frontier filtering is a separate core-side step).
#
# GitHub carries native sub-issues but its list surface omits parent linkage
# (CONTRACT.md "JSON output contract"), so children cannot be found by filtering
# list-items rows. Two reads instead: the parent's native subIssues connection
# yields the child NUMBERS, then the adapter's own list-items output is filtered
# to that set (reusing its exact normalized projection) and re-parented. Same
# repo only: subIssues nodes in another repo are dropped (the intersect is
# number-keyed against this repo's list). Truncation bound is list-items' own
# (limits.list_items_max) — safe while sub_items_per_parent <= list_items_max.
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

# Native child numbers, scoped to the parent's own repo (a cross-repo sub-issue's
# number would collide with an unrelated same-numbered issue in this repo).
#
# The same-repo test reads the node's `url`, not `repository.nameWithOwner`. gh's
# GraphQL query does request `repository{nameWithOwner}`, but its `--json
# subIssues` projection drops it again, emitting only id/number/title/url/state
# (checked in gh's export path, 2.94.0 through 2.98.0). Selecting on the absent
# field matched nothing, so every container read as childless (#3825). A node's
# `url` is `<host>/<owner>/<repo>/issues/<n>`, so owner/repo are the two path
# segments before `issues`. `repository.nameWithOwner` still wins where a gh
# build does emit it; a node attributable to neither repo is dropped, as before.
#
# Two different drops, only one of them expected. A node resolving to ANOTHER
# repo is out of scope for this number-keyed intersect and stays silent
# (CONTRACT.md "Adapter contract": a documented truncation, not an error). A node
# resolving to NO repo means neither field parsed — the shape #3825 was, where a
# projection change blinds the verb with an empty list and no signal. That case
# gets a one-line stderr note so the next projection change is visible instead of
# silent. It cannot fire on well-formed input: every node gh emits carries a
# `url`. stdout stays the machine-parseable envelope either way.
wit_run_gh read issue view "$WIT_ID_NUMBER" -R "$target_repo" --json subIssues
scoped="$(jq -c --arg repo "$target_repo" '
  def node_repo:
    (.repository.nameWithOwner? // null)
    // (((.url // "") | split("/")) as $seg
        | if ($seg | length) >= 5 and $seg[-2] == "issues"
          then ($seg[-4:-2] | join("/"))
          else null
          end);
  [(.subIssues.nodes // [])[] | {n: .number, r: node_repo}] as $nodes
  | {
      nums: [$nodes[] | select(.r == $repo) | .n],
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
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: []}'
  exit 0
fi

# Reuse list-items' normalized envelope, then keep only the child rows and stamp
# the known parent (list rows carry parent_id: null — GitHub omits it in bulk).
# $() swallows the sibling's exit-on-error; propagate its code.
items_env="$(bash "$WIT_GH_ADAPTER_DIR/list-items.sh" --state "$state" --repo "$target_repo")" || exit "$?"
jq -c --argjson nums "$child_nums" --arg pid "$id" '{
  schema_version: .schema_version,
  items: [
    .items[]
    | select((.id | split("#")[-1] | tonumber) as $n | $nums | index($n))
    | .parent_id = $pid
  ]
}' <<<"$items_env"
