#!/usr/bin/env bash
# Tripwire contract test: the review plugin's standards-grounding markers are
# load-bearing (the standards convention's acceptance criteria grep for them) —
# this test fails loudly if a future prose edit drops one.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$PLUGIN_DIR/skills/quality-gate/SKILL.md"
CRITERIA="$PLUGIN_DIR/skills/quality-gate/context/criteria.md"
SETUP="$PLUGIN_DIR/skills/setup/SKILL.md"

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

# --- binding reference present in every consuming surface -------------------
for f in "$GATE" "$CRITERIA" "$SETUP"; do
  if grep -q "reference/standards-contract.md" "$f"; then
    ok "binding reference present in ${f#"$PLUGIN_DIR/"}"
  else
    fail "missing reference/standards-contract.md in ${f#"$PLUGIN_DIR/"}"
  fi
done

# --- criteria.md points at the ladder instead of restating it ---------------
if grep -q "Resolution ladder" "$CRITERIA"; then
  ok "criteria.md points at the binding's Resolution ladder section"
else
  fail "criteria.md lost its pointer to the binding's Resolution ladder section"
fi
# Distinctive contract-only phrasings; their presence means a rung or the setup
# procedure got restated into plugin prose (single-home violation).
for phrase in "present at the resolution root" "exit without interview"; do
  hits=$(grep -l "$phrase" "$GATE" "$CRITERIA" "$SETUP" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then
    ok "no restated contract phrasing: '$phrase'"
  else
    fail "contract phrasing '$phrase' restated in: $hits"
  fi
done

# --- Step 1 item 3 rewired through the index (all modes inherit) ------------
if grep -q "What conventions apply?.*standards index" "$GATE"; then
  ok "quality-gate Step 1 conventions item routes through the standards index"
else
  fail "quality-gate Step 1 'What conventions apply?' lost its standards-index routing"
fi

# --- setup skill keeps its manual-only invocation shape ---------------------
if [[ "$(grep -c "^disable-model-invocation: true" "$SETUP")" -eq 1 ]]; then
  ok "setup skill is user-invoked only (disable-model-invocation: true)"
else
  fail "setup skill frontmatter lost disable-model-invocation: true"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
