#!/usr/bin/env bash
wit_body_has_legacy_frontier_tier_signal() {
  local body="${1:-}"
  [[ -n "$body" ]] || return 1

  local -a patterns=(
    '[Cc]apability[- ]tier:[[:space:]]*[Ff]rontier'
    '[Ss]tamped for the frontier capability tier'
    '[Ff]rontier[- ]tier quota guard'
    '\*\*[Cc]apability tier:\*\*[[:space:]]*[Ff]rontier'
  )

  local IFS='|'
  grep -Eq "${patterns[*]}" <<<"$body"
}
