#!/usr/bin/env bash
# set-fields <id> --field <field-id>=<option-id> [--field ...] — CONTRACT.md "Verbs (core public
# surface)". Write. Sets single-select org issue fields by option id. Each option id must be one
# of its field's options in the item's organization (GET orgs/{org}/issue-fields); any other id
# exits 5 before anything is written. The REST write takes option names, so the verb sends the
# name the listing gives each id, all fields in one POST, which leaves the item's other fields as
# they are.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: set-fields <id> --field <field-id>=<option-id> [--field <field-id>=<option-id> ...]"
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift
pairs="[]"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --field)
    [[ $# -ge 2 && "$2" =~ ^([1-9][0-9]*)=([1-9][0-9]*)$ ]] ||
      wit_usage_error "--field needs <field-id>=<option-id>, both whole numbers"
    field="${BASH_REMATCH[1]}"
    [[ "$(jq --argjson f "$field" 'any(.[]; .field_id == $f)' <<<"$pairs")" == "false" ]] ||
      wit_usage_error "field $field given twice"
    pairs="$(jq -c --argjson f "$field" --argjson o "${BASH_REMATCH[2]}" '. + [{field_id: $f, option_id: $o}]' <<<"$pairs")"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ "$pairs" != "[]" ]] || wit_usage_error "at least one --field is required"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"

api_version=(-H "X-GitHub-Api-Version: 2026-03-10")
wit_run_gh read api "${api_version[@]}" "orgs/$WIT_ID_OWNER/issue-fields"
resolved="$(jq -c --argjson pairs "$pairs" '. as $fields | $pairs | map(. as $p
  | ($fields[] | select(.id == $p.field_id) | .options // [] | .[] | select(.id == $p.option_id) | .name) as $name
  | $p + {value: $name})' <<<"$WIT_GH_OUT")" || {
  echo "set-fields: org issue-field listing for $WIT_ID_OWNER is not JSON" >&2
  exit "$EX_INTERNAL"
}
missing="$(jq -r --argjson r "$resolved" '.[] | select(. as $p | $r | all(.field_id != $p.field_id)) | "\(.field_id)=\(.option_id)"' <<<"$pairs")"
if [[ -n "$missing" ]]; then
  printf 'set-fields: not an option of that field in %s: %s\n' "$WIT_ID_OWNER" "${missing//$'\n'/, }" >&2
  exit "$EX_NOT_FOUND"
fi

# The body goes as JSON on stdin: gh's -f/-F array-of-objects form splits each field id and value
# into separate entries, which the API rejects.
body="$(jq -c '{issue_field_values: map({field_id, value})}' <<<"$resolved")"
wit_run_gh write api -X POST "${api_version[@]}" \
  "repos/$WIT_ID_OWNER/$WIT_ID_REPO/issues/$WIT_ID_NUMBER/issue-field-values" --input - <<<"$body"

jq -nc --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson fields "$resolved" \
  '{schema_version: $sv, id: $id, fields: $fields}'
