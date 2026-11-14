#!/usr/bin/env bash
# Tests for check-map.sh's part-duplicate rule: an id `<module>/<part>` must name one Parts line.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-map.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# A control skill whose one feature, testing, lists the given Parts lines. Prints its directory.
make_skill() { # <case name> <parts lines>
  local root="$TEST_TMPDIR/$1" skill="$TEST_TMPDIR/$1/.claude/skills/control-repo"
  mkdir -p "$skill/features/testing" "$root/plugins/testing/skills/run-e2e"
  : >"$root/plugins/testing/skills/run-e2e/SKILL.md"
  cat >"$skill/SKILL.md" <<'EOF'
# control-repo

## Launch

Start nothing.

## Ready

true

## Capture

logs: the session log

## Cleanup

Stop nothing.

## Features

- testing | features/testing/README.md | entry points: 1 | sources: plugins/testing/skills/*/SKILL.md
EOF
  cat >"$skill/features/testing/README.md" <<EOF
# testing

The skills of the testing plugin.

## Parts

$2

## Sub-features

none

## Entry points

- \`/testing:<skill>\` at the prompt | driven

## Reset

Nothing to reset.

## Drive

1. Run \`/testing:<skill>\` for the part. Result: the skill answers.
2. **Proof.** Result: the answer names the skill. Captures: logs

## Gotchas

- None seen yet.
EOF
  printf '%s' "$skill"
}

run_check() { bash "$CHECK" "$1" 2>&1; }

skill="$(make_skill distinct "- \`run-e2e\`: Start the app.
- \`write\`: Write tests.
- range: the chosen dates.
- **P1.** The first state.")"
assert_equals "distinct code-span, word and bold-id parts print nothing" "$(run_check "$skill")" ""

skill="$(make_skill code-span "- \`run-e2e\`: Start the app.
- \`write\`: Write tests.
- \`run-e2e\`: Drive real flows.")"
assert_equals "two code-span lines naming run-e2e" "$(run_check "$skill")" \
  "part-duplicate | features/testing/README.md | ## Parts names run-e2e more than once"

skill="$(make_skill bold-id "- **P1.** The first state.
- **P2.** The second state.
- **P1.** The first state again.")"
assert_equals "two bold ids P1" "$(run_check "$skill")" \
  "part-duplicate | features/testing/README.md | ## Parts names P1 more than once"

skill="$(make_skill mixed "- range: the chosen dates.
- \`range\`: the dates again.")"
assert_equals "a word and a code span naming the same part" "$(run_check "$skill")" \
  "part-duplicate | features/testing/README.md | ## Parts names range more than once"

skill="$(make_skill prose "- The user signs in.
- The user signs out.")"
assert_equals "prose lines that start alike name no part" "$(run_check "$skill")" ""

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
