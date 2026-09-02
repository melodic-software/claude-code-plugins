#!/usr/bin/env bash
# create-item — CONTRACT.md "Verbs (core public surface)". Creates via bot identity.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: create-item --title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <owner>/<repo>]" "$@"

title="" body="" labels="" type="" parent="" blocked_by="" repo_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || wit_usage_error "--title needs a value"
      title="$2"
      shift 2
      ;;
    --type)
      [[ $# -ge 2 ]] || wit_usage_error "--type needs a value"
      type="$2"
      shift 2
      ;;
    --body)
      [[ $# -ge 2 ]] || wit_usage_error "--body needs a value"
      body="$2"
      shift 2
      ;;
    --labels)
      [[ $# -ge 2 ]] || wit_usage_error "--labels needs a value"
      labels="$2"
      shift 2
      ;;
    --parent)
      [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
      parent="$2"
      shift 2
      ;;
    --blocked-by)
      [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
      blocked_by="$2"
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
[[ -n "$title" ]] || wit_usage_error "--title is required"

# wit_resolve_repo may call gh; wit_run_gh exits on API error, but inside $() that
# only exits the subshell — propagate its code rather than continuing with "".
target_repo="$(wit_resolve_repo "$repo_override")" || exit "$?"

args=(issue create -R "$target_repo" --title "$title" --body "$body")

# Native GitHub Issue Type (org-defined Task/Bug/Feature) is a gh 2.94 flag.
# On older gh, forwarding `--type` dies with `unknown flag` (exit 1) and
# `/work-items:track add` on an org repo files nothing. Degrade to the same
# coarse `type:` label personal/non-org repos already use, and say so.
if [[ -n "$type" ]]; then
  if wit_gh_has_native_surface; then
    args+=(--type "$type")
  else
    type_lc="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
    case "$type_lc" in
    bug | fix) type_label="type: bug" ;;
    feature | feat) type_label="type: feature" ;;
    *) type_label="type: task" ;;
    esac
    printf 'create-item.sh: --type requires gh >= 2.94; applying %s instead\n' \
      "$type_label" >&2
    if [[ ",${labels}," != *",${type_label},"* ]]; then
      labels="${labels:+$labels,}$type_label"
    fi
  fi
fi

if [[ -n "$labels" ]]; then
  IFS=',' read -ra label_list <<<"$labels"
  for label in "${label_list[@]}"; do
    args+=(--label "$label")
  done
fi

if [[ -n "$parent" ]]; then
  wit_require_github_id "$parent" || wit_usage_error "malformed or non-github --parent id: $parent"
  args+=(--parent "$(wit_issue_url "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")")
fi

if [[ -n "$blocked_by" ]]; then
  blocker_urls=""
  IFS=',' read -ra blocker_list <<<"$blocked_by"
  for blocker in "${blocker_list[@]}"; do
    wit_require_github_id "$blocker" || wit_usage_error "malformed or non-github --blocked-by id: $blocker"
    blocker_urls+="${blocker_urls:+,}$(wit_issue_url "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")"
  done
  args+=(--blocked-by "$blocker_urls")
fi

wit_run_gh write "${args[@]}"
created_url="$(printf '%s\n' "$WIT_GH_OUT" | tail -n1)"
number="${created_url##*/}"
[[ "$number" =~ ^[0-9]+$ ]] || {
  printf 'create-item: could not parse created issue URL: %s\n' "$created_url" >&2
  exit "$EX_INTERNAL"
}

wit_emit_item "${target_repo%%/*}" "${target_repo##*/}" "$number"
