#!/usr/bin/env bash
# get-field-options --field <name-or-id> [--repo <owner>/<repo>] — CONTRACT.md "Verbs (core public
# surface)". Read-only. Lists the options of one single-select organization issue field, from the
# same listing set-fields validates against (GET orgs/{org}/issue-fields). The field is matched by
# its exact name or its numeric id. A field the organization does not have, or one with no options,
# yields an empty list and exit 0, so a caller falls back to its own defaults.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: get-field-options --field <name-or-id> [--repo <owner>/<repo>]"
wit_help_if_requested "$usage" "$@"

field="" repo_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --field)
    [[ $# -ge 2 && -n "$2" && -z "$field" ]] || wit_usage_error "--field needs one non-empty value"
    field="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--repo needs a value"
    repo_override="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$field" ]] || wit_usage_error "$usage"
[[ -z "$repo_override" || "$repo_override" =~ ^[^/]+/[^/]+$ ]] ||
  wit_usage_error "--repo must be <owner>/<repo> (got: $repo_override)"

# $() swallows wit_run_gh's exit-on-error; propagate its code (see create-item.sh).
target_repo="$(wit_resolve_repo "$repo_override")" || exit "$?"
owner="${target_repo%%/*}"

wit_run_gh read api -H "X-GitHub-Api-Version: 2026-03-10" "orgs/$owner/issue-fields"
options="$(jq -c --arg f "$field" '[.[] | select((.id | tostring) == $f or .name == $f)
  | .options // [] | .[] | {id, name}]' <<<"$WIT_GH_OUT")" || {
  echo "get-field-options: org issue-field listing for $owner is not JSON" >&2
  exit "$EX_INTERNAL"
}

jq -nc --arg sv "$WIT_SCHEMA_VERSION" --arg field "$field" --argjson options "$options" \
  '{schema_version: $sv, field: $field, options: $options}'
