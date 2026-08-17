#!/usr/bin/env bash
# legacy-frontier-tier-signal.sh — detect pre-#1716 frontier-tier body stamps.
#
# Before the label reader flip, work-loop read frontier tier from triage-briefing
# body prose. Triage refuses to re-triage already-triaged items, so setup's
# backfill pass uses these patterns to find items that still carry only the legacy
# signal. Patterns are conservative: generic "frontier tier" mentions (e.g.
# security-surface dispatch prose) do not match.

wit_body_has_legacy_frontier_tier_signal() {
  local body="${1:-}"
  [[ -n "$body" ]] || return 1

  local -a patterns=(
    '[Cc]apability[- ]tier:[[:space:]]*[Ff]rontier'
    '[Ss]tamped for the frontier capability tier'
    '[Ff]rontier[- ]tier quota guard'
    '\*\*[Cc]apability tier:\*\*[[:space:]]*[Ff]rontier'
    '[Cc]apability tier:[[:space:]]*[Ff]rontier[[:space:]]*\(quota guard\)'
  )

  # One grep over the catalogue joined as an ERE alternation (`|` binds loosest,
  # so each entry stays intact) — a per-pattern loop forked grep once per entry.
  local pattern
  pattern="$(printf '%s|' "${patterns[@]}")"
  pattern="${pattern%|}"
  if printf '%s' "$body" | grep -Eq "$pattern"; then
    return 0
  fi
  return 1
}
