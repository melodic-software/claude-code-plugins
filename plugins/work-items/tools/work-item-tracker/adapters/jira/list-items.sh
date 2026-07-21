#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates with
# explicit pagination: pages POST /rest/api/3/search/jql via nextPageToken up to
# limits.list_items_max (never a client default). JQL scope is the binding's
# project_keys; --repo <site>/<PROJECTKEY> narrows to one project.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <site>/<PROJECTKEY>]" "$@"

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

wit_need_jira_config

# Project scope: a --repo override (site/PROJECTKEY) narrows to one project after
# validating its site against the bound site AND its key against the JQL-token
# allowlist (a bad --repo key is a usage error, exit 2); otherwise scope is all
# configured project_keys, already allowlist-validated by wit_need_jira_config. Every
# value reaching the JQL builders below is therefore charset-checked first — the
# builders assemble JQL by string concatenation, so this is what keeps it injection-safe.
if [[ -n "$repo_override" ]]; then
  repo_site="${repo_override%%/*}"
  repo_project="${repo_override#*/}"
  [[ "$repo_site" == "$WIT_JIRA_SITE" && "$repo_project" != "$repo_override" && -n "$repo_project" ]] ||
    wit_usage_error "--repo must be <site>/<PROJECTKEY> with site matching config.jira.site '$WIT_JIRA_SITE'"
  [[ "$repo_project" =~ $WIT_JIRA_PROJECT_KEY_RE ]] ||
    wit_usage_error "--repo project key '$repo_project' is outside the allowed charset ($WIT_JIRA_PROJECT_KEY_RE)"
  # --repo may only narrow WITHIN the declared scope, never widen to an undeclared
  # project the token can see (config.jira.project_keys is the read boundary).
  wit_jira_project_in_scope "$repo_project" ||
    wit_usage_error "--repo project '$repo_project' is not in the binding's config.jira.project_keys (declared read scope)"
  projects_json="$(jq -cn --arg p "$repo_project" '[$p]')"
else
  projects_json="$WIT_JIRA_PROJECT_KEYS"
fi

# statusCategory scope mirrors the state cut in the normalizer: open == not a
# done-category, closed == a done-category, all == unconstrained. The done keys are
# the configurable done-key set (override seam), allowlist-validated at config load; JQL
# matches them via `statusCategory in`.
case "$state" in
open) status_clause=" AND statusCategory not in ($(jq -r 'map("\"\(.)\"") | join(",")' <<<"$WIT_JIRA_DONE_KEYS"))" ;;
closed) status_clause=" AND statusCategory in ($(jq -r 'map("\"\(.)\"") | join(",")' <<<"$WIT_JIRA_DONE_KEYS"))" ;;
all) status_clause="" ;;
*) wit_usage_error "internal: unexpected --state '$state'" ;; # pre-validated above; defensive guard
esac
projects_clause="project in ($(jq -r 'map("\"\(.)\"") | join(",")' <<<"$projects_json"))"
jql="$projects_clause$status_clause ORDER BY created ASC"

limit="$(jq -r '.limits.list_items_max' "$WIT_JIRA_ADAPTER_DIR/capabilities.json")"
fields_json="$(jq -cn --arg f "$WIT_JIRA_FIELDS" '$f | split(",")')"

# Page via nextPageToken until the store is exhausted or the ceiling is reached
# (documented truncation, not an error). Each page's issues are normalized and
# accumulated; the ceiling caps total emitted rows across pages.
next_token=""
emitted=0
{
  while ((emitted < limit)); do
    page_size=$((limit - emitted))
    ((page_size > 5000)) && page_size=5000 # /search/jql caps maxResults at 5000/page
    body="$(jq -cn --arg jql "$jql" --argjson fields "$fields_json" \
      --argjson mr "$page_size" --arg tok "$next_token" \
      '{jql: $jql, fields: $fields, maxResults: $mr} + (if $tok == "" then {} else {nextPageToken: $tok} end)')"
    wit_jira_http POST "/search/jql" "$body"
    wit_jira_require_ok "list-items search"
    # A 2xx body that is not an object with an `issues` array (malformed JSON, or an
    # error envelope an intermediary returned with a 200) must fail loudly — otherwise
    # the jq below yields nothing, page_count is empty, the loop breaks, and an empty
    # success envelope is emitted, silently telling list-frontier there is no work.
    [[ "$(jq -r 'if (type == "object" and (.issues | type) == "array") then "ok" else "bad" end' <<<"$WIT_JIRA_BODY" 2>/dev/null)" == "ok" ]] || {
      printf 'jira: list-items search returned a %s response without an issues array\n' "$WIT_JIRA_STATUS" >&2
      exit "$EX_UNAVAILABLE"
    }
    page_count="$(jq -r '.issues | length' <<<"$WIT_JIRA_BODY")"
    jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg site "$WIT_JIRA_SITE" \
      --argjson dk "$WIT_JIRA_DONE_KEYS" --arg blk "$WIT_JIRA_BLOCKED_BY_LINK_TYPE" \
      ".issues[] | $WIT_JIRA_NORMALIZE_PROGRAM" <<<"$WIT_JIRA_BODY"
    emitted=$((emitted + page_count))
    next_token="$(jq -r '.nextPageToken // ""' <<<"$WIT_JIRA_BODY")"
    # Last page: isLast true, or no continuation token, or the API returned nothing.
    [[ "$(jq -r '.isLast // false' <<<"$WIT_JIRA_BODY")" == "true" || -z "$next_token" || "$page_count" == "0" ]] && break
  done
} | jq -c -s --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: .}'
