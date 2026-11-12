#!/usr/bin/env bash
# GENERATED from lib/context-zone.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# context-zone: resolve a session's context-usage zone from its snapshot.
#
# Usage:
#   context-zone.sh <session_id>
#
# Reads ~/.claude/context-usage/context/<session_id>.json (written by
# context-usage's mod) plus the optional machine-scope
# ~/.claude/context-usage/zones.json override and prints EXACTLY ONE word:
#
#   light / moderate / heavy / unknown
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
# TOKEN-SHAPE VERSION GATE: total_input_tokens / total_output_tokens are read
# as current context occupancy only from the release the changelog names for
# that fix (https://code.claude.com/docs/en/changelog#2-1-132; field meanings at
# https://code.claude.com/docs/en/statusline#context-window-fields; as of
# 2026-10-11, recheck when either section changes what the token fields count).
# Earlier snapshots would misfire the bands badly. A cumulative total is NOT observable from the numbers alone: 170k
# cumulative in a 200k window is a perfectly plausible current occupancy and
# resolves heavy while the live context may be nowhere near it. So the token
# shape requires the snapshot's cli_version to be >= 2.1.132; an absent,
# malformed, or older version marks it not-computable and leaves the
# percentage shape to stand alone. A second, independent plausibility guard
# still rejects occupancy greater than context_window_size (corrupt data, or
# a snapshot whose version field was forged).
#
# SHIPPED DEFAULT BANDS (zones.json absent = zero-config): percentage bands
# light ≤ 50 < moderate ≤ 75 < heavy over used_percentage, and per
# window-class token bands over occupancy:
#
#   window class 200000:  light ≤ 100000 < moderate ≤ 150000 < heavy
#   window class 1000000: light ≤ 128000 < moderate ≤ 500000 < heavy
#
# All are declared judgment defaults, NOT doc- or benchmark-derived
# constants (anchors and provenance are recorded in the reader contract).
# zones.json is the operator's tuning path:
#
#   {
#     "light_max_used_percentage": 50,
#     "moderate_max_used_percentage": 75,
#     "token_bands": {
#       "200000":  { "light_max_tokens": 100000, "moderate_max_tokens": 150000 },
#       "1000000": { "light_max_tokens": 128000, "moderate_max_tokens": 500000 }
#     }
#   }
#
# OLD KEY NAMES: for one release the resolver also reads smart_max_* as
# light_max_* and acceptable_max_* as moderate_max_*, the new name winning
# when both are set (the reader contract's "Zones" section).
#
# LOWERED AUTO-COMPACT WINDOW: when the snapshot's bands.auto_compact_window
# is a number above 0 and below context_window_size (the mod publishes it only
# then), the percentage edges are scaled by auto_compact_window /
# context_window_size, as the mod scales its own, so zones.json percentages are
# of the auto-compact window. Token bands are not scaled. Absent or out of
# range, the edges stay as set.
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
# a v1 percentage-only zones.json keeps working unchanged. Likewise an object
# with NO edge keys whose keys are all known (token_bands, actions,
# approach_margin, thresholds; the last three are read by the mod, not here)
# keeps the shipped percentage bands silently; an unknown key still warns. The resolver only
# ever READS zones.json; seeding/refreshing it is the setup skill's `apply`.

set -uo pipefail

STALENESS_SECONDS=600 # 10 minutes — byte-matches the reader contract
DEFAULT_LIGHT_MAX=50
DEFAULT_MODERATE_MAX=75
# [class, light_max, moderate_max] rows, ascending class order, as JSON
# because the snapshot pass takes the bands as data.
DEFAULT_TOKEN_BANDS='[[200000,100000,150000],[1000000,128000,500000]]'

unknown() {
  printf 'unknown\n'
  exit 0
}

