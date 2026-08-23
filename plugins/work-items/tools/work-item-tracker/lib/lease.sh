#!/usr/bin/env bash
# Lease marker + lease-time helpers shared by every work-item-tracker adapter
# (CONTRACT.md "Lease protocol"). Sourced.

[[ -n "${_WIT_LEASE_LOADED:-}" ]] && return 0
readonly _WIT_LEASE_LOADED=1

readonly WIT_LEASE_MARKER='<!-- work-item-lease v1 '

# wit_lease_json <marker-line-or-comment-body> — extract the lease JSON from a
# lease marker; empty output when the input is not a lease marker.
#
# Anchored on the FIRST ` -->` after the marker, not on the body ENDING there:
# a comment carrying the lease may have trailing content appended by whatever
# posts it — a bot wrapper's attribution footer, a signature, a CI note. An
# end-anchored match treated every such comment as "not a lease", which is
# silent and dangerous rather than merely lossy: claim's arbitration would find
# no incumbent lease and grant, and renew-lease would refuse to renew a lease it
# had just written. Taking the first ` -->` is also strictly more correct — an
# HTML comment cannot contain `-->`, so the first occurrence always closes it.
wit_lease_json() {
  local body="$1"
  case "$body" in
  "$WIT_LEASE_MARKER"*" -->"*)
    body="${body#"$WIT_LEASE_MARKER"}"
    printf '%s\n' "${body%% -->*}"
    ;;
  *) printf '' ;;
  esac
}

# wit_iso_to_epoch <ISO-8601-UTC> — echo the Unix epoch for a `YYYY-MM-DDTHH:MM:SSZ`
# timestamp. Portable across GNU date (Linux, Git Bash) and BSD date (macOS):
# tries BSD `-j -f` first, falls back to GNU `-d`. Returns 1 if neither parses.
wit_iso_to_epoch() {
  local iso="$1"
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null ||
    # portability-ok: BSD attempt above failed (non-BSD host); GNU fallback here (#1510)
    date -u -d "$iso" '+%s' 2>/dev/null ||
    return 1
}

# wit_select_active_lease <lease-comment-rows-json> — from a JSON array of lease
# comment rows ({id, body, ...}), select the ACTIVE lease = the newest (highest
# id) NON-superseded lease, and set WIT_ACTIVE_LEASE_ID / WIT_ACTIVE_LEASE_JSON
# (both empty when no active lease exists). Not blind `last`: a claim that backs
# off supersedes its own newer comment, so the highest-id comment can be a
# superseded back-off while an earlier comment is the still-active lease.
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
    [[ "$(jq -r '.superseded_at // empty' <<<"$cand")" == "" ]] || continue
    WIT_ACTIVE_LEASE_ID="$(jq -r '.id' <<<"$row")"
    WIT_ACTIVE_LEASE_JSON="$cand"
    break
  done < <(jq -c 'sort_by(.id) | reverse | .[]' <<<"$leases")
  export WIT_ACTIVE_LEASE_ID WIT_ACTIVE_LEASE_JSON
}

# wit_lease_ttl_seconds <lease-json> — echo total TTL in seconds from ttl_hours and
# optional ttl_minutes. Returns 1 when ttl_hours is missing or non-numeric.
wit_lease_ttl_seconds() {
  local lease="$1" hours minutes
  hours="$(jq -r '.ttl_hours // empty' <<<"$lease")"
  minutes="$(jq -r '.ttl_minutes // 0' <<<"$lease")"
  [[ "$hours" =~ ^[0-9]+$ && "$minutes" =~ ^[0-9]+$ ]] || return 1
  echo $((hours * 3600 + minutes * 60))
}

# wit_lease_is_live <lease-json> <now-epoch> — 0 when no superseded_at and not expired.
wit_lease_is_live() {
  local lease="$1" now_epoch="$2" renewed ttl_seconds renewed_epoch
  [[ "$(jq -r '.superseded_at // empty' <<<"$lease")" == "" ]] || return 1
  renewed="$(jq -r '.renewed_at // empty' <<<"$lease")"
  ttl_seconds="$(wit_lease_ttl_seconds "$lease")" || return 1
  ((ttl_seconds > 0)) || return 1
  renewed_epoch="$(wit_iso_to_epoch "$renewed")" || return 1
  ((now_epoch < renewed_epoch + ttl_seconds))
}
