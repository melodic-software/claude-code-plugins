#!/usr/bin/env bash
# Drift check: plugin-quality's inlined context-guard floor values must stay
# byte-identical (value-level) to the context-guard reader contract that owns
# them.
#
# This is the consumer-lane drift check the reader contract's "Inline-floor
# ownership" section names. It asserts every load-bearing inlined phrase —
# staleness window, snapshot path, marker path, percentage bands, token
# bands, and the combination-rule sentence — appears in BOTH files after
# normalization (backticks/emphasis stripped, whitespace flattened), so a
# value change on either side fails this lane until both move together.
#
# SKIPs (exit 0) outside the monorepo checkout: an installed plugin cache is
# per-plugin isolated and cannot see the sibling plugin's contract file —
# the lane is meaningful only where both files exist (repo CI's plugin-gate).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../skills/audit/SKILL.md"
CONTRACT="$SCRIPT_DIR/../../context-guard/reference/reader-contract.md"

if [[ ! -r "$CONTRACT" || ! -r "$SKILL" ]]; then
  echo "SKIP: context-guard reader contract not reachable (installed-cache isolation) — drift lane runs in the monorepo only"
  exit 0
fi

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# Normalize: drop markdown emphasis/backticks, flatten all whitespace runs.
norm() {
  tr -d '`*' <"$1" | tr '\n' ' ' | tr -s ' '
}
SKILL_N=$(norm "$SKILL")
CONTRACT_N=$(norm "$CONTRACT")

# both <label> <fixed-phrase>
both() {
  local label="$1" phrase="$2" where=""
  [[ "$CONTRACT_N" == *"$phrase"* ]] || where="reader contract"
  [[ "$SKILL_N" == *"$phrase"* ]] || where="${where:+$where and }plugin-quality SKILL.md"
  if [[ -z "$where" ]]; then
    ok "$label"
  else
    fail "$label: phrase not found in $where: '$phrase'"
  fi
}

both "staleness window (10 minutes)" "10 minutes"
both "snapshot path pattern" "~/.claude/context-guard/context/<session_id>.json"
both "zones file path" "~/.claude/context-guard/zones.json"
both "evidence-degraded marker path" "<session_id>.compacted"
both "percentage floor" "smart ≤ 50 < acceptable ≤ 75 < dumb"
both "200k-class token band" "200000: smart ≤ 100000 < acceptable ≤ 160000 < dumb"
both "1M-class token band" "1000000: smart ≤ 200000 < acceptable ≤ 400000 < dumb"
both "occupancy definition" "total_input_tokens + total_output_tokens"
both "combination rule sentence" \
  "when both shapes are computable, the worse zone wins (conservative-min); when only one is computable, it stands alone; when neither is, the zone is unknown"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
