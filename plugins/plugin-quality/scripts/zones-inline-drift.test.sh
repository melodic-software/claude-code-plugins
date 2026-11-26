#!/usr/bin/env bash
# shellcheck disable=SC2088  # the ~/ strings are documented contract PHRASES being grep-matched as data, never paths this script expands
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
  both "$RESOLVER_N" "scripts/context-zone.sh" "$1" "$2"
}

resolver_and_contract "staleness window (10 minutes)" "10 minutes"
resolver_and_contract "snapshot path pattern" "~/.claude/context-usage/context/<session_id>.json"
resolver_and_contract "zones file path" "~/.claude/context-usage/zones.json"
resolver_and_contract "percentage floor" "light ≤ 50 < moderate ≤ 75 < heavy"
resolver_and_contract "200k-class token band" "200000: light ≤ 100000 < moderate ≤ 150000 < heavy"
resolver_and_contract "1M-class token band" "1000000: light ≤ 128000 < moderate ≤ 500000 < heavy"
resolver_and_contract "occupancy definition" "total_input_tokens + total_output_tokens"
resolver_and_contract "token-shape version floor" "cli_version"
resolver_and_contract "token-shape version floor value" "2.1.132"
resolver_and_contract "zone vocabulary" "light / moderate / heavy / unknown"

both "$SKILL_N" "skills/audit/SKILL.md" "evidence-degraded marker path" "<session_id>.compacted"

drift_report
