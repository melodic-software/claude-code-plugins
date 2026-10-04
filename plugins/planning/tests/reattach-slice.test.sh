#!/usr/bin/env bash
# The plan, prd, and design hubs' mandatory gates stay inside the compaction
# re-attach slice (#4255). The stand-in for 5,000 tokens is the first 20,000
# bytes. A phrase that also appears after that cut is a gate the re-attach can
# drop. The interview hub's full gate rules stay where interview-defenses.test.sh
# pins them, past the cut; its "## Gates" block restates them early and is
# asserted here.
#
# shellcheck disable=SC2016  # single quotes are deliberate: assert_gate phrases are verbatim
# markdown lines that hold literal backticks, and expanding them would break the match.
# test-scope: plugins/planning/skills/*/SKILL.md
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

slice=""
tail=""
load_hub() {
  local hub="$PLUGIN_DIR/skills/$1/SKILL.md"
  slice="$(head -c 20000 "$hub")"
  tail=""
  if [[ "$(wc -c <"$hub" | tr -d ' ')" -gt 20000 ]]; then
    tail="$(tail -c +20001 "$hub")"
  fi
}

assert_gate() {
  local phrase="$1"
  if [[ "$slice" == *"$phrase"* && "$tail" != *"$phrase"* ]]; then
    ok "inside the re-attach slice: $phrase"
  else
    fail "not confined to the re-attach slice: $phrase"
  fi
}

load_hub plan
assert_gate 'Hard-to-reverse decisions escalate EARLY'
assert_gate 'Route a phase to an agent team only when'
assert_gate '### Step 4.7: Outcome gate'
assert_gate 'The gate does not vanish when no human is present.'
assert_gate 'dispatch a fresh-context plan-reviewer sub-agent'
assert_gate '### Step 5: Present for Approval'
assert_gate 'The plan is a proposal, not a commitment.'

load_hub prd
assert_gate 'run this mandatory check'
assert_gate 'If it matches the skip conditions, STOP and tell the user'
assert_gate 'never silently overwrite it'
assert_gate 'Do NOT auto-clear or auto-invoke.'
assert_gate 'ask ONE question'

load_hub design
assert_gate 'Never autonomously decide design.'
assert_gate 'is withheld, recorded as a `deferred` thread'
assert_gate 'MUST produce `design-resolution.md`'
assert_gate '## Handoff gate (`handoff` action)'
assert_gate 'This skill carries no gate criteria of its own'

load_hub interview
assert_gate '## Gates'
assert_gate "**The user's decisions are never synthesized.**"
assert_gate '**A gap during `lock` synthesis halts the run.**'
assert_gate '**The register gate runs before the contract locks.**'
assert_gate 'Full rule: Step 3, "Register gate".'

if grep -q '^## Execution-shape analysis$' "$PLUGIN_DIR/skills/plan/context/plan-template.md"; then
  ok 'step 4.5 analysis lives in the plan template'
else
  fail 'step 4.5 analysis lives in the plan template'
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
