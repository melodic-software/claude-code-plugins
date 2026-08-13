#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=legacy-frontier-tier-signal.sh
source "$SCRIPT_DIR/legacy-frontier-tier-signal.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

assert_match() {
  local name="$1" body="$2"
  if wit_body_has_legacy_frontier_tier_signal "$body"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_no_match() {
  local name="$1" body="$2"
  if wit_body_has_legacy_frontier_tier_signal "$body"; then
    fail "$name"
  else
    pass "$name"
  fi
}

assert_match "capability tier colon frontier" $'## Agent Brief\nCapability tier: frontier\n'
assert_match "capability-tier label form in body" $'capability-tier: frontier\n'
assert_match "stamped for the frontier capability tier" \
  'Item stamped for the frontier capability tier during triage.'
assert_match "frontier-tier quota guard phrase" \
  'This item runs under the frontier-tier quota guard.'
assert_match "bold capability tier in brief" $'**Capability tier:** frontier\n'

assert_no_match "empty body" ''
assert_no_match "generic security-surface dispatch mention" \
  'Security-surface work routes to the frontier capability tier for model selection.'
assert_no_match "already has label only in labels not body" \
  'Fix the README link.'

if [[ "$FAILED" -eq 0 ]]; then
  exit 0
fi
exit 1
