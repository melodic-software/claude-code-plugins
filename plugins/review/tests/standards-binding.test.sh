#!/usr/bin/env bash
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

for f in "$GATE" "$CRITERIA" "$SETUP"; do
  if grep -q "reference/standards-contract.md" "$f"; then
    ok "binding reference present in ${f#"$PLUGIN_DIR/"}"
  else
    fail "missing reference/standards-contract.md in ${f#"$PLUGIN_DIR/"}"
  fi
done

if grep -q "Resolution ladder" "$CRITERIA"; then
  ok "criteria.md points at the binding's Resolution ladder section"
else
  fail "criteria.md lost its pointer to the binding's Resolution ladder section"
fi
for phrase in "present at the resolution root" "exit without interview"; do
  hits=$(grep -l "$phrase" "$GATE" "$CRITERIA" "$SETUP" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then
    ok "no restated contract phrasing: '$phrase'"
  else
    fail "contract phrasing '$phrase' restated in: $hits"
  fi
done

if grep -q "What conventions apply?.*standards index" "$GATE"; then
  ok "quality-gate Step 1 conventions item routes through the standards index"
else
  fail "quality-gate Step 1 'What conventions apply?' lost its standards-index routing"
fi

if [[ "$(grep -c "^disable-model-invocation: true" "$SETUP")" -eq 1 ]]; then
  ok "setup skill is user-invoked only (disable-model-invocation: true)"
else
  fail "setup skill frontmatter lost disable-model-invocation: true"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
