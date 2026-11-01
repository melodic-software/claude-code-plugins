#!/usr/bin/env bash
# add-sub-item — Linear adapter. Links an existing issue as a child of --parent.
#
# Linear's parent link is native and single-valued (`Issue.parent`), so this is an
# issueUpdate setting parentId — and re-parenting an issue that already has a parent
# MOVES it rather than adding a second edge. That is the provider's own model, not a
# lossy approximation, but it is worth knowing before batch-linking.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "JSON output contract".
#
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: add-sub-item.sh <id> --parent <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
PARENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --parent)
    [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
    PARENT="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"
[[ -n "$PARENT" ]] || wit_usage_error "--parent is required"
wit_require_linear_id "$PARENT" || wit_usage_error "not a linear item id: $PARENT"
[[ "$ID" != "$PARENT" ]] || wit_usage_error "an item cannot be its own parent: $ID"

wit_need_linear_config

wit_linear_require_scoped_id "$ID"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
CHILD_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"
# The child's own identifier, captured BEFORE the parent is resolved — resolving the
# parent overwrites the WIT_ID_* and WIT_LINEAR_TEAM globals, and comparing against
# those afterwards compares the parent to itself, which never matches.
CHILD_IDENTIFIER="$WIT_LINEAR_TEAM-$WIT_ID_NUMBER"

wit_linear_require_scoped_id "$PARENT"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
PARENT_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"
# A parent that is already this child's child would make a cycle. Linear rejects the
# direct case, but catching the immediate one here gives a message about the request
# rather than about the provider's error text.
[[ "$(jq -r '.parent.identifier // ""' <<<"$WIT_LINEAR_ISSUE")" != "$CHILD_IDENTIFIER" ]] ||
  wit_usage_error "linking $ID under $PARENT would create a parent cycle: $PARENT is already a child of $ID"

wit_linear_gql \
  'mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }' \
  "$(jq -cn --arg id "$CHILD_UUID" --arg p "$PARENT_UUID" '{id: $id, input: {parentId: $p}}')" \
  "linking $ID under $PARENT"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --arg p "$PARENT" \
  '{schema_version: $sv, id: $id, parent_id: $p, linked: true}'
