#!/usr/bin/env bash
# Drift check: plugin-quality's copy of the context-usage zone floor must stay
# byte-identical (value-level) to the context-usage reader contract that owns
# it.
#
# This is the consumer-lane drift check the reader contract's "Inline-floor
# ownership" section names. Two surfaces carry the floor on this side:
#
#   scripts/context-zone.sh   the synced resolver, which owns the staleness
#                             window, both seam paths, the percentage and token
#                             bands, the occupancy definition and the
#                             token-shape version floor.
#   skills/audit/SKILL.md     the evidence-degraded marker path, which the
#                             resolver does not read: that check is
#                             consumer-side and stays in the skill body.
#
# Whether the resolver matches its canonical is a different gate
# (scripts/sync-shared-copies.sh --check). This lane covers what that one
# cannot: a value moving in the reader contract without the resolver moving
# with it, or the reverse.
#
# The contract's combination-rule sentence is deliberately not asserted here.
# The resolver states the same rule in its own wording, and the resolver is a
# synced byte-identical file this repo does not reword to satisfy a grep.
#
# SKIPs (exit 0) outside the monorepo checkout: an installed plugin cache is
# per-plugin isolated and cannot see the sibling plugin's contract file --
# the lane is meaningful only where both files exist (repo CI's plugin-gate).

# shellcheck disable=SC2088,SC2016  # the ~/ and $ strings are contract phrases and resolver code matched as data, never expanded
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/context-zone.sh"
SKILL="$SCRIPT_DIR/../skills/audit/SKILL.md"
CONTRACT="$SCRIPT_DIR/../../context-usage/reference/reader-contract.md"

if [[ ! -r "$CONTRACT" ]]; then
  echo "SKIP: context-usage reader contract not reachable (installed-cache isolation) — drift lane runs in the monorepo only"
  exit 0
fi

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
test_helpers::drift_lane

require_readable "$RESOLVER" "$SKILL"

RESOLVER_N=$(norm "$RESOLVER")
SKILL_N=$(norm "$SKILL")
CONTRACT_N=$(norm "$CONTRACT")

both() {
  local haystack="$1" hay_label="$2" label="$3" phrase="$4" where=""
  [[ "$CONTRACT_N" == *"$phrase"* ]] || where="reader contract"
  [[ "$haystack" == *"$phrase"* ]] || where="${where:+$where and }plugin-quality $hay_label"
  if [[ -z "$where" ]]; then
    ok "$label"
  else
    fail "$label: phrase not found in $where: '$phrase'"
  fi
}

resolver_and_contract() {
  local label="$1" phrase="$2" where="" code
  shift 2
  [[ "$CONTRACT_N" == *"$phrase"* ]] || where="reader contract"
  for code in "$@"; do
    [[ "$RESOLVER_N" == *"$code"* ]] || where="${where:+$where and }plugin-quality scripts/context-zone.sh ('$code')"
  done
  if [[ -z "$where" ]]; then
    ok "$label"
  else
    fail "$label: not found in $where: '$phrase'"
  fi
}

resolver_and_contract "staleness window (10 minutes)" "10 minutes" "STALENESS_SECONDS=600"
resolver_and_contract "snapshot path pattern" "~/.claude/context-usage/context/<session_id>.json" \
  'dir="$HOME/.claude/context-usage"' 'snap="$dir/context/$sid.json"'
resolver_and_contract "zones file path" "~/.claude/context-usage/zones.json" \
  'zones="$HOME/.claude/context-usage/zones.json"'
resolver_and_contract "percentage floor" "light ≤ 50 < moderate ≤ 75 < heavy" \
  "DEFAULT_LIGHT_MAX=50" "DEFAULT_MODERATE_MAX=75"
resolver_and_contract "200k-class token band" "200000: light ≤ 100000 < moderate ≤ 150000 < heavy" \
  "[200000,100000,150000]"
resolver_and_contract "1M-class token band" "1000000: light ≤ 128000 < moderate ≤ 500000 < heavy" \
  "[1000000,128000,500000]"
resolver_and_contract "occupancy definition" "total_input_tokens + total_output_tokens" \
  '$w.total_input_tokens + $w.total_output_tokens'
resolver_and_contract "token-shape version floor" "cli_version" ".cli_version"
resolver_and_contract "token-shape version floor value" "2.1.132" 'TOKEN_SEMANTICS_MIN_VERSION="2.1.132"'
resolver_and_contract "zone vocabulary" "light / moderate / heavy / unknown" \
  "light | moderate | heavy) printf" "printf 'unknown\n'"

both "$SKILL_N" "skills/audit/SKILL.md" "evidence-degraded marker path" "<session_id>.compacted"

drift_report
