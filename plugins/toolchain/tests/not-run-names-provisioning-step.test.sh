#!/usr/bin/env bash
# test-scope: plugins/toolchain/skills/check/SKILL.md
# test-scope: plugins/toolchain/skills/check/context/gates.md
# test-scope: plugins/toolchain/skills/lint/SKILL.md
# The needles quote markdown backticks literally.
# shellcheck disable=SC2016
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)) && printf 'ok: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)) && printf 'FAIL: %s\n' "$1"; }

paragraph() { awk -v p="$2" 'index($0, p) == 1 { print; exit }' "$1"; }

check_rules="$(awk '/^\*\*Declared prerequisites\.\*\*/ { on = 1 } on && /^- With any entry absent/ { print; exit }' \
  "$PLUGIN_DIR/skills/check/SKILL.md")"
gates_rule="$(paragraph "$PLUGIN_DIR/skills/check/context/gates.md" '- **Declared prerequisites.**')"
lint_rule="$(paragraph "$PLUGIN_DIR/skills/lint/SKILL.md" 'Declared prerequisites:')"

for needle in 'skip (prerequisite missing: <name>)' '`install` object' '`provision-prerequisites.sh` in the source-control plugin'; do
  if grep -qF -- "$needle" <<<"$check_rules"; then ok "check's not-run rule carries: $needle"; else fail "check's not-run rule carries: $needle"; fi
done
for pair in "gates.md|$gates_rule" "lint/SKILL.md|$lint_rule"; do
  where="${pair%%|*}" text="${pair#*|}"
  for needle in 'skip (prerequisite missing: <name>)' '`install` object, the provisioning step that installs it'; do
    if grep -qF -- "$needle" <<<"$text"; then ok "$where not-run rule carries: $needle"; else fail "$where not-run rule carries: $needle"; fi
  done
done

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
