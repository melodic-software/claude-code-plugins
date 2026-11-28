#!/usr/bin/env bash

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# shellcheck source=labels.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/labels.sh"

wit_filter_label() {
  jq -c --arg label "$1" '.items |= [.[] | select((.labels // []) | index($label))]'
}

wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-$WIT_DEFAULT_HUMAN_GATED_LABEL}" container="${3:-$WIT_DEFAULT_CONTAINER_LABEL}"
  local status_json floor_json states_json state_labels_json hold_labels_json
  status_json="${WIT_HOLD_LABELS_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_STATUS_LABELS[@]}")}"
  floor_json="$(jq -n -c --argjson status "$status_json" '$ARGS.positional + $status' --args "${WIT_HUMAN_FLOOR_PROVENANCE_LABELS[@]}")"
  states_json="${WIT_HOLD_STATES_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_STATUS_STATES[@]}")}"
  state_labels_json="${WIT_HOLD_STATE_LABELS_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HOLD_STATE_LABELS[@]}")}"
  hold_labels_json="$(jq -n -c --argjson held "$state_labels_json" '$ARGS.positional + $held' --args "$human_gated")"
  jq -c --arg auto "$autonomous" --arg human_gated "$human_gated" --arg container "$container" \
    --arg wayfind "${WIT_WAYFIND_PREFIX:-$WIT_WAYFIND_LABEL_PREFIX}" \
    --arg session_owned "${WIT_SESSION_OWNED_LABEL:-$WIT_DEFAULT_SESSION_OWNED_LABEL}" --argjson floor "$floor_json" --argjson states "$states_json" \
    --argjson hold_labels "$hold_labels_json" '{
    schema_version: .schema_version,
    items: [
      .items[]
      | (.labels // []) as $labels
      | select(
          .state == "open"
          and .blocked_by_count == 0
          and ((.assignees // []) | length == 0)
          and (($labels | index($container)) | not)
          and (any($labels[]?; type == "string" and startswith($wayfind)) | not)
          and (if $auto == "true"
               then (($labels | index($human_gated)) | not)
                    and (($labels | index($session_owned)) | not)
                    and (($labels | any(. as $l | $floor | index($l))) | not)
                    and (((.status | type) == "string" and (.status as $s | $states | index($s))
                          and (($labels | any(. as $l | $hold_labels | index($l))) | not)) | not)
               else true
               end)
        )
    ]
  } + (if has("truncated") then {truncated: .truncated} else {} end)'
}
