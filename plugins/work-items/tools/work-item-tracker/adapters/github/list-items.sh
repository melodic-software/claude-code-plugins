#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates with
# explicit pagination: fetches up to limits.list_items_max from capabilities.json
# (gh's own default silently truncates at 30).
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <owner>/<repo>]" "$@"

state="open" repo_override=""
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

wit_run_gh read issue list -R "$target_repo" --state "$state" --limit "$limit" \
  --json number,title,state,assignees,labels,issueType,blockedBy,url

printf '%s\n' "$WIT_GH_OUT" | jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$target_repo" \
  "{schema_version: \$sv, items: [.[] | $WIT_ITEM_JQ]}"
