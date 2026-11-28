#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: set-native-status <id> --status <name>"
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift
status_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --status)
    [[ $# -ge 2 && -n "$2" && -z "$status_name" ]] || wit_usage_error "--status needs one non-empty status name"
    status_name="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$status_name" ]] || wit_usage_error "--status is required"
if [[ "$status_name" =~ ^[0-9]+$ ]]; then
  wit_usage_error "--status must be a status name string (e.g. Todo, In progress, Done), not a numeric id"
fi
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"
extra_unavail='{"status":null,"updated":false}'

if ! wit_gh_capture write api -X PATCH "repos/$owner/$repo/issues/$number" -f "status=$status_name"; then
  if wit_gh_is_native_status_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number"; then
    wit_gh_emit_unavailable "set-native-status" "$id" "none" "$WIT_GH_ERR" "$extra_unavail"
  fi
  printf '%s\n' "$WIT_GH_ERR" >&2
  exit "$(wit_map_gh_error "$WIT_GH_ERR")"
fi

applied="$(jq -r 'if type == "object" and (.status | type) == "object" and (.status.name | type) == "string" and (.status.name | length) > 0 then .status.name else empty end' <<<"$WIT_GH_OUT" 2>/dev/null)" || applied=""
if [[ -z "$applied" ]]; then
  wit_gh_emit_unavailable "set-native-status" "$id" "none" \
    "repository did not apply native status (not enrolled or unsupported)" "$extra_unavail"
fi

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg status "$applied" \
  '{schema_version: $sv, id: $id, status: $status, available: true, updated: true}'
