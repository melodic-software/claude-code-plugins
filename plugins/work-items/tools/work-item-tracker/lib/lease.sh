#!/usr/bin/env bash
[[ -n "${_WIT_LEASE_LOADED:-}" ]] && return 0
readonly _WIT_LEASE_LOADED=1

readonly WIT_LEASE_MARKER='<!-- work-item-lease v1 '
readonly WIT_LEASE_MAX_TTL_HOURS=168
readonly WIT_LEASE_SKEW_SECONDS=300

wit_lease_json() {
  local body="$1"
  case "$body" in
  "$WIT_LEASE_MARKER"*" -->"*)
    body="${body#"$WIT_LEASE_MARKER"}"
    printf '%s\n' "${body%% -->*}"
    ;;
  *) ;;
  esac
}

wit_iso_to_epoch() {
  local iso="$1"
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null ||
    # portability-ok: BSD attempt above failed (non-BSD host); GNU fallback here (#1510)
    date -u -d "$iso" '+%s' 2>/dev/null ||
    return 1
}

WIT_ACTIVE_LEASE_ID=""
WIT_ACTIVE_LEASE_JSON=""
wit_select_active_lease() {
  local leases="$1" row cand
  WIT_ACTIVE_LEASE_ID=""
  WIT_ACTIVE_LEASE_JSON=""
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
    [[ -n "$cand" ]] || continue
    [[ -z "$(jq -r '.superseded_at // empty' <<<"$cand")" ]] || continue
    WIT_ACTIVE_LEASE_ID="$(jq -r '.id' <<<"$row")"
    WIT_ACTIVE_LEASE_JSON="$cand"
    break
  done < <(jq -c 'sort_by(.id) | reverse | .[]' <<<"$leases")
  export WIT_ACTIVE_LEASE_ID WIT_ACTIVE_LEASE_JSON
}

WIT_WINNER_ID=""
WIT_WINNER_JSON=""
wit_lease_winner() {
  local leases="$1" now_epoch="$2" self="$3" released_fn="${4:-}" row cand row_id
  WIT_WINNER_ID=""
  WIT_WINNER_JSON=""
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
    [[ -n "$cand" ]] || continue
    wit_lease_is_live "$cand" "$now_epoch" || continue
    row_id="$(jq -r '.id' <<<"$row")"
    if [[ -n "$released_fn" && "$row_id" != "$self" ]] && "$released_fn" "$row_id" "$cand"; then
      continue
    fi
    WIT_WINNER_ID="$row_id"
    WIT_WINNER_JSON="$cand"
    break
  done < <(jq -c 'sort_by(.id) | .[]' <<<"$leases")
  export WIT_WINNER_ID WIT_WINNER_JSON
}

wit_newer_live_lease() {
  local leases="$1" now_epoch="$2" self="$3" row cand
  while IFS= read -r row; do
    cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
    [[ -n "$cand" ]] && wit_lease_is_live "$cand" "$now_epoch" && return 0
  done < <(jq -c --argjson self "$self" '.[] | select(.id > $self)' <<<"$leases")
  return 1
}

wit_lease_ttl_seconds() {
  local lease="$1" hours minutes
  hours="$(jq -r '.ttl_hours // empty' <<<"$lease")"
  minutes="$(jq -r '.ttl_minutes // 0' <<<"$lease")"
  [[ "$hours" =~ ^[0-9]+$ && "$minutes" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((hours * 3600 + minutes * 60))"
}

wit_lease_ttl_within_cap() {
  [[ "$1" =~ ^[0-9]{1,6}$ && "$2" =~ ^[0-9]{1,6}$ ]] &&
    ((10#$1 * 60 + 10#$2 <= WIT_LEASE_MAX_TTL_HOURS * 60))
}

wit_lease_phase_valid() {
  case "$1" in
  triage | discovery | implementation) return 0 ;;
  *) return 1 ;;
  esac
}

wit_lease_is_live() {
  local lease="$1" now_epoch="$2" renewed ttl_seconds renewed_epoch
  [[ -z "$(jq -r '.superseded_at // empty' <<<"$lease")" ]] || return 1
  renewed="$(jq -r '.renewed_at // empty' <<<"$lease")"
  ttl_seconds="$(wit_lease_ttl_seconds "$lease")" || return 1
  ((ttl_seconds > 0 && ttl_seconds <= WIT_LEASE_MAX_TTL_HOURS * 3600)) || return 1
  renewed_epoch="$(wit_iso_to_epoch "$renewed")" || return 1
  ((renewed_epoch <= now_epoch + WIT_LEASE_SKEW_SECONDS && now_epoch < renewed_epoch + ttl_seconds))
}
