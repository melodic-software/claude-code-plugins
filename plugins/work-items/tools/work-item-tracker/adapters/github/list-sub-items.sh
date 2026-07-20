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
wit_run_gh read issue view "$WIT_ID_NUMBER" -R "$target_repo" --json subIssues
child_nums="$(printf '%s\n' "$WIT_GH_OUT" |
  jq -c --arg repo "$target_repo" \
    '[(.subIssues.nodes // [])[] | select(.repository.nameWithOwner == $repo) | .number]')"

if [[ "$child_nums" == "[]" ]]; then
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: []}'
  exit 0
fi

# Reuse list-items' normalized envelope, then keep only the child rows and stamp
# the known parent (list rows carry parent_id: null — GitHub omits it in bulk).
# $() swallows the sibling's exit-on-error; propagate its code.
items_env="$(bash "$WIT_GH_ADAPTER_DIR/list-items.sh" --state "$state" --repo "$target_repo")" || exit "$?"
printf '%s\n' "$items_env" | jq -c --argjson nums "$child_nums" --arg pid "$id" '{
  schema_version: .schema_version,
  items: [
    .items[]
    | select((.id | split("#")[-1] | tonumber) as $n | $nums | index($n))
    | .parent_id = $pid
  ]
}'
