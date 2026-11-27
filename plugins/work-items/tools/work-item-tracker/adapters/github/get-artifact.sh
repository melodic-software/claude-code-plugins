#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: get-artifact <id> (--artifact <number> | --name <name>) [--version <n>] [--versions]'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift

art_num="" art_name="" version="" include_versions=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --artifact)
    [[ $# -ge 2 ]] || wit_usage_error "--artifact needs a value"
    art_num="$2"
    shift 2
    ;;
  --name)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--name needs a non-empty value"
    art_name="$2"
    shift 2
    ;;
  --version)
    [[ $# -ge 2 ]] || wit_usage_error "--version needs a value"
    version="$2"
    shift 2
    ;;
  --versions)
    include_versions=1
    shift
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done

wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

if [[ -n "$art_num" && -n "$art_name" ]]; then
  wit_usage_error "--artifact and --name are mutually exclusive"
fi
if [[ -z "$art_num" && -z "$art_name" ]]; then
  wit_usage_error "specify either --artifact <number> or --name <name>"
fi
if [[ -n "$art_num" && ! "$art_num" =~ ^[1-9][0-9]*$ ]]; then
  wit_usage_error "--artifact must be a positive integer"
fi
if [[ -n "$version" && ! "$version" =~ ^[1-9][0-9]*$ ]]; then
  wit_usage_error "--version must be a positive integer"
fi

unavail_extra='{"artifact":null}'
if ! wit_gh_has_issue_artifact; then
  wit_gh_emit_unavailable get-artifact "$id" "comment" \
    "gh issue artifact subcommand unavailable (requires gh with issue artifact support)" "$unavail_extra"
fi

handle_view_error() {
  local err="$1"
  if [[ "$err" == *"HTTP 404"* || "$err" == *"Not Found"* ]]; then
    if gh issue artifact list "$number" -R "$owner/$repo" --json number >/dev/null 2>&1; then
      printf '%s\n' "$err" >&2
      exit "$EX_NOT_FOUND"
    fi
  fi
  if wit_gh_is_feature_unavailable "$err" "$owner" "$repo" "$number" 1; then
    wit_gh_emit_unavailable get-artifact "$id" "comment" "$err" "$unavail_extra"
  fi
  printf '%s\n' "$err" >&2
  exit "$(wit_map_gh_error "$err")"
}

if [[ -n "$art_name" ]]; then
  if ! wit_gh_capture read issue artifact list "$number" -R "$owner/$repo" --json number,name; then
    if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
      wit_gh_emit_unavailable get-artifact "$id" "comment" "$WIT_GH_ERR" "$unavail_extra"
    fi
    printf '%s\n' "$WIT_GH_ERR" >&2
    exit "$(wit_map_gh_error "$WIT_GH_ERR")"
  fi
  art_num="$(jq -r --arg n "$art_name" '[.[] | select(.name == $n)][0].number // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
  if [[ -z "$art_num" ]]; then
    printf "get-artifact: artifact '%s' not found on %s\n" "$art_name" "$id" >&2
    exit "$EX_NOT_FOUND"
  fi
fi

if [[ -z "$version" ]]; then
  fields="id,number,name,type,body,url,createdAt,updatedAt"
  ((include_versions)) && fields+=",versions"
  if ! wit_gh_capture read issue artifact view "$number" "$art_num" -R "$owner/$repo" --json "$fields"; then
    handle_view_error "$WIT_GH_ERR"
  fi
  # shellcheck disable=SC2016  # jq variables, not bash expansions
  jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson inc_v "$include_versions" "$WIT_JQ_DEF_UTC_TS"'{
    schema_version: $sv,
    id: $id,
    available: true,
    artifact: ({
      id: (.id // null),
      number: .number,
      name: .name,
      type: .type,
      url: .url,
      version: null,
      body: (.body // ""),
      created_at: (.createdAt | wit_utc_ts),
      updated_at: (.updatedAt | wit_utc_ts)
    } + (if $inc_v == 1 then {
      versions: [(.versions // [])[] | {
        number: .number,
        created_at: (.createdAt | wit_utc_ts),
        actor: (.actor.login // null)
      }]
    } else {} end))
  }' <<<"$WIT_GH_OUT" || {
    printf 'get-artifact: response for %s artifact #%s is not JSON\n' "$id" "$art_num" >&2
    exit "$EX_INTERNAL"
  }
  exit 0
fi

if ! wit_gh_capture read issue artifact view "$number" "$art_num" -R "$owner/$repo" \
  --json "id,number,name,type,url,createdAt,updatedAt,versions"; then
  handle_view_error "$WIT_GH_ERR"
fi
meta_json="$WIT_GH_OUT"

body_tmp="$(mktemp)"
err_tmp="$(mktemp)"
trap 'rm -f "$body_tmp" "$err_tmp"' EXIT

if ! gh issue artifact download "$number" "$art_num" -R "$owner/$repo" --version "$version" --output - \
  >"$body_tmp" 2>"$err_tmp"; then
  dl_err="$(<"$err_tmp")"
  if wit_gh_is_feature_unavailable "$dl_err" "$owner" "$repo" "$number" 0; then
    wit_gh_emit_unavailable get-artifact "$id" "comment" "$dl_err" "$unavail_extra"
  fi
  printf '%s\n' "$dl_err" >&2
  exit "$(wit_map_gh_error "$dl_err")"
fi

clean_tmp="$(mktemp)"
trap 'rm -f "$body_tmp" "$err_tmp" "$clean_tmp"' EXIT
tr -d '\r' <"$body_tmp" >"$clean_tmp"

# shellcheck disable=SC2016  # jq variables, not bash expansions
jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson ver "$version" \
  --argjson inc_v "$include_versions" --rawfile body "$clean_tmp" "$WIT_JQ_DEF_UTC_TS"'{
  schema_version: $sv,
  id: $id,
  available: true,
  artifact: ({
    id: (.id // null),
    number: .number,
    name: .name,
    type: .type,
    url: .url,
    version: $ver,
    body: $body,
    created_at: (.createdAt | wit_utc_ts),
    updated_at: (.updatedAt | wit_utc_ts)
  } + (if $inc_v == 1 then {
    versions: [(.versions // [])[] | {
      number: .number,
      created_at: (.createdAt | wit_utc_ts),
      actor: (.actor.login // null)
    }]
  } else {} end))
}' <<<"$meta_json" || {
  printf 'get-artifact: metadata response for %s artifact #%s is not JSON\n' "$id" "$art_num" >&2
  exit "$EX_INTERNAL"
}
