#!/usr/bin/env bash
# Core-side frontier derivation (CONTRACT.md "Verbs (core public surface)"):
# frontier = open AND zero open blockers AND unassigned AND not a container;
# --autonomous additionally drops items labeled with the configured "human-gated"
# role label (default needs-human; label-taxonomy.md "Canonical roles",
# config.role_labels). Runs over the adapter's list-items envelope (or, for a
# container-scoped frontier, its list-sub-items envelope) — provider search
# syntax never reaches this layer. Sourced.

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# The container marker (CONTRACT.md "Containers and state"): an ordinary item
# carrying this label is a navigable graph root (wayfind maps, decompose
# breakdowns), never a claimable worker item — so it is never its own frontier
# item. A named constant, not a baked literal: it matches the documented CONTRACT
# term. Making the string configurable (a consumer wanting a non-`work-map`
# marker) is deferred to the label-taxonomy config.role_labels convention, keyed
# off that same first request — not a parallel binding key.
readonly WIT_CONTAINER_LABEL="work-map"

# wit_filter_frontier <autonomous:true|false> [<human-gated-label>] [<container-label>]
# — stdin: list-items (or list-sub-items) envelope; stdout: frontier envelope
# (same schema_version passthrough). human-gated defaults to "needs-human";
# callers resolving a binding should pass WIT_HUMAN_GATED_LABEL (lib/binding.sh)
# so a repo's configured remap is honored. container defaults to
# WIT_CONTAINER_LABEL; a container item is dropped from every frontier
# unconditionally (issue #498 obs #3 — a container must never surface itself).
wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-needs-human}" container="${3:-$WIT_CONTAINER_LABEL}"
  jq -c --arg auto "$autonomous" --arg human_gated "$human_gated" --arg container "$container" '{
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
               else true
               end)
        )
    ]
  }'
}
