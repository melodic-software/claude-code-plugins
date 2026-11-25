#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: link-blocks.sh <id> --blocked-by <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
BLOCKED_BY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --blocked-by)
    [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
    BLOCKED_BY="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"
[[ -n "$BLOCKED_BY" ]] || wit_usage_error "--blocked-by is required"
wit_require_linear_id "$BLOCKED_BY" || wit_usage_error "not a linear item id: $BLOCKED_BY"
[[ "$ID" != "$BLOCKED_BY" ]] || wit_usage_error "an item cannot be blocked by itself: $ID"

wit_need_linear_config

wit_linear_require_scoped_id "$ID"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
TARGET_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

wit_linear_require_scoped_id "$BLOCKED_BY"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
BLOCKER_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

wit_linear_gql \
  'mutation($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success } }' \
  "$(jq -cn --arg b "$BLOCKER_UUID" --arg t "$TARGET_UUID" \
    '{input: {issueId: $b, relatedIssueId: $t, type: "blocks"}}')" \
  "linking $ID as blocked by $BLOCKED_BY"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --arg by "$BLOCKED_BY" \
  '{schema_version: $sv, id: $id, blocked_by: $by, linked: true}'
