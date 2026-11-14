#!/usr/bin/env bash
# Unit tests for generate-cheatsheet.mjs. Each scenario builds a throwaway
# fixture tree (config + marketplace + skills + spine + scaffold sheet) under
# mktemp and drives the generator through --root: the green generate/--check
# path, every enforcement failure mode (missing stage, excluded-but-mapped
# conflict, unknown stage/cadence enums, summary cap, charset guard, cadence
# coupling, orphaned exclusion), drift detection, and the spine-drift
# assertion. The fixture config re-exports the REAL summaryError so the guard
# the generator enforces in tests is the shipped one, not a copy.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SELF_DIR/generate-cheatsheet.mjs"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

# file:// URL for the real config (Windows Git Bash needs the drive-letter
# form; pwd -W emits it there and fails harmlessly elsewhere).
REAL_SCRIPTS_DIR="$(cd "$SELF_DIR" && (pwd -W 2>/dev/null || pwd))"
case "$REAL_SCRIPTS_DIR" in
/*) REAL_CONFIG_URL="file://$REAL_SCRIPTS_DIR/cheatsheet-config.mjs" ;;
*) REAL_CONFIG_URL="file:///$REAL_SCRIPTS_DIR/cheatsheet-config.mjs" ;;
esac

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
tree=""

# write_skill <dir> <plugin> <skill> [metadata lines...]
write_skill() {
  local dir="$1" plugin="$2" skill="$3"
  shift 3
  mkdir -p "$dir/plugins/$plugin/skills/$skill"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$skill"
    printf 'description: fixture skill for cheat-sheet generator tests\n'
    if (($# > 0)); then
      printf 'metadata:\n'
      local line
      for line in "$@"; do
        printf '  %s\n' "$line"
      done
    fi
    printf -- '---\n\n# %s\n' "$skill"
  } >"$dir/plugins/$plugin/skills/$skill/SKILL.md"
}

# mk_tree — baseline green fixture: one mapped skill, one rule-excluded setup
# skill, one operator skill; single-stage spine.
mk_tree() { # <out-var>
  local dir
  fixture_tree::build "$1" || return 1
  dir="${!1}"
  mkdir -p "$dir/docs" "$dir/.claude-plugin" \
    "$dir/plugins/session-flow/skills/workflow/context"
  cat >"$dir/scripts/cheatsheet-config.mjs" <<EOF
export { CADENCES, summaryError } from "$REAL_CONFIG_URL";
export const STAGES = [
  { slug: "plan", heading: "3. Plan", workflow: true },
  { slug: "operator", heading: "Operator cadence", workflow: false },
];
export const EXCLUDED_PLUGINS = new Map();
export const EXCLUDED_SKILL_NAME = { name: "setup", reason: "infra setup" };
export const EXCLUDED_SKILLS = new Map();
EOF
  cat >"$dir/.claude-plugin/marketplace.json" <<'EOF'
{
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha" },
    { "name": "beta", "source": "./plugins/beta" }
  ]
}
EOF
  printf '## 3. Plan (fixture spine)\n' \
    >"$dir/plugins/session-flow/skills/workflow/context/steps.md"
  printf '# Skill cheat sheet (fixture)\n\n<!-- cheatsheet:start -->\n<!-- cheatsheet:end -->\n' \
    >"$dir/docs/skill-cheat-sheet.md"
  write_skill "$dir" alpha mapped \
    'workflow-stage: plan' \
    'summary: Fixture skill mapped to the plan stage'
  write_skill "$dir" alpha setup
  write_skill "$dir" beta looper \
    'workflow-stage: operator' \
    'cadence: continuous' \
    'summary: Fixture operator skill with a cadence'
}

run_gen() { # run_gen <tree> [extra args...] — stdout+stderr to $OUT, exit code in $CODE
  local tree="$1"
  shift
  OUT="$(node "$GENERATOR" --root "$tree" "$@" 2>&1)"
  CODE=$?
}

# assert_fails <label> <tree> <expected substring>: generate fails naming the
# defect and leaves the sheet byte-unchanged.
assert_fails() {
  local label="$1" tree="$2" expected="$3" before
  before="$(od -c "$tree/docs/skill-cheat-sheet.md")"
  run_gen "$tree"
  if [[ "$CODE" -ne 0 && "$OUT" == *"$expected"* && "$(od -c "$tree/docs/skill-cheat-sheet.md")" == "$before" ]]; then
    ok "$label"
  else
    fail "$label (exit=$CODE, output: $OUT)"
  fi
  rm -rf "$tree"
}

# --- green path: generate, idempotent --check, content shape -----------------
mk_tree tree
run_gen "$tree"
if [[ "$CODE" -eq 0 ]]; then ok "green generate exits 0"; else fail "green generate (exit=$CODE: $OUT)"; fi
run_gen "$tree" --check
if [[ "$CODE" -eq 0 ]]; then ok "green --check exits 0 after generate"; else fail "green --check (exit=$CODE: $OUT)"; fi
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$sheet" == *"- [3. Plan](#3-plan)"* ]]; then
  ok "TOC anchor emitted"
else
  fail "TOC anchor missing: $sheet"
fi
if [[ "$sheet" == *"[\`/alpha:mapped\`](../plugins/alpha/skills/mapped/SKILL.md)"* ]]; then
  ok "mapped row links its SKILL.md"
else
  fail "mapped row missing: $sheet"
fi
if [[ "$sheet" == *"| continuous |"* ]]; then
  ok "operator table carries cadence column"
else
  fail "cadence column missing"
fi
if [[ "$sheet" != *"alpha:setup"* ]]; then
  ok "rule-excluded setup skill omitted"
else
  fail "setup skill leaked into sheet"
fi
if command -v npx >/dev/null 2>&1 && npx --no-install markdownlint-cli2 --help >/dev/null 2>&1; then
  if npx --no-install markdownlint-cli2 --config "$REPO_ROOT/.markdownlint-cli2.jsonc" \
    "$tree/docs/skill-cheat-sheet.md" >/dev/null 2>&1; then
    ok "fixture sheet is markdownlint-clean"
  else
    fail "fixture sheet fails markdownlint"
  fi
else
  echo "skip: markdownlint-cli2 not installed locally"
fi

# --- drift: hand-edit after generate, --check fails ---------------------------
sed -i.bak 's/Fixture skill mapped to the plan stage/edited by hand/' \
  "$tree/plugins/alpha/skills/mapped/SKILL.md" &&
  rm -f "$tree/plugins/alpha/skills/mapped/SKILL.md.bak"
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"drift"* ]]; then ok "--check fails on drift"; else fail "drift not detected (exit=$CODE: $OUT)"; fi
# The drift DETAIL comes from scripts/lib/report-first-difference.mjs, the block
# shared with scripts/generate-catalog.mjs. Assert on it separately: the header
# line above is emitted by this generator, so a helper that threw or fell silent
# would leave the case above green and the regression unseen.
if [[ "$OUT" == *"First difference at generated line "* && "$OUT" == *"expected: "* && "$OUT" == *"found:    "* ]]; then
  ok "drift report names the first differing generated line"
else
  fail "drift detail missing (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

# --- enforcement failure modes -------------------------------------------------
mk_tree tree
write_skill "$tree" alpha mapped # metadata stripped entirely
assert_fails "missing workflow-stage names the skill" "$tree" \
  "alpha/mapped: no workflow-stage and no exclusion entry"

mk_tree tree
write_skill "$tree" alpha setup 'workflow-stage: plan' \
  'summary: Excluded skill wrongly carrying a stage'
assert_fails "excluded skill carrying stage is a conflict" "$tree" \
  "alpha/setup: excluded (infra setup) but carries workflow-stage/summary/cadence metadata"

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: design' \
  'summary: Unknown stage enum value'
assert_fails "unknown stage enum" "$tree" 'unknown workflow-stage "design"'

mk_tree tree
write_skill "$tree" beta looper 'workflow-stage: operator' \
  'cadence: hourly' 'summary: Unknown cadence enum value'
assert_fails "unknown cadence enum" "$tree" 'unknown cadence "hourly"'

mk_tree tree
long_summary="$(printf 'x%.0s' $(seq 1 101))"
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  "summary: $long_summary"
assert_fails "summary over 100 codepoints" "$tree" "exceeds 100 codepoints"

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  'summary: "quoted summaries are rejected"'
assert_fails "charset guard rejects YAML-special lead" "$tree" \
  "starts with a YAML-special character"

# Remaining summaryError branches, plus the generator's own raw-value check:
# a trailing " #" comment on a swept key is rejected from the RAW value before
# comment-strip semantics apply, so a hand-edit cannot silently truncate.
mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  'summary: truncated by a trailing # comment'
assert_fails "trailing comment on a swept key" "$tree" \
  'carries a trailing " #" comment'

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' 'summary:'
assert_fails "empty summary" "$tree" "empty summary"

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  'summary: bad: mapping indicator inside'
assert_fails "summary with colon-space" "$tree" 'contains ": "'

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  'summary: ends with a colon:'
assert_fails "summary with trailing colon" "$tree" "ends with a colon or whitespace"

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  "$(printf 'summary: has\ttab inside')"
assert_fails "summary with control character" "$tree" "tab or control character"

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' \
  'cadence: daily' 'summary: Cadence outside operator stage'
assert_fails "cadence without operator stage" "$tree" \
  "cadence is only valid with workflow-stage operator"

mk_tree tree
write_skill "$tree" beta looper 'workflow-stage: operator' \
  'summary: Operator row with no cadence'
assert_fails "operator without cadence" "$tree" \
  "workflow-stage operator requires cadence"

mk_tree tree
sed -i.bak 's/EXCLUDED_SKILLS = new Map()/EXCLUDED_SKILLS = new Map([["alpha\/ghost", "gone"]])/' \
  "$tree/scripts/cheatsheet-config.mjs" &&
  rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
assert_fails "orphaned exclusion entry" "$tree" \
  'orphaned exclusion: skill "alpha/ghost" does not exist'

# --- blank line inside metadata block does not truncate later keys --------------
mk_tree tree
cat >"$tree/plugins/beta/skills/looper/SKILL.md" <<'EOF'
---
name: looper
description: fixture skill for cheat-sheet generator tests
metadata:
  workflow-stage: operator

  cadence: continuous
  summary: Keys after a blank line still read
---

# looper
EOF
run_gen "$tree"
if [[ "$CODE" -eq 0 ]] && grep -q "Keys after a blank line still read" "$tree/docs/skill-cheat-sheet.md"; then
  ok "blank line inside metadata block is tolerated"
else
  fail "blank line truncated metadata keys (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

# --- Actions and Next columns -----------------------------------------------------
# write_rich_skill <dir> <plugin> <skill> <argument-hint line or ""> <body>
write_rich_skill() {
  local dir="$1" plugin="$2" skill="$3" hint="$4" body="$5"
  mkdir -p "$dir/plugins/$plugin/skills/$skill"
  {
    printf -- '---\nname: %s\ndescription: fixture skill for cheat-sheet generator tests\n' "$skill"
    [[ -n "$hint" ]] && printf '%s\n' "$hint"
    printf 'metadata:\n  workflow-stage: plan\n  summary: Fixture row for %s\n---\n\n# %s\n\n%s\n' \
      "$skill" "$skill" "$body"
  } >"$dir/plugins/$plugin/skills/$skill/SKILL.md"
}

row_of() { # row_of <tree> <plugin:skill>: the sheet row for that skill
  grep -F "[\`/$2\`]" "$1/docs/skill-cheat-sheet.md"
}

mk_tree tree
write_rich_skill "$tree" alpha hinted \
  'argument-hint: "[audit|fix [<file>:<line>]|sweep --all|<target>|this branch] [--json]"' \
  "$(printf '## Next\n\n- Findings to fix: /beta:looper --apply.\n- Nothing found: %s.\n\n## Gotchas\n\n- /alpha:setup is outside the Next section.' "\`/alpha:mapped\`")"
write_rich_skill "$tree" alpha single \
  "argument-hint: '[topic]'" \
  "$(printf '## Next\n\n/alpha:hinted audit <path>, which reads the report this run wrote.')"
run_gen "$tree"
if [[ "$CODE" -eq 0 ]]; then ok "skills with argument-hint and ## Next generate"; else fail "rich fixture (exit=$CODE: $OUT)"; fi
row="$(row_of "$tree" alpha:hinted)"
if [[ "$row" == *"| \`audit\`, \`fix\`, \`sweep\` | \`/beta:looper\`, \`/alpha:mapped\` |" ]]; then
  ok "Actions are the first group's action words; Next follows the bullet shape in order"
else
  fail "hinted row: $row"
fi
row="$(row_of "$tree" alpha:single)"
if [[ "$row" == *"Fixture row for single |  | \`/alpha:hinted\` |" ]]; then
  ok "a hint with no choice of actions renders an empty Actions cell; Next reads the one-line shape"
else
  fail "single row: $row"
fi
row="$(row_of "$tree" alpha:mapped)"
if [[ "$row" == *"Fixture skill mapped to the plan stage |  |  |" ]]; then
  ok "no argument-hint and no ## Next render empty cells"
else
  fail "mapped row: $row"
fi
row="$(row_of "$tree" beta:looper)"
if [[ "$row" == *"| continuous | Fixture operator skill with a cadence |  |  |" ]]; then
  ok "operator rows carry the Actions and Next columns after the cadence"
else
  fail "looper row: $row"
fi
rm -rf "$tree"

mk_tree tree
write_rich_skill "$tree" alpha hinted "" \
  "$(printf '## Next\n\n/alpha:ghost <topic>.')"
assert_fails "a ## Next naming a skill not in the tree fails" "$tree" \
  "alpha/hinted: ## Next names /alpha:ghost, which is not a skill in this tree"

# --- spine drift ----------------------------------------------------------------
mk_tree tree
printf '## 3. Blueprint (renamed upstream)\n' \
  >"$tree/plugins/session-flow/skills/workflow/context/steps.md"
assert_fails "spine-drift assertion fires on renamed stage" "$tree" "spine drift"

# --- marker forms: either form is read, and regenerating keeps the one found -----
OLD_START='<!-- cheatsheet:start -->'
OLD_END='<!-- cheatsheet:end -->'
GEN_START='<!-- BEGIN GENERATED: cheatsheet. Run node scripts/generate-cheatsheet.mjs -->'
GEN_END='<!-- END GENERATED: cheatsheet -->'

write_sheet() { # write_sheet <tree> <marker line...>
  local tree="$1"
  shift
  {
    printf '# Skill cheat sheet (fixture)\n\n'
    printf '%s\n' "$@"
  } >"$tree/docs/skill-cheat-sheet.md"
}

mk_tree tree
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"$OLD_START"$'\n'* && "$sheet" == *$'\n'"$OLD_END"* &&
  "$sheet" == *"/alpha:mapped"* && "$sheet" != *"BEGIN GENERATED"* ]]; then
  ok "regenerating a start/end sheet keeps the start/end markers"
else
  fail "start/end form not kept (exit=$CODE: $sheet)"
fi
rm -rf "$tree"

mk_tree tree
write_sheet "$tree" "$GEN_START" "$GEN_END"
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"drift"* ]]; then
  ok "--check on an empty BEGIN GENERATED block reports drift"
else
  fail "empty BEGIN GENERATED block passed --check (exit=$CODE: $OUT)"
fi
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"$GEN_START"$'\n'* && "$sheet" == *$'\n'"$GEN_END"* &&
  "$sheet" == *"/alpha:mapped"* && "$sheet" != *"cheatsheet:start"* ]]; then
  ok "regenerating a BEGIN GENERATED sheet keeps the BEGIN GENERATED markers"
else
  fail "BEGIN GENERATED form not kept (exit=$CODE: $sheet)"
fi
run_gen "$tree" --check
if [[ "$CODE" -eq 0 ]]; then ok "--check passes on a regenerated BEGIN GENERATED sheet"; else fail "BEGIN GENERATED --check (exit=$CODE: $OUT)"; fi
rm -rf "$tree"

mk_tree tree
write_sheet "$tree" "$OLD_START" "$OLD_END" "$GEN_START" "$GEN_END"
assert_fails "a sheet with both marker forms fails" "$tree" "carries markers of more than one form"

mk_tree tree
write_sheet "$tree" "$OLD_START"
assert_fails "a start marker with no end marker fails" "$tree" "has unbalanced markers"

mk_tree tree
write_sheet "$tree" "$GEN_END" "$GEN_START"
assert_fails "an end marker before its start marker fails" "$tree" "has unbalanced markers"

mk_tree tree
write_sheet "$tree" "$GEN_START" "$GEN_END" "$GEN_START" "$GEN_END"
assert_fails "a repeated marker pair fails" "$tree" "has unbalanced markers"

mk_tree tree
write_sheet "$tree" '<!-- BEGIN GENERATED: cheatsheet. Run something else -->' "$GEN_END"
assert_fails "a BEGIN GENERATED line with other instruction text fails naming the expected line" "$tree" \
  "differs from the expected line $GEN_START"

mk_tree tree
write_sheet "$tree" "$OLD_START" "$OLD_END" "$GEN_END"
run_gen "$tree"
if [[ "$CODE" -ne 0 && "$OUT" == *"more than one form"* && "$OUT" == *"$GEN_END"* && "$OUT" != *"BEGIN GENERATED"* ]]; then
  ok "the more-than-one-form message lists the stray end marker found, not an absent start"
else
  fail "more-than-one-form message (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
write_sheet "$tree" "no markers here"
assert_fails "a sheet with no markers fails, naming the BEGIN GENERATED pair first" "$tree" \
  "is missing the cheatsheet markers ($GEN_START ... $GEN_END or $OLD_START ... $OLD_END)"

test_harness::report
