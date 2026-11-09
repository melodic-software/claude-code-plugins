#!/usr/bin/env bash
# Core-side frontier derivation (CONTRACT.md "Verbs (core public surface)") over an
# adapter envelope; provider search syntax never reaches this layer. Sourced.

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# shellcheck source=labels.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/labels.sh"

# wit_filter_label <label> — stdin a list envelope, stdout the items carrying exactly that
# label. Core runs it after every `--label` read, so a provider whose label filter matches
# loosely (case-insensitively, or by any of several comma-split names) cannot widen the
# result. Every other envelope key, `truncated` included, passes through unchanged.
wit_filter_label() {
  jq -c --arg label "$1" '.items |= [.[] | select((.labels // []) | index($label))]'
}

# wit_filter_frontier <autonomous:true|false> [<human-gated-label>] [<container-label>]
# stdin a list-items envelope, stdout the frontier. Callers with a binding pass its
# resolved WIT_HUMAN_GATED_LABEL / WIT_CONTAINER_LABEL so a remap is honored; the hold
# lists and the wayfind prefix come from the WIT_HOLD_*_JSON and WIT_WAYFIND_PREFIX
# that wit_read_binding exports, else the lib/labels.sh defaults. The
# source envelope's `truncated` passes through unchanged: filtering a truncated
# listing yields a truncated frontier. An adapter that predates the field emits
# none, and the frontier then carries none either, so a reader sees "unknown".
# An item whose `status` (its Work status, wit_attach_statuses) is a hold state
# and that carries no hold-state label is held as well: labels reach the field
# first, so the field may only add a hold the labels lack and never frees an
# item they hold. No setter is checked here: the adapter's get-statuses answers
# only counted values when the binding configures setter trust (the GitHub
# adapter's config.github.status_trust), and this filter takes `status` as given.
wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-$WIT_DEFAULT_HUMAN_GATED_LABEL}" container="${3:-$WIT_DEFAULT_CONTAINER_LABEL}"
  local status_json floor_json states_json state_labels_json hold_labels_json
  # Build the floor lists (provenance and status labels; the hold
  # states) as jq array arguments. --args positionals keep labels containing
  # spaces intact (every member does).
  status_json="${WIT_HOLD_LABELS_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_STATUS_LABELS[@]}")}"
  floor_json="$(jq -n -c --argjson status "$status_json" '$ARGS.positional + $status' --args "${WIT_HUMAN_FLOOR_PROVENANCE_LABELS[@]}")"
  states_json="${WIT_HOLD_STATES_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_STATUS_STATES[@]}")}"
  state_labels_json="${WIT_HOLD_STATE_LABELS_JSON:-$(jq -n -c '$ARGS.positional' --args "${WIT_HOLD_STATE_LABELS[@]}")}"
  hold_labels_json="$(jq -n -c --argjson held "$state_labels_json" '$ARGS.positional + $held' --args "$human_gated")"
  jq -c --arg auto "$autonomous" --arg human_gated "$human_gated" --arg container "$container" \
    --arg wayfind "${WIT_WAYFIND_PREFIX:-$WIT_WAYFIND_LABEL_PREFIX}" --argjson floor "$floor_json" --argjson states "$states_json" \
    --argjson hold_labels "$hold_labels_json" '{
    schema_version: .schema_version,
    items: [
      .items[]
      | select(
          .state == "open"
          and .blocked_by_count == 0
          and ((.assignees // []) | length == 0)
          and (((.labels // []) | index($container)) | not)
          and (any((.labels // [])[]?; type == "string" and startswith($wayfind)) | not)
          and (if $auto == "true"
               then (((.labels // []) | index($human_gated)) | not)
                    and (((.labels // []) | any(. as $l | $floor | index($l))) | not)
                    and (((.status | type) == "string" and (.status as $s | $states | index($s))
                          and (((.labels // []) | any(. as $l | $hold_labels | index($l))) | not)) | not)
               else true
               end)
        )
    ]
  } + (if has("truncated") then {truncated: .truncated} else {} end)'
}
