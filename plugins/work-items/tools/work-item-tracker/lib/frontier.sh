#!/usr/bin/env bash
# Core-side frontier derivation (CONTRACT.md "Verbs (core public surface)"):
# frontier = open AND zero open blockers AND unassigned; --autonomous additionally
# drops items labeled needs-human. Runs over the adapter's list-items envelope —
# provider search syntax never reaches this layer. Sourced.

[[ -n "${_WIT_FRONTIER_LOADED:-}" ]] && return 0
readonly _WIT_FRONTIER_LOADED=1

# wit_filter_frontier <autonomous:true|false> — stdin: list-items envelope;
# stdout: frontier envelope (same schema_version passthrough).
wit_filter_frontier() {
  local autonomous="${1:-false}"
  jq -c --arg auto "$autonomous" '{
    schema_version: .schema_version,
    items: [
      .items[]
      | select(
          .state == "open"
          and .blocked_by_count == 0
          and ((.assignees // []) | length == 0)
          and (if $auto == "true"
               then (((.labels // []) | index("needs-human")) | not)
               else true
               end)
        )
    ]
  }'
}
