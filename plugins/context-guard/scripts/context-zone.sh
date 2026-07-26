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
# unparsable snapshot → unknown; current_usage null or missing (documented
# early-session and post-/compact statusline states — a compacted session's
# numbers are not evidence) → unknown; jq absent → unknown. The resolver
# never throttles a consumer on data it cannot trust and never fabricates a
# zone. Exit code is always 0 — the word is the contract.
#
# TWO ZONE SHAPES, ONE COMBINATION RULE (reader contract, "Occupancy and
# combination rule"):
#
#   percentage shape — context_window.used_percentage against the percentage
#     bands. Upstream computes used_percentage from INPUT tokens only
#     (input + cache_creation + cache_read; no output — statusline doc), so
#     it answers "distance to compaction".
#   token shape — occupancy = total_input_tokens + total_output_tokens
#     against the window-class token bands. Occupancy counts BOTH directions
#     because both occupy the window, and degradation research tracks
#     absolute tokens in context, not window fraction. It answers "distance
#     to quality loss". The two shapes are different units answering
#     different questions — never equate them without normalizing.
#
#   Combination: when both shapes are computable, the WORSE zone wins
#   (conservative-min). When only one is computable, it stands alone. When
#   neither is, the zone is unknown.
#
# TOKEN-SHAPE VERSION GATE: total_input_tokens / total_output_tokens mean
# *current context occupancy* only since Claude Code 2.1.132 — before that
# they were cumulative session totals, which would misfire the bands badly.
# A cumulative total is NOT observable from the numbers alone: 170k
# cumulative in a 200k window is a perfectly plausible current occupancy and
# resolves dumb while the live context may be nowhere near it. So the token
# shape requires the snapshot's cli_version to be >= 2.1.132; an absent,
# malformed, or older version marks it not-computable and leaves the
# percentage shape to stand alone. A second, independent plausibility guard
# still rejects occupancy greater than context_window_size (corrupt data, or
# a snapshot whose version field was forged).
#
# SHIPPED DEFAULT BANDS (zones.json absent = zero-config): percentage bands
# smart ≤ 50 < acceptable ≤ 75 < dumb over used_percentage, and per
# window-class token bands over occupancy:
#
#   window class 200000:  smart ≤ 100000 < acceptable ≤ 160000 < dumb
#   window class 1000000: smart ≤ 200000 < acceptable ≤ 400000 < dumb
#
# All are declared judgment defaults, NOT doc- or benchmark-derived
# constants (anchors and provenance are recorded in the reader contract).
# zones.json is the operator's tuning path:
#
#   {
#     "smart_max_used_percentage": 50,
#     "acceptable_max_used_percentage": 75,
#     "token_bands": {
#       "200000":  { "smart_max_tokens": 100000, "acceptable_max_tokens": 160000 },
#       "1000000": { "smart_max_tokens": 200000, "acceptable_max_tokens": 400000 }
#     }
#   }
#
# Window-class selection: the band row whose class key is the LARGEST one
# ≤ context_window_size. A window smaller than every configured class has no
# row — the token shape is not-computable for it (never borrow a larger
# class's looser bands).
#
# Each shape's configuration is validated independently: malformed
# percentage keys fall back to the shipped percentage defaults with a
# visible stderr notice (unchanged v1 behavior); a malformed token_bands
# object falls back to the shipped token bands with its own notice; an
# ABSENT token_bands key is zero-config (shipped token defaults, silent) so
# a v1 percentage-only zones.json keeps working unchanged. The resolver only
# ever READS zones.json; seeding/refreshing it is the setup skill's `apply`.

set -uo pipefail

STALENESS_SECONDS=600 # 10 minutes — byte-matches the reader contract
DEFAULT_SMART_MAX=50
DEFAULT_ACCEPTABLE_MAX=75
# "class smart_max acceptable_max" rows, ascending class order.
DEFAULT_TOKEN_BANDS=$'200000 100000 160000\n1000000 200000 400000'

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

