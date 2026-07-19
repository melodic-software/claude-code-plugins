#!/usr/bin/env bash
# Core-side frontier derivation (CONTRACT.md "Verbs (core public surface)"):
# frontier = open AND zero open blockers AND unassigned; --autonomous additionally
# drops items labeled with the configured "human-gated" role label (default
# needs-human; label-taxonomy.md "Canonical roles", config.role_labels). Runs
# over the adapter's list-items envelope — provider search syntax never reaches
# this layer. Sourced.

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# wit_filter_frontier <autonomous:true|false> [<human-gated-label>] — stdin:
# list-items envelope; stdout: frontier envelope (same schema_version
# passthrough). The label defaults to "needs-human"; callers resolving a
# binding should pass WIT_HUMAN_GATED_LABEL (lib/binding.sh) instead of relying
# on that default, so a repo's configured remap is honored.
wit_filter_frontier() {
  local autonomous="${1:-false}" human_gated="${2:-needs-human}"
  jq -c --arg auto "$autonomous" --arg human_gated "$human_gated" '{
    schema_version: .schema_version,
    items: [
      .items[]
      | select(
          .state == "open"
          and .blocked_by_count == 0
          and ((.assignees // []) | length == 0)
          and (if $auto == "true"
               then (((.labels // []) | index($human_gated)) | not)
               else true
               end)
        )
    ]
  }'
}