sid="${1:-}"
# Same filename character class the mod's writer accepts — also path containment on
# the read side.
[[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || unknown
command -v jq >/dev/null 2>&1 || unknown
[[ -n "${HOME:-}" ]] || unknown

dir="$HOME/.claude/context-usage"
# Migration: a session still running the plugin under its earlier name writes the
# directory below. Remove this line once every lane has converged on context-usage.
[[ -r "$dir/context/$sid.json" ]] || dir="$HOME/.claude/context-guard"
snap="$dir/context/$sid.json"
[[ -r "$snap" ]] || unknown

# SPAWN DISCIPLINE. This resolver sits on the PostToolBatch path, so it runs
# once per tool batch and every process it starts is paid there. The budget is
# one jq on the common path, and a second only when a zones.json override is
# present. The gates above this line stay in bash and cost nothing, so the
# no-snapshot and hostile-id cases exit without starting anything at all.
# Band resolution therefore runs first and hands the bands to the snapshot
# pass as data, so every comparison happens inside that one jq.
#
# REDIRECTION PLACEMENT. Counting jq invocations is not the same as counting
# processes. Bash elides the extra fork inside `$(...)` and execs the command
# directly in the substitution's subshell, but only when that command carries no
# redirection of its own — so `$(jq … 2>/dev/null)` runs one jq at a cost of TWO
# process creations, while `{ v=$(jq …); } 2>/dev/null` runs the same jq for one.
# Both jq call sites below therefore keep their stderr redirect on the enclosing
# group. Nothing else changes: the same stream is suppressed, stdout is still
# captured, and jq's exit status still reaches the `||`. See #3520.

# Band resolution: zones.json override when present and valid, shipped
# defaults otherwise, with a visible notice for each present shape that is bad.
# One jq pass validates the two shapes INDEPENDENTLY and prints two lines: the
# percentage result, then the token result.
light_max=$DEFAULT_LIGHT_MAX
moderate_max=$DEFAULT_MODERATE_MAX
token_bands=$DEFAULT_TOKEN_BANDS
# The migration moves zones.json before the old directory goes, so the new one wins.
zones="$HOME/.claude/context-usage/zones.json"
[[ -e "$zones" ]] || zones="$dir/zones.json"
if [[ -e "$zones" ]]; then
  # Stderr on the GROUP: see REDIRECTION PLACEMENT above.
  { zres=$(jq -r '
    def alias($new; $old):
      (if (.[$new] // null) == null and (.[$old] // null) != null then .[$new] = .[$old] else . end)
      | del(.[$old]);
    def normalize:
      if type != "object" then .
      else alias("light_max_used_percentage"; "smart_max_used_percentage")
        | alias("moderate_max_used_percentage"; "acceptable_max_used_percentage")
        | if ((.token_bands? // null) | type) == "object"
          then .token_bands |= map_values(
            if type == "object"
            then alias("light_max_tokens"; "smart_max_tokens") | alias("moderate_max_tokens"; "acceptable_max_tokens")
            else . end)
          else . end
      end;
    def pct_ok:
      (type == "object")
      and ((.light_max_used_percentage? // null) | type) == "number"
      and ((.moderate_max_used_percentage? // null) | type) == "number"
      and (.light_max_used_percentage > 0)
      and (.light_max_used_percentage < .moderate_max_used_percentage)
      and (.moderate_max_used_percentage <= 100);
    def pct_absent:
      (type == "object")
      and ((.light_max_used_percentage? // null) == null)
      and ((.moderate_max_used_percentage? // null) == null)
      and (keys | all(IN("token_bands", "actions", "approach_margin", "thresholds")));
    def tb_state:
      if (.token_bands? // null) == null then "absent"
      elif ((.token_bands | type) == "object")
        and ((.token_bands | length) > 0)
        and (.token_bands | to_entries | all(
          (.key | test("^[0-9]+$"))
          and ((.value | type) == "object")
          and ((.value.light_max_tokens? // null) | type) == "number"
          and ((.value.moderate_max_tokens? // null) | type) == "number"
          and (.value.light_max_tokens > 0)
          and (.value.light_max_tokens < .value.moderate_max_tokens)
          and (.value.moderate_max_tokens <= (.key | tonumber))
        ))
      then "valid" else "invalid" end;
    normalize |
    (if pct_ok then "\(.light_max_used_percentage) \(.moderate_max_used_percentage)"
     elif pct_absent then "absent"
     else "invalid" end),
    (tb_state as $s
     | if $s == "valid"
       then (.token_bands | to_entries | sort_by(.key | tonumber)
             | map([(.key | tonumber), .value.light_max_tokens, .value.moderate_max_tokens])
             | tojson)
       else $s end)
  ' "$zones"); } 2>/dev/null || zres=""
  # jq writes CRLF on some hosts and command substitution strips only the
  # trailing terminator, so the separator's carriage return would otherwise
  # ride along on the first line.
  zres=${zres//$'\r'/}
  zpct=${zres%%$'\n'*}
  ztb=${zres#*$'\n'}
  # An unreadable or unparsable file yields no output: both shapes fall back,
  # each with its own notice.
  [[ -n "$zres" && "$ztb" != "$zres" ]] || {
    zpct="invalid"
    ztb="invalid"
  }
  if [[ "$zpct" == "invalid" ]]; then
    printf 'context-usage: zones.json malformed — using shipped default bands (%s/%s)\n' \
      "$DEFAULT_LIGHT_MAX" "$DEFAULT_MODERATE_MAX" >&2
  elif [[ "$zpct" != "absent" ]]; then
    light_max=${zpct%% *}
    moderate_max=${zpct#* }
  fi
  if [[ "$ztb" == "invalid" ]]; then
    printf 'context-usage: zones.json token_bands malformed — using shipped default token bands (200000:100000/150000, 1000000:128000/500000)\n' >&2
  elif [[ "$ztb" != "absent" ]]; then
    token_bands=$ztb
  fi
fi

# `now` from the printf builtin, which starts no process. Its %()T conversion
# arrived in bash 4.2, and stock macOS ships 3.2, which these scripts support:
# there printf fails and binds nothing, so the clock falls back to `date`
# rather than resolving every snapshot to unknown and silently disabling both
# hooks. The pre-assignment keeps `set -u` from aborting the -z test when
# printf bound nothing.
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
# TOKEN-SHAPE VERSION GATE (see the header): versions compare component by
# component, missing components reading as 0, so "2.2" means 2.2.0.
TOKEN_SEMANTICS_MIN_VERSION="2.1.132"

# THE CAPTURED_AT GATE. The strict ISO-8601 format test runs FIRST, so no
# natural-language value ("now", "1 second ago") can let a forged captured_at
# defeat the staleness check. `fromdateiso8601` then parses it, but it
# NORMALIZES a well-formed yet calendar-invalid value instead of refusing it:
# February 30th becomes March 2nd, and second 60 rolls into the next minute.
# So the parsed epoch is formatted back and must equal the input byte for
# byte; anything that does not round-trip is refused.
# Stderr on the GROUP: see REDIRECTION PLACEMENT above.
{ zone=$(jq -r --arg sid "$sid" --arg minver "$TOKEN_SEMANTICS_MIN_VERSION" \
  --argjson now "$now_epoch" --argjson stale "$STALENESS_SECONDS" \
  --argjson smax "$light_max" --argjson amax "$moderate_max" \
  --argjson tbands "$token_bands" '
  def vge($cand; $min):
    ($cand | test("^[0-9]+(\\.[0-9]+)*$"))
    and (($cand | split(".") | map(tonumber)) as $c
      | ($min | split(".") | map(tonumber)) as $m
      | ([($c | length), ($m | length)] | max) as $n
      | (($c + [range($n) | 0]) | .[0:$n]) as $cp
      | (($m + [range($n) | 0]) | .[0:$n]) as $mp
      | $cp >= $mp);
  def rank($v; $s; $a):
    if $v <= $s then 0 elif $v <= $a then 1 else 2 end;
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
        | (.bands? // null) as $b
        | (if (($b | type) == "object")
              and ((($b.auto_compact_window? // null) | type) == "number")
              and ((($w.context_window_size? // null) | type) == "number")
              and ($b.auto_compact_window > 0) and ($w.context_window_size > 0)
              and ($b.auto_compact_window < $w.context_window_size)
           then [($smax * $b.auto_compact_window) / $w.context_window_size,
                 ($amax * $b.auto_compact_window) / $w.context_window_size]
           else [$smax, $amax] end) as $pb
        | (if ((($w.used_percentage? // null) | type) == "number")
              and ($w.used_percentage >= 0) and ($w.used_percentage <= 100)
           then rank($w.used_percentage; $pb[0]; $pb[1]) else null end) as $pz
        | (if ((($w.total_input_tokens? // null) | type) == "number") and ($w.total_input_tokens >= 0)
              and ((($w.total_output_tokens? // null) | type) == "number") and ($w.total_output_tokens >= 0)
              and ((($w.context_window_size? // null) | type) == "number") and ($w.context_window_size > 0)
              and vge((if (((.cli_version? // null) | type) == "string") then .cli_version else "" end); $minver)
           then (($w.total_input_tokens + $w.total_output_tokens) as $occ
             | if $occ > $w.context_window_size then null
               else ($tbands | map(select(.[0] <= $w.context_window_size)) | sort_by(.[0]) | last) as $row
                 | if $row == null then null else rank($occ; $row[1]; $row[2]) end
               end)
           else null end) as $tz
        | [$pz, $tz] | map(select(. != null))
        | if length == 0 then "unknown"
          else max as $worst | ["light", "moderate", "heavy"][$worst] end
      end
  end' "$snap"); } 2>/dev/null || unknown
zone=${zone//$'\r'/}

# The word is the contract. Anything the pass above could not resolve, and
# anything outside the vocabulary, leaves here as unknown.
case "$zone" in
light | moderate | heavy) printf '%s\n' "$zone" ;;
*) unknown ;;
esac

exit 0
