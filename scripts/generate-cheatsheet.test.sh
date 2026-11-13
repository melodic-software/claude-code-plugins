#!/usr/bin/env bash
# Unit tests for generate-cheatsheet.mjs. Each scenario builds a throwaway
# fixture tree (config + marketplace + skills + spine + scaffold sheet) under
# mktemp and drives the generator through --root: the green generate/--check
# path, every enforcement failure mode (missing stage, excluded-but-mapped
# conflict, unknown stage/cadence enums, summary cap, charset guard, cadence
# coupling, orphaned exclusion), drift detection, the spine-drift
# assertion, and the "By kind of task" view with its Task kinds, stage-command
# and cited runs-for-you failures, the Arguments column and the Upstream
# column. The fixture config re-exports the REAL summaryError so the guard
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
export const STAGE_COMMANDS = new Map([["plan", { skills: ["alpha/mapped"] }]]);
export const RUNS_FOR_YOU = new Map();
export const UPSTREAM_RECORDS = [];
EOF
  cat >"$dir/.claude-plugin/marketplace.json" <<'EOF'
{
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha" },
    { "name": "beta", "source": "./plugins/beta" }
  ]
}
EOF
  printf '%s\n' '## 3. Plan (fixture spine)' '' '## Task kinds' '' \
    '| Kind | Runs, in order | On trigger | Skips |' '| --- | --- | --- | --- |' \
    '| Fix | 3. Plan | none | none |' \
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

# --- by kind of task, Arguments and Upstream columns -----------------------------
mk_tree tree
cat >"$tree/plugins/alpha/skills/mapped/SKILL.md" <<'EOF'
---
name: mapped
description: fixture skill for cheat-sheet generator tests
argument-hint: "[run|check] <target>"
metadata:
  workflow-stage: plan
  summary: Fixture skill mapped to the plan stage
---

# mapped
EOF
mkdir -p "$tree/docs/upstream"
cat >"$tree/docs/upstream/rec.md" <<'EOF'
# Fixture upstream record

## Attribution table

| Upstream | Ours | Relation |
|---|---|---|
| [`up-skill`](https://github.com/o/r/tree/abc/skills/up-skill) | `alpha:mapped` | Derived |
| [Upstream PR #1](https://github.com/o/r/pull/1) | `alpha:mapped` | Pointer |
| [`abc1234`](https://github.com/o/r/commit/abc1234) | `alpha:mapped` | Pointer |
| [`NOTES.md`](https://github.com/o/r/blob/abc/skills/up-skill/NOTES.md) | `alpha:mapped` | Pointer |
EOF
sed -i.bak \
  -e 's|RUNS_FOR_YOU = new Map()|RUNS_FOR_YOU = new Map([["alpha/mapped", [{ does: "Runs the fixture call", cite: "fixture skill for cheat-sheet generator tests" }]]])|' \
  -e 's|UPSTREAM_RECORDS = \[\]|UPSTREAM_RECORDS = [{ label: "Rec", path: "docs/upstream/rec.md", heading: "Attribution table" }]|' \
  "$tree/scripts/cheatsheet-config.mjs" &&
  rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"- [By kind of task](#by-kind-of-task)"* ]]; then
  ok "by-kind section is listed first in the TOC"
else
  fail "by-kind TOC entry missing (exit=$CODE: $OUT)"
fi
if [[ "$sheet" == *"| Fix | \`/alpha:mapped\` | none | none |"* ]]; then
  ok "Task kinds row renders the stage's command in order"
else
  fail "by-kind row missing: $sheet"
fi
if [[ "$sheet" == *"| \`[run\\|check] <target>\` |"* ]]; then
  ok "argument-hint renders as a code span with its pipe escaped"
else
  fail "argument-hint cell missing: $sheet"
fi
if [[ "$sheet" == *'Runs the fixture call ([SKILL.md](../plugins/alpha/skills/mapped/SKILL.md): "fixture skill for cheat-sheet generator tests")'* ]]; then
  ok "runs-for-you claim quotes its cited line"
else
  fail "runs-for-you claim missing: $sheet"
fi
if [[ "$sheet" == *"[Rec \`up-skill\`](upstream/rec.md#attribution-table)"* && "$sheet" != *"PR #1"* &&
  "$sheet" != *"abc1234"* && "$sheet" != *"NOTES.md"* ]]; then
  ok "upstream record row links its table; pull request, commit and file links are not units"
else
  fail "upstream column wrong: $sheet"
fi
rm -rf "$tree"

mk_tree tree
sed -i.bak 's/| Fix | 3. Plan |/| Fix | 4. Build |/' \
  "$tree/plugins/session-flow/skills/workflow/context/steps.md" &&
  rm -f "$tree/plugins/session-flow/skills/workflow/context/steps.md.bak"
assert_fails "Task kinds row naming a stage that does not exist fails naming it" "$tree" \
  'Task kinds row "Fix": unknown stage "4. Build"'

mk_tree tree
sed -i.bak 's/| none | none |/| 3. Plan | none |/' \
  "$tree/plugins/session-flow/skills/workflow/context/steps.md" &&
  rm -f "$tree/plugins/session-flow/skills/workflow/context/steps.md.bak"
assert_fails "Task kinds row listing a stage twice fails" "$tree" \
  'Task kinds row "Fix": stage "3. Plan" listed twice'

mk_tree tree
printf '## 3. Plan (fixture spine)\n' \
  >"$tree/plugins/session-flow/skills/workflow/context/steps.md"
assert_fails "steps.md with no Task kinds table fails" "$tree" 'has no "## Task kinds" table'

mk_tree tree
sed -i.bak 's/STAGE_COMMANDS = new Map(.*);/STAGE_COMMANDS = new Map();/' \
  "$tree/scripts/cheatsheet-config.mjs" &&
  rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
assert_fails "a stage a kind runs with no command fails" "$tree" \
  'Task kinds row "Fix": stage "3. Plan" has no STAGE_COMMANDS entry'

mk_tree tree
sed -i.bak 's|"alpha/mapped"|"alpha/ghost"|' "$tree/scripts/cheatsheet-config.mjs" &&
  rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
assert_fails "a stage command naming a skill not on the sheet fails" "$tree" \
  'stage command "plan": "alpha/ghost" is not a skill on the sheet'

mk_tree tree
sed -i.bak 's|RUNS_FOR_YOU = new Map()|RUNS_FOR_YOU = new Map([["alpha/mapped", [{ does: "x", cite: "no such line" }]]])|' \
  "$tree/scripts/cheatsheet-config.mjs" &&
  rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
assert_fails "a runs-for-you cite on no line fails" "$tree" \
  'cite "no such line" is on 0 lines of SKILL.md, not exactly one'

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
