#!/usr/bin/env bash
# add-sub-item <id> --parent <id> — CONTRACT.md "Verbs (core public surface)".
# Records the parent as a frontmatter field; get-item is authoritative for linkage.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: add-sub-item <id> --parent <id>" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: add-sub-item <id> --parent <id>"
shift
parent=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent)
      [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
      parent="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$parent" ]] || wit_usage_error "--parent is required"
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id"
number="$WIT_ID_NUMBER" # capture before the parent parse overwrites WIT_ID_NUMBER
wit_require_local_id "$parent" || wit_usage_error "malformed or non-local-markdown --parent id: $parent"
parent_number="$WIT_ID_NUMBER"

wit_need_storage
file="$(wit_item_file "$number")"
[[ -f "$file" ]] || {
  printf 'add-sub-item: no item %s\n' "$id" >&2
  exit "$EX_NOT_FOUND"
}
wit_item_exists "$parent_number" || {
  printf 'add-sub-item: parent %s not found\n' "$parent" >&2
  exit "$EX_NOT_FOUND"
}
wit_fm_set "$file" parent "$(jq -cn --arg p "$parent" '$p')"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg parent "$parent" \
  '{schema_version: $sv, id: $id, parent_id: $parent, linked: true}'
