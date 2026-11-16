#!/usr/bin/env bash
# Lease marker + lease-time helpers shared by every work-item-tracker adapter
# (CONTRACT.md "Lease protocol"). Sourced.

[[ -n "${_WIT_LEASE_LOADED:-}" ]] && return 0
readonly _WIT_LEASE_LOADED=1

readonly WIT_LEASE_MARKER='<!-- work-item-lease v1 '
# A lease whose TTL exceeds this is not live, so claim refuses it.
readonly WIT_LEASE_MAX_TTL_HOURS=168
# Clock skew a lease reader tolerates between the provider's timestamps and the local clock.
readonly WIT_LEASE_SKEW_SECONDS=300

# wit_lease_json <marker-line-or-comment-body> — extract the lease JSON from a
# lease marker; empty output when the input is not a lease marker.
#
# Anchored on the FIRST ` -->`, not the body's end: a posted lease may carry a trailing
# footer, and an end-anchored match reads it as no lease, so claim grants and renew refuses.
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

# wit_iso_to_epoch <ISO-8601-UTC> — echo the Unix epoch for a `YYYY-MM-DDTHH:MM:SSZ`
# timestamp, via BSD or GNU date. Returns 1 if neither parses.
wit_iso_to_epoch() {
  local iso="$1"
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null ||
    # portability-ok: BSD attempt above failed (non-BSD host); GNU fallback here (#1510)
    date -u -d "$iso" '+%s' 2>/dev/null ||
    return 1
}

# wit_select_active_lease <lease-comment-rows-json>: set WIT_ACTIVE_LEASE_ID / _JSON to the
# newest NON-superseded lease. Not blind `last`: a backed-off claim supersedes its own newer comment.
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

# wit_lease_winner <lease-comment-rows-json> <now-epoch> <self-id> [<released-fn>]: set
# WIT_WINNER_ID / WIT_WINNER_JSON to the EARLIEST live lease, the one claim arbitration
# (CONTRACT.md "Lease protocol", claim step 4) says holds the item; both empty when no lease
# is live. A newer live lease is a claimant that has not yet backed off and never holds.
# <released-fn>, when given, runs as `<fn> <row-id> <lease-json>` for each live lease other
# than <self-id>; its exit 0 counts that lease as released and arbitration moves on.
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

# wit_newer_live_lease <lease-comment-rows-json> <now-epoch> <self-id>: 0 when a live lease
# has a higher comment id than <self-id>.
wit_newer_live_lease() {
  local row cand
  while IFS= read -r row; do
    cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
    [[ -n "$cand" ]] && wit_lease_is_live "$cand" "$2" && return 0
  done < <(jq -c --argjson self "$3" '.[] | select(.id > $self)' <<<"$1")
  return 1
}

# wit_lease_ttl_seconds <lease-json> — echo total TTL in seconds from ttl_hours and
# optional ttl_minutes. Returns 1 when ttl_hours is missing or non-numeric.
wit_lease_ttl_seconds() {
  local lease="$1" hours minutes
  hours="$(jq -r '.ttl_hours // empty' <<<"$lease")"
  minutes="$(jq -r '.ttl_minutes // 0' <<<"$lease")"
  [[ "$hours" =~ ^[0-9]+$ && "$minutes" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((hours * 3600 + minutes * 60))"
}

# wit_lease_ttl_within_cap <hours> <minutes> — 0 when both are non-negative integers
# whose total is at most WIT_LEASE_MAX_TTL_HOURS.
wit_lease_ttl_within_cap() {
  [[ "$1" =~ ^[0-9]{1,6}$ && "$2" =~ ^[0-9]{1,6}$ ]] &&
    ((10#$1 * 60 + 10#$2 <= WIT_LEASE_MAX_TTL_HOURS * 60))
}

# wit_lease_phase_valid <kind> — 0 when <kind> is a lease phase claim accepts
# (CONTRACT.md "Lease protocol"). A lease with no phase field is an implementation claim.
wit_lease_phase_valid() {
  case "$1" in
  triage | discovery | implementation) return 0 ;;
  *) return 1 ;;
  esac
}

# wit_lease_is_live <lease-json> <now-epoch> — 0 when no superseded_at and not expired.
# A lease renewed more than WIT_LEASE_SKEW_SECONDS after now, or with a TTL over
# WIT_LEASE_MAX_TTL_HOURS, is not live.
wit_lease_is_live() {
  local lease="$1" now_epoch="$2" renewed ttl_seconds renewed_epoch
  [[ -z "$(jq -r '.superseded_at // empty' <<<"$lease")" ]] || return 1
  renewed="$(jq -r '.renewed_at // empty' <<<"$lease")"
  ttl_seconds="$(wit_lease_ttl_seconds "$lease")" || return 1
  ((ttl_seconds > 0 && ttl_seconds <= WIT_LEASE_MAX_TTL_HOURS * 3600)) || return 1
  renewed_epoch="$(wit_iso_to_epoch "$renewed")" || return 1
  ((renewed_epoch <= now_epoch + WIT_LEASE_SKEW_SECONDS && now_epoch < renewed_epoch + ttl_seconds))
}
