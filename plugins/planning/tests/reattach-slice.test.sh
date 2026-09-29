#!/usr/bin/env bash
# The plan hub's mandatory gates stay inside the compaction re-attach slice
# (#4255). The stand-in for 5,000 tokens is the first 20,000 bytes. A phrase
# that also appears after that cut is a gate the re-attach can drop.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUB="$PLUGIN_DIR/skills/plan/SKILL.md"

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

slice="$(head -c 20000 "$HUB")"
tail=""
if [[ "$(wc -c <"$HUB" | tr -d ' ')" -gt 20000 ]]; then
  tail="$(tail -c +20001 "$HUB")"
fi

assert_gate() {
  local phrase="$1"
  if [[ "$slice" == *"$phrase"* && "$tail" != *"$phrase"* ]]; then
    ok "inside the re-attach slice: $phrase"
  else
    fail "not confined to the re-attach slice: $phrase"
  fi
}

assert_gate 'Hard-to-reverse decisions escalate EARLY'
assert_gate 'Route a phase to an agent team only when'
assert_gate '### Step 4.7: Outcome gate'
assert_gate 'The gate does not vanish when no human is present.'
assert_gate 'dispatch a fresh-context plan-reviewer sub-agent'
assert_gate '### Step 5: Present for Approval'
assert_gate 'The plan is a proposal, not a commitment.'

if grep -q '^## Execution-shape analysis$' "$PLUGIN_DIR/skills/plan/context/plan-template.md"; then
  ok 'step 4.5 analysis lives in the plan template'
else
  fail 'step 4.5 analysis lives in the plan template'
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
