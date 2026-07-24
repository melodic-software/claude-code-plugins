#!/usr/bin/env bash
# context-zone: resolve a session's context-usage zone from its snapshot.
#
# Usage:
#   context-zone.sh <session_id>
#
# Reads ~/.claude/context-guard/context/<session_id>.json (written by
# statusline-tee.sh) plus the optional machine-scope
# ~/.claude/context-guard/zones.json override and prints EXACTLY ONE word:
#
#   smart / acceptable / dumb / unknown
#
# Fail-open (../reference/reader-contract.md is the authoritative contract):
# absent, stale (captured_at older than the 10-minute staleness window), or
# unparsable snapshot → unknown; used_percentage null / missing /
# non-numeric / outside 0–100 → unknown; current_usage null or missing
# (documented early-session and post-/compact statusline states — a
# compacted session's percentage is not evidence) → unknown; jq absent →
# unknown. The resolver never throttles a consumer on data it cannot trust
# and never fabricates a zone. Exit code is always 0 — the word is the
# contract.
#
# SHIPPED DEFAULT BANDS (zones.json absent = zero-config): smart ≤ 50 <
# acceptable ≤ 75 < dumb, over context_window.used_percentage. These are
# declared judgment defaults, NOT doc-derived constants: no official page
# documents an auto-compaction threshold percentage (verified 2026-07-24
# against the statusline, how-Claude-Code-works, context-window, settings,
# and costs pages — they say only "as you approach the limit"). zones.json
# is the operator's tuning path:
#
#   { "smart_max_used_percentage": 50, "acceptable_max_used_percentage": 75 }
#
# A malformed zones.json (unparsable, non-numeric bands, inverted ordering,
# bands outside 0–100) falls back to the shipped defaults with a visible
# stderr notice — never silently. The resolver only ever READS zones.json;
# seeding/refreshing it is the setup skill's `apply`.

set -uo pipefail

STALENESS_SECONDS=600 # 10 minutes — byte-matches the reader contract
DEFAULT_SMART_MAX=50
DEFAULT_ACCEPTABLE_MAX=75

unknown() {
  printf 'unknown\n'
  exit 0
}

sid="${1:-}"
# Same filename character class the tee enforces — also path containment on
# the read side.
[[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || unknown
command -v jq >/dev/null 2>&1 || unknown
[[ -n "${HOME:-}" ]] || unknown

snap="$HOME/.claude/context-guard/context/$sid.json"
[[ -r "$snap" ]] || unknown

# One validation pass over the snapshot: emits "captured_at used_percentage"
# only when every trust precondition holds; anything else is "invalid".
parsed=$(jq -r '
  if (type != "object") then "invalid"
  elif ((.captured_at? // null) | type) != "string" then "invalid"
  elif ((.context_window? // null) | type) != "object" then "invalid"
  elif (.context_window.current_usage? // null) == null then "invalid"
  elif ((.context_window.used_percentage? // null) | type) != "number" then "invalid"
  elif (.context_window.used_percentage < 0) or (.context_window.used_percentage > 100) then "invalid"
  else "\(.captured_at) \(.context_window.used_percentage)"
  end' "$snap" 2>/dev/null) || unknown
[[ -n "$parsed" && "$parsed" != "invalid" ]] || unknown
ts=${parsed%% *}
used=${parsed#* }

# Staleness: GNU date (-d, Git Bash/Linux) with a BSD (-j -f, macOS) fallback.
now_epoch=$(date -u +%s 2>/dev/null) || unknown
snap_epoch=$(date -u -d "$ts" +%s 2>/dev/null ||
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null) || unknown
[[ "$snap_epoch" =~ ^[0-9]+$ ]] || unknown
age=$((now_epoch - snap_epoch))
# Small negative tolerance for clock skew; a snapshot from the future beyond
# that is as untrustworthy as a stale one.
((age >= -60 && age <= STALENESS_SECONDS)) || unknown

# Band resolution: zones.json override when present and valid, shipped
# defaults otherwise (with a visible notice when the file exists but is bad).
smart_max=$DEFAULT_SMART_MAX
acceptable_max=$DEFAULT_ACCEPTABLE_MAX
zones="$HOME/.claude/context-guard/zones.json"
if [[ -e "$zones" ]]; then
  bands=$(jq -r '
    if (type == "object")
      and ((.smart_max_used_percentage? // null) | type) == "number"
      and ((.acceptable_max_used_percentage? // null) | type) == "number"
      and (.smart_max_used_percentage > 0)
      and (.smart_max_used_percentage < .acceptable_max_used_percentage)
      and (.acceptable_max_used_percentage <= 100)
    then "\(.smart_max_used_percentage) \(.acceptable_max_used_percentage)"
    else "invalid"
    end' "$zones" 2>/dev/null) || bands="invalid"
  if [[ -z "$bands" || "$bands" == "invalid" ]]; then
    printf 'context-guard: zones.json malformed — using shipped default bands (%s/%s)\n' \
      "$DEFAULT_SMART_MAX" "$DEFAULT_ACCEPTABLE_MAX" >&2
  else
    smart_max=${bands%% *}
    acceptable_max=${bands#* }
  fi
fi

# Float-safe comparison; band uppers are inclusive.
awk -v u="$used" -v s="$smart_max" -v a="$acceptable_max" 'BEGIN {
  if (u <= s) print "smart"
  else if (u <= a) print "acceptable"
  else print "dumb"
}' 2>/dev/null || unknown
exit 0
