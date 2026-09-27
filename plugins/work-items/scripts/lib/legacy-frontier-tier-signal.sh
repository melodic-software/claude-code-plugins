#!/usr/bin/env bash
# legacy-frontier-tier-signal.sh — detect pre-#1716 frontier-tier body stamps.
#
# Patterns stay narrow: a generic "frontier tier" mention (for example
# security-surface dispatch prose) must not match.

wit_body_has_legacy_frontier_tier_signal() {
  local body="${1:-}"
  [[ -n "$body" ]] || return 1

  local -a patterns=(
    '[Cc]apability[- ]tier:[[:space:]]*[Ff]rontier'
    '[Ss]tamped for the frontier capability tier'
    '[Ff]rontier[- ]tier quota guard'
    '\*\*[Cc]apability tier:\*\*[[:space:]]*[Ff]rontier'
  )

  # One grep over the catalogue joined as an ERE alternation (`|` binds loosest,
  # so each entry stays intact); a per-pattern loop would fork grep per entry.
  local pattern
  pattern="$(printf '%s|' "${patterns[@]}")"
  pattern="${pattern%|}"
  printf '%s' "$body" | grep -Eq "$pattern"
}
