#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: list-sub-items <parent-id> [--state open|closed|all]'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "$usage"
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
parent_quoted="$(jq -cn --arg p "$id" '$p')"

{
  for n in $(wit_item_numbers); do
    file="$(wit_item_file "$n")"
    [[ "$(wit_fm_field "$file" parent)" == "$parent_quoted" ]] || continue
    wit_state_matches "$state" "$(wit_fm_field "$file" state)" || continue
    wit_emit_local_item "$n" true
  done
} | jq -c -s --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: ., truncated: false}'
