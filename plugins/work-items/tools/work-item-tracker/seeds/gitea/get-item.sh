#!/usr/bin/env bash
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

SCOPE="$WIT_ID_OWNER/$WIT_ID_REPO"
wit_gitea_scope_in_scope "$SCOPE" ||
  wit_usage_error "$SCOPE is not in config.gitea.scopes (the declared read scope)"

wit_gitea_http GET "/repos/$WIT_ID_OWNER/$WIT_ID_REPO/issues/$WIT_ID_NUMBER"
wit_gitea_require_ok "fetching $ID"

BBC="$(wit_gitea_blocked_by_count "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")" || exit "$?"

jq -c \
  --arg sv "$WIT_SCHEMA_VERSION" \
  --argjson bbc "$BBC" \
  --arg full "$WIT_ID_OWNER/$WIT_ID_REPO" \
  '(.repository.full_name //= $full) | '"$WIT_GITEA_NORMALIZE_PROGRAM" \
  <<<"$WIT_GITEA_BODY" || {
  printf 'get-item.sh: could not normalize the gitea response for %s\n' "$ID" >&2
  exit "$EX_INTERNAL"
}
