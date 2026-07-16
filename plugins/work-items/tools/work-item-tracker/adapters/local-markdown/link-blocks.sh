#!/usr/bin/env bash
# link-blocks <id> --blocked-by <id> — CONTRACT.md "Verbs (core public surface)".
# Appends a structured "Blocked by:" line; get-item/list-items resolve blocker state
# by number. cross_repo_edges is unsupported (single-namespace store) — a blocker in
# another namespace is recorded as a text pointer only, never a resolvable edge.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: link-blocks <id> --blocked-by <id>" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: link-blocks <id> --blocked-by <id>"
shift
blocker=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocked-by)
      [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
      blocker="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$blocker" ]] || wit_usage_error "--blocked-by is required"
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id"
number="$WIT_ID_NUMBER" # capture before the blocker parse overwrites WIT_ID_NUMBER
wit_require_local_id "$blocker" || wit_usage_error "malformed or non-local-markdown --blocked-by id: $blocker"
blocker_number="$WIT_ID_NUMBER"

wit_need_storage
file="$(wit_item_file "$number")"
[[ -f "$file" ]] || {
  printf 'link-blocks: no item %s\n' "$id" >&2
  exit "$EX_NOT_FOUND"
}
wit_item_exists "$blocker_number" || {
  printf 'link-blocks: blocker %s not found\n' "$blocker" >&2
  exit "$EX_NOT_FOUND"
}
printf 'Blocked by: %s\n' "$blocker" >>"$file"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg blocker "$blocker" \
  '{schema_version: $sv, id: $id, blocked_by: $blocker, linked: true}'
