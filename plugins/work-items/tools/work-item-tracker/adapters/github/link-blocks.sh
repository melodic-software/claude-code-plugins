#!/usr/bin/env bash
# link-blocks <id> --blocked-by <id> — CONTRACT.md "Verbs (core public surface)".
# Cross-repo edges supported (blocker URL form). Provider ceilings map to exit 7.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: link-blocks <id> --blocked-by <id>" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: link-blocks <id> --blocked-by <id>"
shift
blocker=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocked-by)
      [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
      blocker="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$blocker" ]] || wit_usage_error "--blocked-by is required"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"
wit_require_github_id "$blocker" || wit_usage_error "malformed or non-github --blocked-by id: $blocker"
blocker_url="$(wit_issue_url "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")"

wit_run_gh write issue edit "$number" -R "$owner/$repo" --add-blocked-by "$blocker_url"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg blocker "$blocker" \
  '{schema_version: $sv, id: $id, blocked_by: $blocker, linked: true}'
