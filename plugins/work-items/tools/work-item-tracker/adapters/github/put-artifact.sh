#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: put-artifact <id> (--body-file <path> | --body <text> | --url <url>) [--name <name>] [--type generic|plan|embedded_html] [--artifact <number>]'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift

body_file="" body="" url="" name="" art_type="" explicit_num=""
has_body_file=0 has_body=0 has_url=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --body-file)
    [[ $# -ge 2 ]] || wit_usage_error "--body-file needs a value"
    body_file="$2"
    has_body_file=1
    shift 2
    ;;
  --body)
    [[ $# -ge 2 ]] || wit_usage_error "--body needs a value"
    body="$2"
    has_body=1
    shift 2
    ;;
  --url)
    [[ $# -ge 2 ]] || wit_usage_error "--url needs a value"
    url="$2"
    has_url=1
    shift 2
    ;;
  --name)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--name needs a non-empty value"
    name="$2"
    shift 2
    ;;
  --type)
    [[ $# -ge 2 ]] || wit_usage_error "--type needs a value"
    art_type="$2"
    shift 2
    ;;
  --artifact)
    [[ $# -ge 2 ]] || wit_usage_error "--artifact needs a value"
    explicit_num="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done

wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

src_count=$((has_body_file + has_body + has_url))
((src_count == 1)) || wit_usage_error "specify exactly one of --body-file, --body, or --url"

if ((has_body_file)); then
  [[ -f "$body_file" && -r "$body_file" ]] || wit_usage_error "--body-file '$body_file' is not a readable file"
  [[ -s "$body_file" ]] || wit_usage_error "--body-file '$body_file' is empty"
  [[ -n "$name" ]] || name="$(basename "$body_file")"
fi
if ((has_body)); then
  [[ -n "$name" || -n "$explicit_num" ]] || wit_usage_error "--name is required with --body (unless --artifact is set)"
fi
if ((has_url)); then
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || wit_usage_error "--url must be an http(s) URL with no whitespace"
  [[ -z "$art_type" ]] || wit_usage_error "--type is not valid with --url (link artifacts have fixed type link)"
fi
if [[ -n "$art_type" ]]; then
  case "$art_type" in
  generic | plan | embedded_html) ;;
  *) wit_usage_error "--type must be one of: generic, plan, embedded_html" ;;
  esac
fi
if [[ -n "$explicit_num" && ! "$explicit_num" =~ ^[1-9][0-9]*$ ]]; then
  wit_usage_error "--artifact must be a positive integer"
fi

unavail_extra='{"action":null,"artifact":null}'
if ! wit_gh_has_issue_artifact; then
  wit_gh_emit_unavailable put-artifact "$id" "comment" \
    "gh issue artifact subcommand unavailable (requires gh with issue artifact support)" "$unavail_extra"
fi

desired_type="generic"
if ((has_url)); then
  desired_type="link"
elif [[ -n "$art_type" ]]; then
  desired_type="$art_type"
elif [[ "${name,,}" == *.html || "${name,,}" == *.htm || "${body_file,,}" == *.html || "${body_file,,}" == *.htm ]]; then
  desired_type="embedded_html"
fi

art_num="$explicit_num"
final_name="$name"
final_type=""
final_url=""

if [[ -z "$art_num" && -n "$name" ]]; then
  if ! wit_gh_capture read issue artifact list "$number" -R "$owner/$repo" --json number,name,type,url; then
    if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
      wit_gh_emit_unavailable put-artifact "$id" "comment" "$WIT_GH_ERR" "$unavail_extra"
    fi
    printf '%s\n' "$WIT_GH_ERR" >&2
    exit "$(wit_map_gh_error "$WIT_GH_ERR")"
  fi
  existing="$(jq -c --arg n "$name" '[.[] | select(.name == $n)][0] // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
  if [[ -n "$existing" ]]; then
    art_num="$(jq -r '.number // empty' <<<"$existing")"
    final_type="$(jq -r '.type // empty' <<<"$existing")"
    final_url="$(jq -r '.url // empty' <<<"$existing")"
    final_name="$(jq -r '.name // empty' <<<"$existing")"
    if ((has_url)) && [[ "$final_type" != "link" ]]; then
      printf 'put-artifact: cannot update %s artifact #%s with --url\n' "$final_type" "$art_num" >&2
      exit "$EX_CONFLICT"
    fi
    if ((has_url == 0)) && [[ "$final_type" == "link" ]]; then
      printf 'put-artifact: cannot update link artifact #%s with document content\n' "$art_num" >&2
      exit "$EX_CONFLICT"
    fi
    if [[ -n "$art_type" && "$final_type" != "$art_type" ]]; then
      printf 'put-artifact: cannot change artifact #%s type from %s to %s\n' "$art_num" "$final_type" "$art_type" >&2
      exit "$EX_CONFLICT"
    fi
  fi
fi

if [[ -n "$art_num" ]]; then
  edit_args=(issue artifact edit "$number" "$art_num" -R "$owner/$repo")
  if ((has_body_file)); then
    edit_args+=(--body-file "$body_file")
  elif ((has_body)); then
    edit_args+=(--body "$body")
  else
    edit_args+=(--body "$url")
  fi
  if [[ -n "$explicit_num" && -n "$name" ]]; then
    edit_args+=(--name "$name")
  fi
  if ! wit_gh_capture write "${edit_args[@]}"; then
    if [[ -n "$explicit_num" && ("$WIT_GH_ERR" == *"HTTP 404"* || "$WIT_GH_ERR" == *"Not Found"*) ]]; then
      if gh issue artifact list "$number" -R "$owner/$repo" --json number >/dev/null 2>&1; then
        printf '%s\n' "$WIT_GH_ERR" >&2
        exit "$EX_NOT_FOUND"
      fi
    fi
    if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
      wit_gh_emit_unavailable put-artifact "$id" "comment" "$WIT_GH_ERR" "$unavail_extra"
    fi
    printf '%s\n' "$WIT_GH_ERR" >&2
    exit "$(wit_map_gh_error "$WIT_GH_ERR")"
  fi
  if [[ "$WIT_GH_OUT" =~ (https?://[^[:space:]]+/issues/[0-9]+/artifacts/[0-9]+) ]]; then
    final_url="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$final_type" || -z "$final_name" ]]; then
    if wit_gh_capture read issue artifact view "$number" "$art_num" -R "$owner/$repo" --json number,name,type,url; then
      final_name="$(jq -r '.name // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
      final_type="$(jq -r '.type // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
      final_url="$(jq -r '.url // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
    fi
  fi
  [[ -n "$final_type" ]] || final_type="$desired_type"
  [[ -n "$final_url" ]] || final_url="https://github.com/$owner/$repo/issues/$number/artifacts/$art_num"
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson num "$art_num" \
    --arg name "$final_name" --arg type "$final_type" --arg url "$final_url" \
    '{schema_version: $sv, id: $id, available: true, action: "updated",
      artifact: {number: $num, name: $name, type: $type, url: $url}}'
  exit 0
fi

create_args=(issue artifact create "$number" -R "$owner/$repo")
if ((has_url)); then
  create_args+=("$url")
  [[ -z "$name" ]] || create_args+=(--name "$name")
elif ((has_body_file)); then
  create_args+=(--body-file "$body_file" --name "$name" --type "$desired_type")
else
  create_args+=(--body "$body" --name "$name" --type "$desired_type")
fi

if ! wit_gh_capture write "${create_args[@]}"; then
  if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
    wit_gh_emit_unavailable put-artifact "$id" "comment" "$WIT_GH_ERR" "$unavail_extra"
  fi
  printf '%s\n' "$WIT_GH_ERR" >&2
  exit "$(wit_map_gh_error "$WIT_GH_ERR")"
fi

created_num="" created_url=""
if [[ "$WIT_GH_OUT" =~ (https?://[^[:space:]]+/issues/[0-9]+/artifacts/([0-9]+)) ]]; then
  created_url="${BASH_REMATCH[1]}"
  created_num="${BASH_REMATCH[2]}"
fi

if [[ -z "$created_num" || -z "$final_name" ]]; then
  if wit_gh_capture read issue artifact list "$number" -R "$owner/$repo" --json number,name,type,url; then
    latest="$(jq -c --arg n "$name" 'if $n != "" then ([.[] | select(.name == $n)] | sort_by(.number) | last) else (sort_by(.number) | last) end // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
    if [[ -n "$latest" ]]; then
      created_num="$(jq -r '.number // empty' <<<"$latest")"
      final_name="$(jq -r '.name // empty' <<<"$latest")"
      desired_type="$(jq -r '.type // empty' <<<"$latest")"
      created_url="$(jq -r '.url // empty' <<<"$latest")"
    fi
  fi
fi

if [[ ! "$created_num" =~ ^[0-9]+$ ]]; then
  printf 'put-artifact: created artifact on %s but could not determine its artifact number\n' "$id" >&2
  exit "$EX_INTERNAL"
fi
[[ -n "$created_url" ]] || created_url="https://github.com/$owner/$repo/issues/$number/artifacts/$created_num"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson num "$created_num" \
  --arg name "$final_name" --arg type "$desired_type" --arg url "$created_url" \
  '{schema_version: $sv, id: $id, available: true, action: "created",
    artifact: {number: $num, name: $name, type: $type, url: $url}}'
