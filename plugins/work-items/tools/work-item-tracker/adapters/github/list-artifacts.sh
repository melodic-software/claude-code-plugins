#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: list-artifacts <id> [--type generic|plan|link|embedded_html] [--limit <n>]'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift

art_type="" limit=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --type)
    [[ $# -ge 2 ]] || wit_usage_error "--type needs a value"
    art_type="$2"
    shift 2
    ;;
  --limit)
    [[ $# -ge 2 ]] || wit_usage_error "--limit needs a value"
    limit="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done

wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

if [[ -n "$art_type" ]]; then
  case "$art_type" in
  generic | plan | link | embedded_html) ;;
  *) wit_usage_error "--type must be one of: generic, plan, link, embedded_html" ;;
  esac
fi
if [[ -n "$limit" && ! "$limit" =~ ^[1-9][0-9]*$ ]]; then
  wit_usage_error "--limit must be a positive integer"
fi

unavail_extra='{"artifacts":[]}'
if ! wit_gh_has_issue_artifact; then
  wit_gh_emit_unavailable list-artifacts "$id" "comment" \
    "gh issue artifact subcommand unavailable (requires gh with issue artifact support)" "$unavail_extra"
fi

args=(issue artifact list "$number" -R "$owner/$repo" --json "id,number,name,type,url,createdAt,updatedAt")
[[ -z "$art_type" ]] || args+=(--type "$art_type")
[[ -z "$limit" ]] || args+=(--limit "$limit")

if ! wit_gh_capture read "${args[@]}"; then
  if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
    wit_gh_emit_unavailable list-artifacts "$id" "comment" "$WIT_GH_ERR" "$unavail_extra"
  fi
  printf '%s\n' "$WIT_GH_ERR" >&2
  exit "$(wit_map_gh_error "$WIT_GH_ERR")"
fi

# shellcheck disable=SC2016  # jq variables, not bash expansions
jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" "$WIT_JQ_DEF_UTC_TS"'{
  schema_version: $sv,
  id: $id,
  available: true,
  artifacts: [(. // [])[] | {
    id: (.id // null),
    number: .number,
    name: .name,
    type: .type,
    url: .url,
    created_at: (.createdAt | wit_utc_ts),
    updated_at: (.updatedAt | wit_utc_ts)
  }]
}' <<<"$WIT_GH_OUT" || {
  printf 'list-artifacts: response for %s is not JSON\n' "$id" >&2
  exit "$EX_INTERNAL"
}
