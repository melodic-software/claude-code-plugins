#!/usr/bin/env bash
# Fixture tests for check-all-skills-verb-contract.sh, driven through the real
# skill-quality checker and through stubs that stand in for a broken one.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$(cd "$SELF_DIR/.." && pwd)/plugins/skill-quality/scripts/check-skill.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

root=""
fixture_tree::build root --sut check-all-skills-verb-contract.sh --plugins || exit 2
trap 'rm -rf "$root"' EXIT

write_skill() {
  local leaf="$1" description="$2"
  mkdir -p "$root/plugins/demo/skills/$leaf"
  printf -- '---\nname: %s\ndescription: "%s"\n---\n\n# %s\n\nBody.\n' \
    "$leaf" "$description" "$leaf" >"$root/plugins/demo/skills/$leaf/SKILL.md"
}
set_baseline() { printf '# baseline\n%s\n' "$1" >"$root/scripts/verb-contract-baseline.txt"; }

# run <expected-exit> <name> [checker]: run the gate in the fixture.
run() {
  local expected="$1" name="$2" checker="${3:-$CHECKER}" status
  LAST_OUTPUT="$(CHECK_SKILL_BIN="$checker" bash "$root/scripts/check-all-skills-verb-contract.sh" 2>&1)"
  status=$?
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
  else
    bad "$name" "expected exit $expected, got $status; output: $LAST_OUTPUT"
  fi
}

MUTATING='Audit and fix every stale widget in the tree. Use when: the widgets drift.'
READ_ONLY='Audit every stale widget in the tree and report it. Use when: the widgets drift.'

write_skill list "$READ_ONLY"
write_skill audit "$MUTATING"
run 1 "an audit skill whose description advertises mutation fails"
assert_output_contains "the failure names the skill" "plugins/demo/skills/audit"

set_baseline plugins/demo/skills/audit
run 0 "a baselined mismatch passes"

write_skill audit "$READ_ONLY"
run 1 "a baseline row whose skill no longer mismatches fails as stale"
assert_output_contains "the stale row is named" "stale row"

rm -f "$root/scripts/verb-contract-baseline.txt"
run 0 "a clean corpus with no baseline passes"
assert_output_contains "the pass counts both skills" "PASS (2 skills"

stub="$root/stub-checker.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$stub"
run 2 "a checker that exits 0 without a rollup cannot pass the gate" "$stub"

printf '#!/usr/bin/env bash\necho "Error: not a skills root" >&2\nexit 2\n' >"$stub"
run 2 "a checker environment error exits 2" "$stub"
assert_output_contains "the checker's own error is shown" "not a skills root"

printf '#!/usr/bin/env bash\nprintf "\\n1 passed, 0 failed\\n"\n' >"$stub"
run 2 "a rollup that undercounts the skills on disk exits 2" "$stub"

# shellcheck disable=SC2016  # the stub expands its own environment
printf '#!/usr/bin/env bash\n[[ "${CHECK_SKILL_ONLY:-}" == 25 ]] || exit 2\nprintf "\\n2 passed, 0 failed\\n"\n' >"$stub"
run 0 "the checker runs with CHECK_SKILL_ONLY=25" "$stub"

test_harness::report
