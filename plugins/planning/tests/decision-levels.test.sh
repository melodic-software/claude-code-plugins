#!/usr/bin/env bash
# test-scope: plugins/planning/skills/*/SKILL.md
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/test-ok-fail.sh
source "$PLUGIN_DIR/lib/test-ok-fail.sh"

check_level() {
  local skill="$1" level="$2" file count
  file="$PLUGIN_DIR/skills/$skill/SKILL.md"
  count=$(grep -c "^\*\*Level this skill decides: $level\*\*" "$file")
  if [[ "$count" -eq 1 ]]; then
    ok "$skill SKILL.md declares exactly one '$level' level line"
  else
    fail "expected exactly 1 '$level' level line in $skill SKILL.md, got $count"
  fi
}

check_level interview "behavior"
check_level design "interfaces and contracts"
check_level plan "files and symbols"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
