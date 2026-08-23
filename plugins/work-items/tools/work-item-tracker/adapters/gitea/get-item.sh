#!/usr/bin/env bash
# get-item — Gitea / Forgejo adapter (provider `gitea`).
# Scaffolded by /work-items:onboard-adapter; the provider mapping below is written
# against the Gitea `Issue` struct (modules/structs/issue.go) and the generated swagger
# definition of GET /repos/{owner}/{repo}/issues/{index}.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract", "Exit codes".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: get-item.sh <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
[[ $# -eq 0 ]] || wit_usage_error "unexpected argument: $1"
wit_require_gitea_id "$ID" || wit_usage_error "not a gitea item id: $ID"

wit_need_gitea_config

# The declared scope list is the authorization boundary, not just a filter: a bound
# workflow must not read items from a repository it did not declare, even when the
# token can see them. Enforced BEFORE any request, so the diagnostic names this verb.
SCOPE="$WIT_ID_OWNER/$WIT_ID_REPO"
wit_gitea_scope_in_scope "$SCOPE" ||
  wit_usage_error "$SCOPE is not in config.gitea.scopes (the declared read scope)"

wit_gitea_http GET "/repos/$WIT_ID_OWNER/$WIT_ID_REPO/issues/$WIT_ID_NUMBER"
wit_gitea_require_ok "fetching $ID"

# Gitea's Issue carries no dependency data, so the open-blocker count is a second
# request. get-item is the authoritative read, so it pays that cost rather than
# reporting a count it did not compute.
#
# That helper exits on transport/HTTP failure, but inside $( ) that only ends the
# subshell — propagate its code rather than continuing with "".
BBC="$(wit_gitea_blocked_by_count "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")" || exit "$?"

# `.repository` is absent from some Gitea issue payloads; the ID grammar needs
# owner/repo, and the id parsed from the argument is authoritative for exactly that.
# Injecting it keeps the normalizer's single definition of `qualify` usable for both
# this verb and list-items rather than forking the program.
jq -c \
  --arg sv "$WIT_SCHEMA_VERSION" \
  --argjson bbc "$BBC" \
  --arg full "$WIT_ID_OWNER/$WIT_ID_REPO" \
  '(.repository.full_name //= $full) | '"$WIT_GITEA_NORMALIZE_PROGRAM" \
  <<<"$WIT_GITEA_BODY" || {
  printf 'get-item.sh: could not normalize the gitea response for %s\n' "$ID" >&2
  exit "$EX_INTERNAL"
}
