#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates with
# explicit pagination: fetches up to limits.list_items_max from capabilities.json
# (gh's own default silently truncates at 30). One row past the ceiling is requested
# so the envelope's `truncated` flag is exact rather than inferred from a full page.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <owner>/<repo>] [--label <name>]" "$@"

state="open" repo_override="" label_args=()
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
  # Filtered by GitHub, so the ceiling counts only items carrying the label.
  --label)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--label needs a value"
    label_args=(--label "$2")
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

wit_run_gh read issue list -R "$target_repo" --state "$state" "${label_args[@]+"${label_args[@]}"}" \
  --limit "$((limit + 1))" --json number,title,state,assignees,labels,issueType,blockedBy,url,createdAt

wit_gh_load_wont_do_labels
printf '%s' "$WIT_GH_OUT" | wit_gh_annotate_blocker_reasons |
  jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$target_repo" --argjson limit "$limit" \
    "{schema_version: \$sv, items: [.[:\$limit][] | $WIT_ITEM_JQ], truncated: (length > \$limit)}"
