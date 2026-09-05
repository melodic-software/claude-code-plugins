#!/usr/bin/env bash
# Core-side frontier derivation (CONTRACT.md "Verbs (core public surface)"):
# frontier = open AND zero open blockers AND unassigned AND not a container;
# --autonomous additionally drops items labeled with the configured "human-gated"
# role label (default needs-human; label-taxonomy.md "Canonical roles",
# config.role_labels) AND items carrying a human-floor work class
# (WIT_HUMAN_FLOOR_WORK_CLASS_LABELS in lib/labels.sh — C4 structural, C5
# untrusted-provenance). Runs over the adapter's list-items envelope (or, for a
# container-scoped frontier, its list-sub-items envelope) — provider search
# syntax never reaches this layer. Sourced.

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# shellcheck source=labels.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/labels.sh"

# The container marker (CONTRACT.md "Containers and state"): an ordinary item
# carrying this label is a navigable graph root (wayfind maps, decompose
# breakdowns), never a claimable worker item — so it is never its own frontier
# item. The string resolves from the binding — config.container_label, a sibling
# of config.role_labels — falling back to the shipped default in lib/labels.sh;
# callers resolving a binding pass WIT_CONTAINER_LABEL (lib/binding.sh) so a
# repo's configured remap is honored.

# wit_filter_frontier <autonomous:true|false> [<human-gated-label>] [<container-label>]
# — stdin: list-items (or list-sub-items) envelope; stdout: frontier envelope
# (same schema_version passthrough). human-gated defaults to the shipped default
# (lib/labels.sh — the one definition source); callers resolving a binding should
# pass WIT_HUMAN_GATED_LABEL (lib/binding.sh) so a repo's configured remap is
# honored. container defaults the same way (WIT_DEFAULT_CONTAINER_LABEL /
# WIT_CONTAINER_LABEL); a container item is dropped from every frontier
# unconditionally — a container must never surface itself.
#
# The human-floor work classes are NOT a third positional parameter: unlike the
# role and container labels they have no binding key to remap (labels.sh), so
# the filter reads the shipped array directly.
#
# Why the floor is enforced HERE and not left to the admission gate: the gate
# runs after a worker has already claimed the item, so a contradictory item
# (autonomous-eligible role label + C4/C5 work class) is claimed, escalated, and
# released once per lane instance — burning a worker every pass while still
# looking frontier-available. The floor and the role label genuinely contradict;
# resolving that against the floor is fail-closed, and it is the same direction
# the unclassified case already resolves.
wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-$WIT_DEFAULT_HUMAN_GATED_LABEL}" container="${3:-$WIT_DEFAULT_CONTAINER_LABEL}"
  local floor_json
  # Build the floor list as a jq array argument. printf '%s\n' over the array
  # then slurping keeps labels containing spaces intact (every member does).
  floor_json="$(printf '%s\n' "${WIT_HUMAN_FLOOR_WORK_CLASS_LABELS[@]}" | jq -R . | jq -s -c .)"
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
  }'
}
