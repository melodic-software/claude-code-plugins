#!/usr/bin/env bash
# Gate for the <skill-dir> spoke-script convention: spokes under skills/*/context and
# skills/*/reference are read by the Read tool, which substitutes no variables, so they name
# bundled scripts as <skill-dir>/scripts/<name>.sh and SKILL.md renders the placeholder.
# shellcheck disable=SC2016,SC2013  # the dollar-brace tokens are literal text; script names hold no spaces
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="$SCRIPT_DIR/../skills"

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# check_skills <skills-root>: print one line per violation; exit 1 when any.
check_skills() {
  local root="$1" bad=0 spoke skill ref
  for spoke in "$root"/*/context/* "$root"/*/reference/*; do
    [[ -f "$spoke" ]] || continue
    skill="$(dirname "$(dirname "$spoke")")"
    if grep -qF '${CLAUDE_PLUGIN_ROOT}' "$spoke"; then
      echo "plugin-root token in spoke: $spoke"
      bad=1
    fi
    for ref in $(grep -o '<skill-dir>/scripts/[A-Za-z0-9_.-]*\.sh' "$spoke" | sed 's|<skill-dir>/||'); do
      [[ -f "$skill/$ref" ]] || {
        echo "missing script $ref for spoke: $spoke"
        bad=1
      }
    done
  done
  for skill in "$root"/*/; do
    if grep -qs '<skill-dir>' "$skill"context/* "$skill"reference/* && ! grep -qF '${CLAUDE_SKILL_DIR}' "$skill/SKILL.md"; then
      echo "SKILL.md lacks the skill-dir token: $skill"
      bad=1
    fi
  done
  return "$bad"
}

rc=0
OUT=$(check_skills "$SKILLS") || rc=$?
assert_exit "shipped skills satisfy the spoke-script convention" 0 "$rc"
assert_eq "no violations reported" "" "$OUT"

# The gate must be able to fail: inject each defect into a copy of the shipped tree.
# inject <label> <expected-substring> <file under the copy> <sed expression>
inject() {
  local copy="$TEST_TMPDIR/$1"
  mkdir -p "$copy"
  cp -R "$SKILLS/." "$copy/"
  sed -i "$4" "$copy/$3"
  rc=0
  OUT=$(check_skills "$copy") || rc=$?
  assert_exit "$1: rejected" 1 "$rc"
  assert_contains "$1: names the defect" "$OUT" "$2"
}

inject token "plugin-root token" audit/context/audit.md \
  's|<skill-dir>/scripts/audit-spine.sh|${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-spine.sh|'
inject missing "missing script scripts/no-such-script.sh" audit/context/audit.md \
  's|<skill-dir>/scripts/audit-spine.sh|<skill-dir>/scripts/no-such-script.sh|'
inject no-source "lacks the skill-dir token" audit/SKILL.md \
  's|\${CLAUDE_SKILL_DIR}|the skill directory|'

report_and_exit