# One validation pass over the snapshot. Trust gates (shape, captured_at,
# embedded session_id equal to the REQUESTED id — the seam is per-session and
# a copied/renamed snapshot must not answer for another session, non-null
# current_usage) emit "invalid"; past them it emits one line
# "captured_at ver pct ti to cws" where each measurement field is a number or
# the literal x when that field is null / missing / out of documented range,
# and ver is the snapshot's cli_version string or x.
parsed=$(jq -r --arg sid "$sid" '
  if (type != "object") then "invalid"
  elif ((.captured_at? // null) | type) != "string" then "invalid"
  elif (.session_id? // null) != $sid then "invalid"
  elif ((.context_window? // null) | type) != "object" then "invalid"
  elif (.context_window.current_usage? // null) == null then "invalid"
  else
    [ .captured_at,
      (if ((.cli_version? // null) | type) == "string" and (.cli_version | test("^[0-9]+(\\.[0-9]+)*$"))
        then .cli_version else "x" end),
      (if ((.context_window.used_percentage? // null) | type) == "number"
          and (.context_window.used_percentage >= 0)
          and (.context_window.used_percentage <= 100)
        then (.context_window.used_percentage | tostring) else "x" end),
      (if ((.context_window.total_input_tokens? // null) | type) == "number"
          and (.context_window.total_input_tokens >= 0)
        then (.context_window.total_input_tokens | tostring) else "x" end),
      (if ((.context_window.total_output_tokens? // null) | type) == "number"
          and (.context_window.total_output_tokens >= 0)
        then (.context_window.total_output_tokens | tostring) else "x" end),
      (if ((.context_window.context_window_size? // null) | type) == "number"
          and (.context_window.context_window_size > 0)
        then (.context_window.context_window_size | tostring) else "x" end)
    ] | join(" ")
  end' "$snap" 2>/dev/null) || unknown
[[ -n "$parsed" && "$parsed" != "invalid" ]] || unknown
read -r ts ver pct ti to cws <<<"$parsed" || unknown

# Strict ISO-8601 UTC format gate BEFORE any date parsing: GNU date -d also
# accepts natural-language values ("now", "1 second ago") that would let a
# forged captured_at defeat the staleness check. Untrusted data is validated
# to the documented format, then parsed — never handed to a lenient parser.
[[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || unknown

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
# defaults otherwise (with a visible notice when a present shape is bad).
smart_max=$DEFAULT_SMART_MAX
acceptable_max=$DEFAULT_ACCEPTABLE_MAX
token_bands=$DEFAULT_TOKEN_BANDS
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
  # token_bands is optional (a v1 percentage-only file is zero-config for the
  # token shape); when PRESENT it must validate as a whole or the shipped
  # token bands apply with a notice.
  tb=$(jq -r '
    if (.token_bands? // null) == null then "absent"
    elif ((.token_bands | type) == "object")
      and ((.token_bands | length) > 0)
      and (.token_bands | to_entries | all(
        (.key | test("^[0-9]+$"))
        and ((.value | type) == "object")
        and ((.value.smart_max_tokens? // null) | type) == "number"
        and ((.value.acceptable_max_tokens? // null) | type) == "number"
        and (.value.smart_max_tokens > 0)
        and (.value.smart_max_tokens < .value.acceptable_max_tokens)
        and (.value.acceptable_max_tokens <= (.key | tonumber))
      ))
    then (.token_bands | to_entries
      | sort_by(.key | tonumber)
      | map("\(.key) \(.value.smart_max_tokens) \(.value.acceptable_max_tokens)")
      | join("\n"))
    else "invalid"
    end' "$zones" 2>/dev/null) || tb="invalid"
  if [[ "$tb" == "invalid" || -z "$tb" ]]; then
    printf 'context-guard: zones.json token_bands malformed — using shipped default token bands (200000:100000/160000, 1000000:200000/400000)\n' >&2
  elif [[ "$tb" != "absent" ]]; then
    token_bands=$tb
  fi
fi

# Percentage shape: used_percentage against the percentage bands.
pct_zone="x"
if [[ "$pct" != "x" ]]; then
  pct_zone=$(awk -v u="$pct" -v s="$smart_max" -v a="$acceptable_max" 'BEGIN {
    if (u <= s) print "smart"
    else if (u <= a) print "acceptable"
    else print "dumb"
  }' 2>/dev/null) || pct_zone="x"
fi

# Token-shape version gate: the token fields carry current-occupancy
# semantics only from TOKEN_SEMANTICS_MIN_VERSION on. Compared component by
# component in awk — deliberately NOT `sort -V`, which is a GNU-only
# construct this repo's portability lane rejects. Missing components compare
# as 0, so "2.2" reads as 2.2.0; a version the jq gate already rejected
# arrives as x and fails here.
TOKEN_SEMANTICS_MIN_VERSION="2.1.132"
version_at_least() { # <candidate> <minimum>
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  awk -F. -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = (na > nb ? na : nb)
    for (i = 1; i <= n; i++) {
      av = (i <= na ? x[i] + 0 : 0); bv = (i <= nb ? y[i] + 0 : 0)
      if (av > bv) exit 0
      if (av < bv) exit 1
    }
    exit 0
  }' 2>/dev/null
}

# Token shape: occupancy = total_input_tokens + total_output_tokens against
# the selected window-class row. Requires the version gate above, plus the
# independent plausibility guard that occupancy above the window size is
# impossible as current occupancy (corrupt or forged data).
tok_zone="x"
if [[ "$ti" != "x" && "$to" != "x" && "$cws" != "x" ]] &&
  version_at_least "$ver" "$TOKEN_SEMANTICS_MIN_VERSION"; then
  tok_zone=$(awk -v ti="$ti" -v to="$to" -v cws="$cws" '
    BEGIN { occ = ti + to; cls = -1 }
    {
      # rows arrive "class smart acceptable", ascending: keep the largest
      # class that fits inside this window.
      if ($1 + 0 <= cws + 0 && $1 + 0 > cls) { cls = $1 + 0; s = $2; a = $3 }
    }
    END {
      if (occ > cws) { print "x"; exit }   # plausibility guard
      if (cls < 0) { print "x"; exit }      # window smaller than every class
      if (occ <= s) print "smart"
      else if (occ <= a) print "acceptable"
      else print "dumb"
    }' <<<"$token_bands" 2>/dev/null) || tok_zone="x"
fi

# Combination rule (verbatim in the reader contract): both computable → the
# worse zone wins; one computable → it stands alone; neither → unknown.
rank() {
  case "$1" in
  smart) printf '0' ;;
  acceptable) printf '1' ;;
  dumb) printf '2' ;;
  *) printf 'x' ;;
  esac
}
pr=$(rank "$pct_zone")
tr_=$(rank "$tok_zone")
if [[ "$pr" == "x" && "$tr_" == "x" ]]; then
  unknown
fi
worst=-1
[[ "$pr" != "x" ]] && ((pr > worst)) && worst=$pr
[[ "$tr_" != "x" ]] && ((tr_ > worst)) && worst=$tr_
case "$worst" in
0) printf 'smart\n' ;;
1) printf 'acceptable\n' ;;
2) printf 'dumb\n' ;;
*) printf 'unknown\n' ;;
esac
exit 0
