#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: get-item <id>  (id: jira:<site>/<PROJECTKEY>#<number>)" "$@"

id="${1:-}"
[[ -n "$id" && $# -eq 1 ]] || wit_usage_error "usage: get-item <id>"
wit_require_jira_id "$id" ||
  wit_usage_error "malformed or non-jira id: $id (expected jira:<site>/<PROJECTKEY>#<number>)"

wit_need_jira_config
[[ "$WIT_ID_OWNER" == "$WIT_JIRA_SITE" ]] ||
  wit_usage_error "id site '$WIT_ID_OWNER' does not match bound config.jira.site '$WIT_JIRA_SITE'"

[[ "$WIT_ID_REPO" =~ $WIT_JIRA_PROJECT_KEY_RE ]] ||
  wit_usage_error "project key '$WIT_ID_REPO' is outside the allowed charset ($WIT_JIRA_PROJECT_KEY_RE)"

wit_jira_project_in_scope "$WIT_ID_REPO" ||
  wit_usage_error "project '$WIT_ID_REPO' is not in the binding's config.jira.project_keys (declared read scope)"

key="$WIT_ID_REPO-$WIT_ID_NUMBER"

wit_jira_http GET "/issue/$key?fields=$WIT_JIRA_FIELDS"
wit_jira_require_ok "get-item $id"
[[ "$(jq -r 'if (type == "object" and (.key | type) == "string") then "ok" else "bad" end' <<<"$WIT_JIRA_BODY" 2>/dev/null)" == "ok" ]] || {
  printf 'get-item: %s response was not a Jira issue object\n' "$WIT_JIRA_STATUS" >&2
  exit "$EX_UNAVAILABLE"
}

res="$(wit_jira_blocker_resolutions <<<"$WIT_JIRA_BODY")"

jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg site "$WIT_JIRA_SITE" \
  --argjson dk "$WIT_JIRA_DONE_KEYS" --arg blk "$WIT_JIRA_BLOCKED_BY_LINK_TYPE" \
  --argjson res "$res" \
  "$WIT_JIRA_NORMALIZE_PROGRAM" <<<"$WIT_JIRA_BODY" || {
  printf 'get-item: %s response could not be normalized (malformed issue key?)\n' "$WIT_JIRA_STATUS" >&2
  exit "$EX_UNAVAILABLE"
}
