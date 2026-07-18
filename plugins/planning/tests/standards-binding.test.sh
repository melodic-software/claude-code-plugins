#!/usr/bin/env bash
# Tripwire contract test: the planning plugin's standards-grounding markers are
# load-bearing (the standards convention's acceptance criteria grep for them) —
# this test fails loudly if a future prose edit drops or duplicates one.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHITECT="$PLUGIN_DIR/skills/plan/SKILL.md"
SETUP="$PLUGIN_DIR/skills/setup/SKILL.md"
TEMPLATE="$PLUGIN_DIR/skills/plan/context/plan-template.md"
REVIEWER="$PLUGIN_DIR/skills/plan/context/plan-reviewer.md"

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

# --- grounding subsection exists exactly once, inside Step 2 ----------------
count=$(grep -c "Ground in consumer standards" "$ARCHITECT")
if [[ "$count" -eq 1 ]]; then
  ok "plan SKILL.md carries exactly one grounding heading"
else
  fail "expected exactly 1 'Ground in consumer standards' in plan SKILL.md, got $count"
fi

step2=$(grep -n "^### Step 2: Formulate the Plan" "$ARCHITECT" | cut -d: -f1 | head -1)
step3=$(grep -n "^### Step 3:" "$ARCHITECT" | cut -d: -f1 | head -1)
ground=$(grep -n "Ground in consumer standards" "$ARCHITECT" | cut -d: -f1 | head -1)
if [[ -n "$step2" && -n "$step3" && -n "$ground" && "$ground" -gt "$step2" && "$ground" -lt "$step3" ]]; then
  ok "grounding heading sits inside Step 2 (line $ground, between $step2 and $step3)"
else
  fail "grounding heading not inside Step 2 (step2=$step2 ground=$ground step3=$step3)"
fi

# --- binding reference present in both skills -------------------------------
for f in "$ARCHITECT" "$SETUP"; do
  if grep -q "reference/standards-contract.md" "$f"; then
    ok "binding reference present in ${f#"$PLUGIN_DIR/"}"
  else
    fail "missing reference/standards-contract.md in ${f#"$PLUGIN_DIR/"}"
  fi
done

# --- pointer discipline: the ladder is cited, never restated ----------------
if grep -q "Resolution ladder" "$ARCHITECT"; then
  ok "plan SKILL.md points at the binding's Resolution ladder section"
else
  fail "plan SKILL.md lost its pointer to the binding's Resolution ladder section"
fi
# Distinctive contract-only phrasings; their presence means a rung or the setup
# procedure got restated into skill prose (single-home violation).
for phrase in "present at the resolution root" "exit without interview"; do
  hits=$(grep -l "$phrase" "$ARCHITECT" "$SETUP" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then
    ok "no restated contract phrasing: '$phrase'"
  else
    fail "contract phrasing '$phrase' restated in: $hits"
  fi
done

# --- template + reviewer carry the grounding surface ------------------------
if grep -q "Standards grounding" "$TEMPLATE"; then
  ok "plan template carries the Standards grounding element"
else
  fail "plan template lost the Standards grounding element"
fi
if grep -q "standards sections loaded" "$REVIEWER"; then
  ok "plan reviewer carries the standards-citation axis"
else
  fail "plan reviewer lost the standards-citation axis"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
