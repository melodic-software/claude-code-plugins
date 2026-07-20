#!/usr/bin/env bash
# Tests for lib/lease.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lease.sh
source "$SCRIPT_DIR/lease.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"

# Portable ISO→epoch (GNU date -d and BSD date -j both handled). 1970-01-01T00:00:01Z = 1.
assert_eq "wit_iso_to_epoch epoch-1" "1" "$(wit_iso_to_epoch '1970-01-01T00:00:01Z')"
assert_eq "wit_iso_to_epoch known ts" "1783828800" "$(wit_iso_to_epoch '2026-07-12T04:00:00Z')"

# Lease-marker JSON extraction.
assert_eq "lease json extracted" '{"holder":"me"}' "$(wit_lease_json '<!-- work-item-lease v1 {"holder":"me"} -->')"
assert_eq "non-marker → empty" "" "$(wit_lease_json 'just a comment')"

# Lease liveness with DETERMINISTIC timestamps (no now-boundary flake — see #1424):
# a lease renewed far in the past is expired regardless of ttl; a fresh lease is
# live; a superseded lease is never live even inside its ttl window.
NOW="$(date -u +%s)"
NOW_ISO="$(date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ)"
PAST_DEAD="$(jq -cn '{renewed_at:"2000-01-01T00:00:00Z", ttl_hours:24}')"
if wit_lease_is_live "$PAST_DEAD" "$NOW"; then fail "past lease expired" "not live" "live"; else pass "past lease expired"; fi
ZERO_TTL_DEAD="$(jq -cn '{renewed_at:"2000-01-01T00:00:00Z", ttl_hours:0}')"
if wit_lease_is_live "$ZERO_TTL_DEAD" "$NOW"; then fail "0-ttl lease not live" "not live" "live"; else pass "0-ttl lease not live"; fi
FRESH_LIVE="$(jq -cn --arg t "$NOW_ISO" '{renewed_at:$t, ttl_hours:24}')"
if wit_lease_is_live "$FRESH_LIVE" "$NOW"; then pass "fresh 24h lease is live"; else fail "fresh 24h lease is live" "live" "not live"; fi
SUPERSEDED="$(jq -cn --arg t "$NOW_ISO" '{renewed_at:$t, ttl_hours:24, superseded_at:$t}')"
if wit_lease_is_live "$SUPERSEDED" "$NOW"; then fail "superseded lease not live" "not live" "live"; else pass "superseded lease not live"; fi

# Active-lease selection: newest NON-superseded lease wins, and it is the marker's
# own selection (a superseded higher-id back-off does not mask the still-active
# earlier lease — the subtlety both renew-lease and reclaim depend on).
mk() { printf '<!-- work-item-lease v1 %s -->' "$1"; }
BODY_A="$(mk "$(jq -cn '{holder:"a"}')")"
BODY_B="$(mk "$(jq -cn '{holder:"b"}')")"
BODY_B_SUP="$(mk "$(jq -cn '{holder:"b", superseded_at:"2020-01-01T00:00:00Z"}')")"

LEASES_ONE="$(jq -cn --arg a "$BODY_A" '[{id:10, body:$a}]')"
wit_select_active_lease "$LEASES_ONE"
assert_eq "select: single active lease id" "10" "$WIT_ACTIVE_LEASE_ID"
assert_eq "select: single active lease holder" "a" "$(jq -r '.holder' <<<"$WIT_ACTIVE_LEASE_JSON")"

# Higher-id (100) is a superseded back-off; the active lease is the earlier id 10.
LEASES_BACKOFF="$(jq -cn --arg a "$BODY_A" --arg b "$BODY_B_SUP" '[{id:10, body:$a}, {id:100, body:$b}]')"
wit_select_active_lease "$LEASES_BACKOFF"
assert_eq "select: superseded back-off does not mask active lease" "10" "$WIT_ACTIVE_LEASE_ID"

# Two live leases: the newest (highest id) wins.
LEASES_TWO_LIVE="$(jq -cn --arg a "$BODY_A" --arg b "$BODY_B" '[{id:10, body:$a}, {id:100, body:$b}]')"
wit_select_active_lease "$LEASES_TWO_LIVE"
assert_eq "select: newest non-superseded lease wins" "100" "$WIT_ACTIVE_LEASE_ID"

# No active lease: all superseded → both out-params empty.
LEASES_NONE="$(jq -cn --arg b "$BODY_B_SUP" '[{id:100, body:$b}]')"
wit_select_active_lease "$LEASES_NONE"
assert_eq "select: no active lease → empty id" "" "$WIT_ACTIVE_LEASE_ID"
assert_eq "select: no active lease → empty json" "" "$WIT_ACTIVE_LEASE_JSON"

[[ $FAILED -eq 0 ]] || exit 1
