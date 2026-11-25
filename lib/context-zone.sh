#!/usr/bin/env bash

set -uo pipefail

STALENESS_SECONDS=600 # 10 minutes — byte-matches the reader contract
DEFAULT_LIGHT_MAX=50
DEFAULT_MODERATE_MAX=75
DEFAULT_TOKEN_BANDS='[[200000,100000,150000],[1000000,128000,500000]]'

unknown() {
  printf 'unknown\n'
  exit 0
}

sid="${1:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || unknown
command -v jq >/dev/null 2>&1 || unknown
[[ -n "${HOME:-}" ]] || unknown

dir="$HOME/.claude/context-usage"
[[ -r "$dir/context/$sid.json" ]] || dir="$HOME/.claude/context-guard"
snap="$dir/context/$sid.json"
[[ -r "$snap" ]] || unknown

light_max=$DEFAULT_LIGHT_MAX
moderate_max=$DEFAULT_MODERATE_MAX
token_bands=$DEFAULT_TOKEN_BANDS
zones="$HOME/.claude/context-usage/zones.json"
[[ -e "$zones" ]] || zones="$HOME/.claude/context-guard/zones.json"
if [[ -e "$zones" ]]; then
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
  zres=${zres//$'\r'/}
  zpct=${zres%%$'\n'*}
  ztb=${zres#*$'\n'}
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

# printf %(fmt)T needs bash 4.2; on 3.2 printf fails and the clock falls back to date:
# https://tiswww.case.edu/php/chet/bash/NEWS
now_epoch=""
if ! printf -v now_epoch '%(%s)T' -1 2>/dev/null || [[ -z "$now_epoch" ]]; then
  now_epoch=$(date -u +%s 2>/dev/null) || unknown
fi
[[ "$now_epoch" =~ ^[0-9]+$ ]] || unknown

TOKEN_SEMANTICS_MIN_VERSION="2.1.132"

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

case "$zone" in
light | moderate | heavy) printf '%s\n' "$zone" ;;
*) unknown ;;
esac

exit 0
