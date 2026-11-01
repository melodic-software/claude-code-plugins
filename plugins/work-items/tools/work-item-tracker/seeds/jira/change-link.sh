#!/usr/bin/env bash
# change-link — CONTRACT.md "Change links". Offline: no request is made. Jira links a
# branch, commit or pull request by the capitalized issue key and documents no closing
# keyword, so merging closes nothing (closes: null) and the link is the key itself.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: change-link (<id> | --branch-ref <KEY-N>)  (id: jira:<site>/<PROJECTKEY>#<number>)" "$@"

wit_change_link_args "$@"
if [[ -n "$WIT_CL_REF" ]]; then
  [[ "$WIT_CL_REF" =~ ^([A-Z][A-Z0-9_]*)-([0-9]+)$ ]] ||
    wit_change_link_no_item "branch ref '$WIT_CL_REF' is not a Jira issue key (PROJECTKEY-number)"
  project="${BASH_REMATCH[1]}" number="${BASH_REMATCH[2]}"
  # The site comes from the binding, and the binding's project_keys is the declared
  # scope: a key from an undeclared project is not this binding's item.
  wit_need_jira_config
  wit_jira_project_in_scope "$project" ||
    wit_change_link_no_item "project '$project' is not in the binding's config.jira.project_keys (declared read scope)"
  WIT_CL_ID="jira:$WIT_JIRA_SITE/$project#$number"
fi
wit_require_jira_id "$WIT_CL_ID" ||
  wit_usage_error "malformed or non-jira id: $WIT_CL_ID (expected jira:<site>/<PROJECTKEY>#<number>)"

key="$WIT_ID_REPO-$WIT_ID_NUMBER"
wit_emit_change_link "$WIT_CL_ID" "" "Refs: $key" "$key"
