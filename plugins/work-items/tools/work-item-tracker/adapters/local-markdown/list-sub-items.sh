#!/usr/bin/env bash
# list-sub-items <parent-id> [--state open|closed|all] — adapter contract
# (CONTRACT.md "Adapter contract"). Enumerates a container's DIRECT children as
# full normalized item objects (same envelope as list-items), each carrying its
# stored parent_id. Raw enumeration: closed and nested-container children are
# kept (frontier filtering is a separate core-side step). Offline — the parent
# link lives in each item's frontmatter, so no native sub-issue surface is
# needed; matches by the stored (JSON-quoted) `parent` field.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-sub-items <parent-id> [--state open|closed|all]" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: list-sub-items <parent-id> [--state open|closed|all]"
shift
state="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
      state="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
case "$state" in
  open | closed | all) ;;
  *) wit_usage_error "--state must be open|closed|all (got: $state)" ;;
esac
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id (expected local-markdown:<owner>/<repo>#<number>)"

wit_need_storage
# The `parent` frontmatter field stores the JSON-quoted id (create-item.sh), so
# compare against the quoted form, never the bare id.
parent_quoted="$(jq -cn --arg p "$id" '$p')"

numbers=()
shopt -s nullglob
for f in "$WIT_STORAGE_DIR"/*.md; do
  base="$(basename "$f" .md)"
  [[ "$base" =~ ^[0-9]+$ ]] || continue
  numbers+=("$base")
done

{
  for n in $(printf '%s\n' "${numbers[@]+"${numbers[@]}"}" | sort -n); do
    file="$(wit_item_file "$n")"
    [[ "$(wit_fm_field "$file" parent)" == "$parent_quoted" ]] || continue
    item_state="$(wit_fm_field "$file" state)"
    case "$state" in
      all) ;;
      open) [[ "$item_state" == '"open"' ]] || continue ;;
      closed) [[ "$item_state" == '"closed"' ]] || continue ;;
      *) ;; # unreachable: --state is validated to open|closed|all at parse time
    esac
    wit_emit_local_item "$n" true
  done
} | jq -c -s --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: .}'
