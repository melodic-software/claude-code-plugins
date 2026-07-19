#!/usr/bin/env bash
# add-sub-item <id> --parent <id> — CONTRACT.md "Verbs (core public surface)".
# Provider ceilings (100 sub-items/parent, 8 levels) map to exit 7.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: add-sub-item <id> --parent <id>" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: add-sub-item <id> --parent <id>"
shift
parent=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent)
      [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
      parent="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$parent" ]] || wit_usage_error "--parent is required"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"
wit_require_github_id "$parent" || wit_usage_error "malformed or non-github --parent id: $parent"
parent_url="$(wit_issue_url "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")"

wit_run_gh write issue edit "$number" -R "$owner/$repo" --parent "$parent_url"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg parent "$parent" \
  '{schema_version: $sv, id: $id, parent_id: $parent, linked: true}'
