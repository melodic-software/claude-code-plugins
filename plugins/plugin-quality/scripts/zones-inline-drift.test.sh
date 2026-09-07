#!/usr/bin/env bash
# Drift check: plugin-quality's copy of the context-guard zone floor must stay
# byte-identical (value-level) to the context-guard reader contract that owns
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
# Byte-identity of the resolver against its canonical is a different gate
# (scripts/sync-context-zone.sh --check). This lane covers what that one
# cannot: a value moving in the reader contract without the resolver moving
# with it, or the reverse.
#
# The contract's combination-rule sentence is deliberately not asserted here.
# The resolver states the same rule in its own wording, and the resolver is a
# synced byte-identical file this repo does not reword to satisfy a grep.
#
# Every load-bearing phrase must appear in BOTH files of its pair after
# normalization (backticks/emphasis stripped, whitespace flattened), so a value
# change on either side fails this lane until both move together.
#
# SKIPs (exit 0) outside the monorepo checkout: an installed plugin cache is
# per-plugin isolated and cannot see the sibling plugin's contract file --
# the lane is meaningful only where both files exist (repo CI's plugin-gate).

# shellcheck disable=SC2088  # the ~/ strings are documented contract PHRASES being grep-matched as data, never paths this script expands
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/context-zone.sh"
SKILL="$SCRIPT_DIR/../skills/audit/SKILL.md"
CONTRACT="$SCRIPT_DIR/../../context-guard/reference/reader-contract.md"

if [[ ! -r "$CONTRACT" ]]; then
  echo "SKIP: context-guard reader contract not reachable (installed-cache isolation) — drift lane runs in the monorepo only"
  exit 0
fi
for f in "$RESOLVER" "$SKILL"; do
  if [[ ! -r "$f" ]]; then
    echo "FAIL: required file missing or unreadable: $f" >&2
    exit 1
  fi
done

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
RESOLVER_N=$(norm "$RESOLVER")
SKILL_N=$(norm "$SKILL")
CONTRACT_N=$(norm "$CONTRACT")

# both <consumer-haystack> <consumer-label> <label> <fixed-phrase>
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
skill_and_contract() {
  both "$SKILL_N" "skills/audit/SKILL.md" "$1" "$2"
}

resolver_and_contract "staleness window (10 minutes)" "10 minutes"
resolver_and_contract "snapshot path pattern" "~/.claude/context-guard/context/<session_id>.json"
resolver_and_contract "zones file path" "~/.claude/context-guard/zones.json"
resolver_and_contract "percentage floor" "smart ≤ 50 < acceptable ≤ 75 < dumb"
resolver_and_contract "200k-class token band" "200000: smart ≤ 100000 < acceptable ≤ 160000 < dumb"
resolver_and_contract "1M-class token band" "1000000: smart ≤ 200000 < acceptable ≤ 400000 < dumb"
resolver_and_contract "occupancy definition" "total_input_tokens + total_output_tokens"
resolver_and_contract "token-shape version floor" "cli_version"
resolver_and_contract "token-shape version floor value" "2.1.132"
resolver_and_contract "zone vocabulary" "smart / acceptable / dumb / unknown"

skill_and_contract "evidence-degraded marker path" "<session_id>.compacted"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
