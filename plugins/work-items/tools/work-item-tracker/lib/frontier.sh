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
# resolved WIT_HUMAN_GATED_LABEL / WIT_CONTAINER_LABEL so a remap is honored. The
# source envelope's `truncated` passes through unchanged: filtering a truncated
# listing yields a truncated frontier. An adapter that predates the field emits
# none, and the frontier then carries none either, so a reader sees "unknown".
wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-$WIT_DEFAULT_HUMAN_GATED_LABEL}" container="${3:-$WIT_DEFAULT_CONTAINER_LABEL}"
  local floor_json
  # Build the floor list (work classes, provenance and status labels) as a jq array argument.
  # --args positionals keep labels containing spaces intact (every member does).
  floor_json="$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_WORK_CLASS_LABELS[@]}" "${WIT_HUMAN_FLOOR_PROVENANCE_LABELS[@]}" "${WIT_HUMAN_FLOOR_STATUS_LABELS[@]}")"
  jq -c --arg auto "$autonomous" --arg human_gated "$human_gated" --arg container "$container" \
    --argjson floor "$floor_json" '{
    schema_version: .schema_version,
    items: [
      .items[]
      | select(
          .state == "open"
          and .blocked_by_count == 0
          and ((.assignees // []) | length == 0)
          and (((.labels // []) | index($container)) | not)
          and (if $auto == "true"
               then (((.labels // []) | index($human_gated)) | not)
                    and (((.labels // []) | any(. as $l | $floor | index($l))) | not)
               else true
               end)
        )
    ]
  } + (if has("truncated") then {truncated: .truncated} else {} end)'
}
