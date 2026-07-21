#!/usr/bin/env bash
# get-item <id> — CONTRACT.md "Verbs (core public surface)". Read-only. Fetches one
# Jira issue via GET /rest/api/3/issue/{key} and emits the normalized item object.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: get-item <id>  (id: jira:<site>/<PROJECTKEY>#<number>)" "$@"

id="${1:-}"
[[ -n "$id" && $# -eq 1 ]] || wit_usage_error "usage: get-item <id>"
wit_require_jira_id "$id" ||
  wit_usage_error "malformed or non-jira id: $id (expected jira:<site>/<PROJECTKEY>#<number>)"

wit_need_jira_config
# The id's site (owner segment) must match the bound site: this adapter holds one
# site's credentials, so a cross-site id cannot be served. Reject loudly rather than
# authenticate the wrong instance.
[[ "$WIT_ID_OWNER" == "$WIT_JIRA_SITE" ]] ||
  wit_usage_error "id site '$WIT_ID_OWNER' does not match bound config.jira.site '$WIT_JIRA_SITE'"

# The id grammar's repo group is broader than a Jira project key; reject a
# non-conforming key up front (exit 2) rather than reconstruct a native key the
# normalizer's parser cannot split (which would surface as an opaque exit 5).
[[ "$WIT_ID_REPO" =~ $WIT_JIRA_PROJECT_KEY_RE ]] ||
  wit_usage_error "project key '$WIT_ID_REPO' is outside the allowed charset ($WIT_JIRA_PROJECT_KEY_RE)"

# Reconstruct the native Jira key (PROJECTKEY-number) from the qualified id parts.
key="$WIT_ID_REPO-$WIT_ID_NUMBER"

wit_jira_http GET "/issue/$key?fields=$WIT_JIRA_FIELDS"
wit_jira_require_ok "get-item $id"

printf '%s\n' "$WIT_JIRA_BODY" | jq -c \
  --arg sv "$WIT_SCHEMA_VERSION" --arg site "$WIT_JIRA_SITE" \
  --argjson dk "$WIT_JIRA_DONE_KEYS" --arg blk "$WIT_JIRA_BLOCKED_BY_LINK_TYPE" \
  "$WIT_JIRA_NORMALIZE_PROGRAM"
