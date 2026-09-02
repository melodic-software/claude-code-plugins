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
# [class, smart_max, acceptable_max] rows, ascending class order. JSON rather
# than whitespace rows because the bands are handed to the snapshot pass as
# data, so the comparison happens there instead of in a separate awk process.
DEFAULT_TOKEN_BANDS='[[200000,100000,160000],[1000000,200000,400000]]'

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

# SPAWN DISCIPLINE. This resolver sits on the PostToolBatch path, so it runs
# once per tool batch and every process it starts is paid there. It used to
# spend six: one jq for the snapshot, two `date` for the staleness arithmetic,
# and three `awk` for the band comparisons and the version gate. It now spends
# one jq on the common path, and a second only when a zones.json override is
# present. The gates above this line stay in bash and still cost nothing, so
# the no-snapshot and hostile-id cases exit without starting anything at all.
#
# The band resolution therefore moves AHEAD of the snapshot pass: the resolved
# bands are handed to that one jq as data, so the comparisons happen where the
# snapshot is already parsed instead of in three separate awk processes.

# Band resolution: zones.json override when present and valid, shipped
# defaults otherwise (with a visible notice when a present shape is bad). The
# two shapes are still validated INDEPENDENTLY and still emit their own
# notices; they are read in one jq pass rather than two because both read the
# same file. Output is two lines: the percentage result, then the token result.
smart_max=$DEFAULT_SMART_MAX
acceptable_max=$DEFAULT_ACCEPTABLE_MAX
token_bands=$DEFAULT_TOKEN_BANDS
zones="$HOME/.claude/context-guard/zones.json"
if [[ -e "$zones" ]]; then
  zres=$(jq -r '
    def pct_ok:
      (type == "object")
      and ((.smart_max_used_percentage? // null) | type) == "number"
      and ((.acceptable_max_used_percentage? // null) | type) == "number"
      and (.smart_max_used_percentage > 0)
      and (.smart_max_used_percentage < .acceptable_max_used_percentage)
      and (.acceptable_max_used_percentage <= 100);
    def tb_state:
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
      then "valid" else "invalid" end;
    (if pct_ok then "\(.smart_max_used_percentage) \(.acceptable_max_used_percentage)"
     else "invalid" end),
    (tb_state as $s
     | if $s == "valid"
       then (.token_bands | to_entries | sort_by(.key | tonumber)
             | map([(.key | tonumber), .value.smart_max_tokens, .value.acceptable_max_tokens])
             | tojson)
       else $s end)
  ' "$zones" 2>/dev/null) || zres=""
  # jq writes CRLF on some hosts and command substitution strips only the
  # trailing terminator, so the separator's carriage return would otherwise
  # ride along on the first line.
  zres=${zres//$'\r'/}
  zpct=${zres%%$'\n'*}
  ztb=${zres#*$'\n'}
  # An unreadable or unparsable file yields no output at all: both shapes fall
  # back, and both say so, exactly as two independent failing passes did.
  [[ -n "$zres" && "$ztb" != "$zres" ]] || {
    zpct="invalid"
    ztb="invalid"
  }
  if [[ "$zpct" == "invalid" ]]; then
    printf 'context-guard: zones.json malformed — using shipped default bands (%s/%s)\n' \
      "$DEFAULT_SMART_MAX" "$DEFAULT_ACCEPTABLE_MAX" >&2
  else
    smart_max=${zpct%% *}
    acceptable_max=${zpct#* }
  fi
  if [[ "$ztb" == "invalid" ]]; then
    printf 'context-guard: zones.json token_bands malformed — using shipped default token bands (200000:100000/160000, 1000000:200000/400000)\n' >&2
  elif [[ "$ztb" != "absent" ]]; then
    token_bands=$ztb
  fi
fi

# `now` from the printf builtin rather than `date -u +%s`: same integer, no
# process. The snapshot's own epoch is computed inside the jq pass below.
# The %()T conversion arrived in bash 4.2, and stock macOS ships 3.2, which
# these scripts support: there printf fails and binds nothing, so the clock
# falls back to the `date` this line replaced rather than resolving every
# snapshot to unknown and silently disabling both hooks. The pre-assignment is
# deliberate: under `set -u` a printf that never bound the variable would
# otherwise abort the -z test. On 4.2+ the fallback is never reached and the
# per-resolve budget the test suite asserts by trace still holds.
now_epoch=""
if ! printf -v now_epoch '%(%s)T' -1 2>/dev/null || [[ -z "$now_epoch" ]]; then
  now_epoch=$(date -u +%s 2>/dev/null) || unknown
fi
[[ "$now_epoch" =~ ^[0-9]+$ ]] || unknown

# One pass over the snapshot, carrying every gate and both band comparisons.
# Trust gates (shape, captured_at, embedded session_id equal to the REQUESTED
# id, because the seam is per-session and a copied or renamed snapshot must not
# answer for another session, non-null current_usage) resolve to unknown, as do a
# non-conforming captured_at, a stale or future-dated one, and a snapshot
# whose measurement fields are all out of documented range.
# TOKEN-SHAPE VERSION GATE: the token fields carry current-occupancy semantics
# only from this version on. Compared component by component, missing
# components reading as 0 so "2.2" means 2.2.0. That is the same rule the awk
# gate applied, now an array comparison inside the pass below.
TOKEN_SEMANTICS_MIN_VERSION="2.1.132"

# THE CAPTURED_AT GATE, AND WHY THE ROUND TRIP IS PART OF IT. The strict
# ISO-8601 format test still runs FIRST and still exists to stop a lenient
# parser accepting natural-language values ("now", "1 second ago") that would
# let a forged captured_at defeat the staleness check. `fromdateiso8601` then
# parses it, but unlike `date -u -d` it NORMALIZES a structurally well-formed
# yet calendar-invalid value instead of refusing it: February 30th becomes
# March 2nd, and second 60 rolls into the next minute. Normalizing there would
# quietly widen the gate this code exists to hold. So the parsed epoch is
# formatted back and required to equal the input byte for byte; anything that
# does not round-trip is refused, which restores `date`'s answer on every such
# value. The two implementations part company only for timestamps thousands of
# years from now, and those fail the staleness window either way.
zone=$(jq -r --arg sid "$sid" --arg minver "$TOKEN_SEMANTICS_MIN_VERSION" \
  --argjson now "$now_epoch" --argjson stale "$STALENESS_SECONDS" \
  --argjson smax "$smart_max" --argjson amax "$acceptable_max" \
  --argjson tbands "$token_bands" '
  def vge($cand; $min):
    ($cand | test("^[0-9]+(\\.[0-9]+)*$"))
    and (($cand | split(".") | map(tonumber)) as $c
      | ($min | split(".") | map(tonumber)) as $m
      | ([($c | length), ($m | length)] | max) as $n
      | (($c + [range($n) | 0]) | .[0:$n]) as $cp
      | (($m + [range($n) | 0]) | .[0:$n]) as $mp
      | $cp >= $mp);
  def band($v; $s; $a):
    if $v <= $s then "smart" elif $v <= $a then "acceptable" else "dumb" end;
  if (type != "object") then "unknown"
  elif ((.captured_at? // null) | type) != "string" then "unknown"
  elif (.session_id? // null) != $sid then "unknown"
  elif ((.context_window? // null) | type) != "object" then "unknown"
  elif (.context_window.current_usage? // null) == null then "unknown"
  elif ((.captured_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) | not) then "unknown"
  else
    (try (.captured_at | fromdateiso8601) catch null) as $e
    | if $e == null then "unknown"
      elif ((try ($e | todateiso8601) catch "") != .captured_at) then "unknown"
      elif ((($now - $e) < -60) or (($now - $e) > $stale)) then "unknown"
      else
        .context_window as $w
        | (if ((($w.used_percentage? // null) | type) == "number")
              and ($w.used_percentage >= 0) and ($w.used_percentage <= 100)
           then band($w.used_percentage; $smax; $amax) else null end) as $pz
        | (if ((($w.total_input_tokens? // null) | type) == "number") and ($w.total_input_tokens >= 0)
              and ((($w.total_output_tokens? // null) | type) == "number") and ($w.total_output_tokens >= 0)
              and ((($w.context_window_size? // null) | type) == "number") and ($w.context_window_size > 0)
              and vge((if (((.cli_version? // null) | type) == "string") then .cli_version else "" end); $minver)
           then (($w.total_input_tokens + $w.total_output_tokens) as $occ
             | if $occ > $w.context_window_size then null
               else ($tbands | map(select(.[0] <= $w.context_window_size)) | sort_by(.[0]) | last) as $row
                 | if $row == null then null else band($occ; $row[1]; $row[2]) end
               end)
           else null end) as $tz
        | ([$pz, $tz] | map(select(. != null))) as $zs
        | if ($zs | length) == 0 then "unknown"
          else ($zs | map(if . == "smart" then 0 elif . == "acceptable" then 1 else 2 end) | max
            | if . == 0 then "smart" elif . == 1 then "acceptable" else "dumb" end)
          end
      end
  end' "$snap" 2>/dev/null) || unknown
zone=${zone//$'\r'/}

# The word is the contract. Anything the pass above could not resolve, and
# anything outside the vocabulary, leaves here as unknown.
case "$zone" in
smart | acceptable | dumb) printf '%s\n' "$zone" ;;
*) unknown ;;
esac

exit 0
