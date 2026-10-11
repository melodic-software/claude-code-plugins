#!/usr/bin/env bash
# list-items — adapter contract (CONTRACT.md "Adapter contract"). Raw candidates
# with explicit pagination: emits up to limits.list_items_max items (ascending by
# number). --repo is accepted for interface parity but each item carries its own
# stored id, so the store is single-namespace and the flag does not re-target.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: list-items [--state open|closed|all] [--repo <owner>/<repo>]" "$@"

state="open"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --state)
    [[ $# -ge 2 ]] || wit_usage_error "--state needs a value"
    state="$2"
    shift 2
    ;;
  # Parsed and discarded: the value has nothing to re-target (see the header).
  --repo)
    [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
case "$state" in
open | closed | all) ;;
*) wit_usage_error "--state must be open|closed|all (got: $state)" ;;
esac

wit_need_storage
limit="$(jq -r '.limits.list_items_max' "$WIT_LOCAL_ADAPTER_DIR/capabilities.json")"

# `truncated` is true only when a matching item past the ceiling exists, so a store
# holding exactly `limit` matches still reads as complete.
emitted=0 truncated=false rows=""
for n in $(wit_item_numbers); do
  item_state="$(wit_fm_field "$(wit_item_file "$n")" state)"
  wit_state_matches "$state" "$item_state" || continue
  if ((emitted >= limit)); then
    truncated=true
    break
  fi
  row="$(wit_emit_local_item "$n" true)" || continue
  rows+="$row"$'\n'
  emitted=$((emitted + 1))
done
printf '%s' "$rows" |
  jq -c -s --arg sv "$WIT_SCHEMA_VERSION" --argjson truncated "$truncated" \
    '{schema_version: $sv, items: ., truncated: $truncated}'
