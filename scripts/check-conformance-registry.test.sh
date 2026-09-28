#!/usr/bin/env bash
# Black-box contract test for check-conformance-registry.sh.
#
# Builds a throwaway tree holding a registry, an owner doc, a script, a plugin
# skill, a repo-local skill and a CI workflow, then mutates one registry row per
# case and asserts on the exit code and the named row. Mutates only its own
# mktemp dir. Registry rows carry literal markdown backticks, never shell
# expansions.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-conformance-registry.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

HEADER='| id | concern | owner | lane | checks | ci | scope |
|---|---|---|---|---|---|---|'
GOOD_ROW='| dim-1 | a concern | docs/owner.md#The rule | judgment: does it hold? | `scripts/existing.sh`, `/p:s`, `/local`, judgment | yes | plugin |'

# mk_tree <out-var> <row>...: a tree whose registry holds the given rows.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label conformance-registry || return 1
  dir="${!1}"
  shift
  mkdir -p "$dir/docs" "$dir/plugins/p/skills/s" "$dir/.claude/skills/local" "$dir/.github/workflows"
  printf '# Owner\n\n## The rule\n\ntext\n\n### A subsection\n' >"$dir/docs/owner.md"
  printf '#!/usr/bin/env bash\n' >"$dir/scripts/existing.sh"
  printf '#!/usr/bin/env bash\n' >"$dir/scripts/not-in-ci.sh"
  printf -- '---\nname: s\n---\n' >"$dir/plugins/p/skills/s/SKILL.md"
  printf -- '---\nname: local\n---\n' >"$dir/.claude/skills/local/SKILL.md"
  printf 'jobs:\n  x:\n    steps:\n      - run: scripts/existing.sh --check\n' >"$dir/.github/workflows/ci.yml"
  {
    printf '# Conformance dimensions\n\n%s\n' "$HEADER"
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } >"$dir/docs/conformance-dimensions.md"
}

# run_case <label> <expected-rc> <expected-substring> <row>...
run_case() {
  local label="$1" expected="$2" needle="$3" tree out rc
  shift 3
  tree=""
  mk_tree tree "$@" || {
    fail "$label: fixture build failed"
    return
  }
  out="$(bash "$tree/scripts/check-conformance-registry.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
  elif [[ -n "$needle" ]] && ! grep -qF -- "$needle" <<<"$out"; then
    fail "$label: output should contain '$needle': $out"
  else
    ok "$label"
  fi
}

run_case "a well-formed row passes" 0 "" "$GOOD_ROW"
run_case "a level-3 owner heading resolves" 0 "" \
  '| dim-1 | c | docs/owner.md#A subsection | judgment: q | judgment | no | fleet |'
run_case "an empty registry fails" 1 "no rows"
run_case "an empty lane fails" 1 "dim-2" \
  "$GOOD_ROW" '| dim-2 | c | docs/owner.md#The rule |  | judgment | no | plugin |'
run_case "empty checks fail" 1 "dim-2" \
  '| dim-2 | c | docs/owner.md#The rule | judgment: q |  | no | plugin |'
run_case "a missing script path fails" 1 "scripts/gone.sh" \
  '| dim-3 | c | docs/owner.md#The rule | run `scripts/gone.sh` | judgment | no | plugin |'
run_case "an unresolved plugin skill fails" 1 "/p:nope" \
  '| dim-4 | c | docs/owner.md#The rule | judgment: q | `/p:nope` | no | plugin |'
run_case "an unresolved repo-local skill fails" 1 "/nope" \
  '| dim-4 | c | docs/owner.md#The rule | judgment: q | `/nope` | no | plugin |'
run_case "a missing owner file fails" 1 "docs/missing.md" \
  '| dim-5 | c | docs/missing.md#The rule | judgment: q | judgment | no | plugin |'
run_case "a missing owner heading fails" 1 "Not a heading" \
  '| dim-6 | c | docs/owner.md#Not a heading | judgment: q | judgment | no | plugin |'
run_case "ci yes with a script CI does not run fails" 1 "scripts/not-in-ci.sh" \
  '| dim-7 | c | docs/owner.md#The rule | judgment: q | `scripts/not-in-ci.sh` | yes | plugin |'
run_case "an unknown scope fails" 1 "dim-8" \
  '| dim-8 | c | docs/owner.md#The rule | judgment: q | judgment | no | galaxy |'
run_case "a duplicate id fails" 1 "dim-1" "$GOOD_ROW" "$GOOD_ROW"

# Missing registry file is an environment error, not a finding.
tree=""
if mk_tree tree "$GOOD_ROW"; then
  rm "$tree/docs/conformance-dimensions.md"
  bash "$tree/scripts/check-conformance-registry.sh" --check >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then ok "a missing registry exits 2"; else fail "a missing registry should exit 2 (rc=$rc)"; fi
else
  fail "missing registry: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then ok "unknown mode exits 2"; else fail "unknown mode should exit 2 (rc=$rc)"; fi

test_harness::report
