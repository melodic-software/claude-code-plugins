#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates
# with explicit pagination: emits up to limits.list_items_max items (ascending by
# number). --repo is accepted for interface parity but each item carries its own
# stored id, so the store is single-namespace and the flag does not re-target.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <owner>/<repo>]" "$@"

state="open" repo_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
      state="$2"
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
case "$state" in
  open | closed | all) ;;
  *) wit_usage_error "--state must be open|closed|all (got: $state)" ;;
esac
: "${repo_override:=}" # accepted for parity; single-namespace store ignores it

wit_need_storage
limit="$(jq -r '.limits.list_items_max' "$WIT_LOCAL_ADAPTER_DIR/capabilities.json")"

numbers=()
shopt -s nullglob
for f in "$WIT_STORAGE_DIR"/*.md; do
  base="$(basename "$f" .md)"
  [[ "$base" =~ ^[0-9]+$ ]] || continue
  numbers+=("$base")
done

emitted=0
{
  for n in $(printf '%s\n' "${numbers[@]+"${numbers[@]}"}" | sort -n); do
    ((emitted < limit)) || break
    item_state="$(wit_fm_field "$(wit_item_file "$n")" state)"
    case "$state" in
      all) ;;
      open) [[ "$item_state" == '"open"' ]] || continue ;;
      closed) [[ "$item_state" == '"closed"' ]] || continue ;;
      *) ;; # unreachable: --state is validated to open|closed|all at parse time
    esac
    wit_emit_local_item "$n" true
    emitted=$((emitted + 1))
  done
} | jq -c -s --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv, items: .}'
