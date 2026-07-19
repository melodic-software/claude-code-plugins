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

[[ $FAILED -eq 0 ]] || exit 1
