#!/usr/bin/env bash
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

write_steps() {
  local dir="$1"
  shift
  {
    printf 'A conditional stage runs only when its trigger holds; otherwise it is\nskipped.\n\n'
    printf '%s\n\n' "${STEPS_HEADING:-## 3. Plan (fixture spine)}"
    printf 'Stages 2-4 are detours: the interview calls one, and the work returns\nto it.\n'
    if (($# > 0)); then
      printf '\n## Task kinds\n\n| Kind | Stages, in order | Skips | Why |\n| --- | --- | --- | --- |\n'
      printf '%s\n' "$@"
    fi
  } >"$dir/plugins/session-flow/skills/workflow/context/steps.md"
}

mk_tree() {
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
  write_steps "$dir" '| Fixture kind | Plan | None | fixture reason |'
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

run_gen() {
  local tree="$1"
  shift
  OUT="$(node "$GENERATOR" --root "$tree" "$@" 2>&1)"
  CODE=$?
}

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

sed -i.bak 's/Fixture skill mapped to the plan stage/edited by hand/' \
  "$tree/plugins/alpha/skills/mapped/SKILL.md" &&
  rm -f "$tree/plugins/alpha/skills/mapped/SKILL.md.bak"
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"drift"* ]]; then ok "--check fails on drift"; else fail "drift not detected (exit=$CODE: $OUT)"; fi
if [[ "$OUT" == *"First difference at generated line "* && "$OUT" == *"expected: "* && "$OUT" == *"found:    "* ]]; then
  ok "drift report names the first differing generated line"
else
  fail "drift detail missing (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
write_skill "$tree" alpha mapped
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

row_of() {
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
if [[ "$row" == *"| \`audit\`, \`fix\`, \`sweep\` | \`[audit\\|fix [<file>:<line>]\\|sweep --all\\|<target>\\|this branch] [--json]\` |  | \`/beta:looper\`, \`/alpha:mapped\` |" ]]; then
  ok "Actions are the first group's action words; Arguments is the whole hint, pipes escaped; Next follows the bullet shape in order"
else
  fail "hinted row: $row"
fi
row="$(row_of "$tree" alpha:single)"
if [[ "$row" == *"Fixture row for single |  | \`[topic]\` |  | \`/alpha:hinted\` |" ]]; then
  ok "a hint with no choice of actions renders an empty Actions cell; Next reads the one-line shape"
else
  fail "single row: $row"
fi
row="$(row_of "$tree" alpha:mapped)"
if [[ "$row" == *"Fixture skill mapped to the plan stage |  |  |  |  |" ]]; then
  ok "no argument-hint and no ## Next render empty cells"
else
  fail "mapped row: $row"
fi
row="$(row_of "$tree" beta:looper)"
if [[ "$row" == *"| continuous | Fixture operator skill with a cadence |  |  |  |  |" ]]; then
  ok "operator rows carry the Actions, Arguments, Upstream and Next columns after the cadence"
else
  fail "looper row: $row"
fi
rm -rf "$tree"

mk_tree tree
write_rich_skill "$tree" alpha flagged \
  'argument-hint: "[--output change-prep|explain] [scope]"' ""
write_rich_skill "$tree" alpha angled 'argument-hint: "<role|all> [workload]"' ""
write_rich_skill "$tree" alpha squared 'argument-hint: "[role|all] [workload]"' ""
write_rich_skill "$tree" alpha marked 'argument-hint: "<<role>|all> [workload]"' ""
write_rich_skill "$tree" alpha switched \
  'argument-hint: "[--ledger|--tools T1,T2|fix] [--unattended]"' ""
run_gen "$tree"
row="$(row_of "$tree" alpha:flagged)"
if [[ "$CODE" -eq 0 && "$row" == *"Fixture row for flagged |  | \`[--output change-prep\\|explain] [scope]\` |"* ]]; then
  ok "a first group led by a flag and its value yields no actions (its value choices are not actions)"
else
  fail "flagged row (exit=$CODE: $OUT; row: $row)"
fi
for skill in angled squared; do
  row="$(row_of "$tree" "alpha:$skill")"
  if [[ "$row" == *"Fixture row for $skill | \`role\`, \`all\` |"* ]]; then
    ok "a first group's choices are actions in $skill brackets"
  else
    fail "$skill row: $row"
  fi
done
row="$(row_of "$tree" alpha:marked)"
if [[ "$row" == *"Fixture row for marked | \`all\` |"* ]]; then
  ok "a <name> placeholder among the choices is not an action"
else
  fail "marked row: $row"
fi
row="$(row_of "$tree" alpha:switched)"
if [[ "$row" == *"Fixture row for switched | \`fix\` |"* ]]; then
  ok "a first group whose first choice is a bare flag still yields its action words"
else
  fail "switched row: $row"
fi
rm -rf "$tree"

mk_tree tree
write_rich_skill "$tree" alpha hinted "" \
  "$(printf '## Next\n\n/alpha:ghost <topic>.')"
run_gen "$tree"
row="$(row_of "$tree" alpha:hinted)"
if [[ "$CODE" -eq 0 && "$row" == *"|  |  |  | \`/alpha:ghost\` |" ]]; then
  ok "a ## Next naming a skill not in the tree renders as written (check-next-graph.py owns that failure)"
else
  fail "ghost successor (exit=$CODE: $OUT; row: $row)"
fi
rm -rf "$tree"

mk_tree tree
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"- [By kind of task](#by-kind-of-task)"* &&
  "$sheet" == *"| Fixture kind | [Plan](#3-plan) |  | None | fixture reason |"* ]]; then
  ok "the by-kind table renders each kind's stages linked to their stage tables; a stage with no command entry shows its name only"
else
  fail "by-kind table (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"| Fixture kind | [Plan](#3-plan) |"* &&
  "$sheet" == *$'## By kind of task\n\nFrom the stage definitions: A conditional stage runs only when its trigger holds; otherwise it is skipped. Stages 2-4 are detours: the interview calls one, and the work returns to it.\n'* ]]; then
  ok "an unconditional stage renders no condition; the lead-in quotes steps.md's conditional and detour sentences"
else
  fail "unconditional stage or lead-in (exit=$CODE: $sheet)"
fi
rm -rf "$tree"

mk_tree tree
STEPS_HEADING='## 3. Plan (conditional: the fixture needs a plan)' \
  write_steps "$tree" '| Fixture kind | Plan | None | fixture reason |'
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"| Fixture kind | [Plan](#3-plan) (conditional: the fixture needs a plan) |"* ]]; then
  ok "a conditional stage renders its heading's condition in the sequence"
else
  fail "conditional stage (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
printf '## 3. Plan (fixture spine)\n\n## Task kinds\n\n| Kind | Stages, in order | Skips | Why |\n| --- | --- | --- | --- |\n| K | Plan | None | r |\n' \
  >"$tree/plugins/session-flow/skills/workflow/context/steps.md"
assert_fails "a steps.md missing the conditional-stage sentence fails naming it" "$tree" \
  'has no sentence starting "A conditional stage runs only when its trigger holds"'

stage_commands() {
  cat >>"$1/scripts/cheatsheet-config.mjs" <<EOF
export const STAGE_COMMANDS = [
  { stage: "plan", skill: "$2", runs: [{ claim: "Fixture claim", basis: "$3" }] },
];
EOF
}

mk_tree tree
printf '\nFirst body line.\nThis skill calls /beta:looper for you.\n' >>"$tree/plugins/alpha/skills/mapped/SKILL.md"
stage_commands "$tree" alpha/mapped "calls /beta:looper for you"
line="$(grep -n "calls /beta:looper for you" "$tree/plugins/alpha/skills/mapped/SKILL.md" | cut -d: -f1)"
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"| Fixture kind | [Plan](#3-plan): \`/alpha:mapped\` | \`/alpha:mapped\`: Fixture claim ([\`plugins/alpha/skills/mapped/SKILL.md:$line\`](../plugins/alpha/skills/mapped/SKILL.md)) | None | fixture reason |"* ]]; then
  ok "a kind's row lists each stage's command in order and its claims cited by path:line"
else
  fail "stage command row (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
stage_commands "$tree" alpha/mapped "a quote the skill does not contain"
assert_fails "a runs-for-you claim whose quote is gone fails naming the entry" "$tree" \
  'stage commands: plan (alpha/mapped) no longer contains its basis quote "a quote the skill does not contain"'

mk_tree tree
stage_commands "$tree" alpha/ghost "anything"
assert_fails "a stage command naming no listed skill fails naming the entry" "$tree" \
  'stage commands: plan names "alpha/ghost", which is not a listed skill'

stage_also() {
  cat >>"$1/scripts/cheatsheet-config.mjs" <<EOF
export const STAGE_COMMANDS = [
  { stage: "plan", skill: "alpha/mapped", also: [{ when: "when the fixture breaks, first", skill: "$2" }] },
];
EOF
}

mk_tree tree
write_skill "$tree" alpha other 'workflow-stage: plan' 'summary: Fixture situational skill'
stage_also "$tree" alpha/other
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"| Fixture kind | [Plan](#3-plan): \`/alpha:mapped\` (when the fixture breaks, first \`/alpha:other\`) |"* ]]; then
  ok "a stage's situational command renders beside its main command with its condition"
else
  fail "situational command (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
stage_also "$tree" alpha/ghost
assert_fails "a situational command naming no listed skill fails naming the entry" "$tree" \
  'stage commands: plan also names "alpha/ghost", which is not a listed skill'

mk_tree tree
stage_also "$tree" beta/looper
assert_fails "a situational command whose skill sits in another stage fails naming the entry" "$tree" \
  'stage commands: plan also names "beta/looper", whose workflow-stage is "operator"'

mk_tree tree
stage_commands "$tree" beta/looper "anything"
assert_fails "a stage command whose skill sits in another stage fails naming the entry" "$tree" \
  'stage commands: plan names "beta/looper", whose workflow-stage is "operator"'

mk_tree tree
write_steps "$tree" '| Fixture kind | Plan | None | fixture reason |' \
  '| Bad kind | Plan, Blueprint | None | names a stage that does not exist |'
assert_fails "a task kind naming a stage steps.md does not define fails naming the kind and the stage" "$tree" \
  'task kinds: "Bad kind" names stage "Blueprint", which steps.md does not define'

mk_tree tree
write_steps "$tree" '| Bad skip | Plan | Blueprint | skips a stage that does not exist |'
assert_fails "a task kind skipping an unknown stage fails naming it" "$tree" \
  'task kinds: "Bad skip" names stage "Blueprint", which steps.md does not define'

mk_tree tree
write_steps "$tree"
assert_fails "a steps.md with no Task kinds table fails" "$tree" \
  "has no Task kinds table"

mk_tree tree
mkdir -p "$tree/docs/upstream"
cat >"$tree/docs/upstream/fixture-upstream.md" <<'EOF'
# Upstream source: fixture

## Attribution table

| Upstream | Ours | Relation |
|---|---|---|
| [`why`](https://example.com/why) | [`alpha:mapped`](../../plugins/alpha/skills/mapped/SKILL.md) | Derived |
| `ghosted` rounds | `alpha:ghost`, `review:code-reviewer` | Partial |

## Not adopted

| Upstream | Ours |
|---|---|
| `skipped` | `beta:looper` |
EOF
cat >>"$tree/scripts/cheatsheet-config.mjs" <<'EOF'
export const UPSTREAM_RECORDS = [{ path: "docs/upstream/fixture-upstream.md", label: "fixture" }];
EOF
run_gen "$tree"
row="$(row_of "$tree" alpha:mapped)"
looper="$(row_of "$tree" beta:looper)"
if [[ "$CODE" -eq 0 && "$row" == *"| [fixture \`why\`](upstream/fixture-upstream.md#attribution-table) |"* &&
  "$looper" != *"skipped"* ]]; then
  ok "a skill an upstream attribution row lists links that record's table; Not adopted rows are not read"
else
  fail "upstream column (exit=$CODE: $OUT; row: $row; looper: $looper)"
fi
rm -rf "$tree"

mk_tree tree
cat >>"$tree/scripts/cheatsheet-config.mjs" <<'EOF'
export const UPSTREAM_RECORDS = [{ path: "docs/upstream/missing.md", label: "missing" }];
EOF
assert_fails "an upstream record with no attribution table fails naming it" "$tree" \
  "upstream record docs/upstream/missing.md has no ## Attribution table"

mk_tree tree
printf '## 3. Blueprint (renamed upstream)\n' \
  >"$tree/plugins/session-flow/skills/workflow/context/steps.md"
assert_fails "spine-drift assertion fires on renamed stage" "$tree" "spine drift"

OLD_START='<!-- cheatsheet:start -->'
OLD_END='<!-- cheatsheet:end -->'
GEN_START='<!-- BEGIN GENERATED: cheatsheet. Run node scripts/generate-cheatsheet.mjs -->'
GEN_END='<!-- END GENERATED: cheatsheet -->'

write_sheet() {
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

map_config() {
  cat >>"$1/scripts/cheatsheet-config.mjs" <<EOF
export const REVIEW_PR_MAP_HEADING = "Review map";
export const REVIEW_PR_AUDIENCES = ["author", "reviewer"];
export const REVIEW_PR_POSTS = ["yes", "no"];
export const REVIEW_PR_MAP = [
  { skill: "$2", job: "Fixture job", audience: ["author", "reviewer"], posts: "$3", basis: "$4" },
];
EOF
}

mk_tree tree
write_skill "$tree" alpha mapped 'workflow-stage: plan' 'summary: Fixture skill mapped to the plan stage'
printf 'It never posts to the PR.\n' >>"$tree/plugins/alpha/skills/mapped/SKILL.md"
map_config "$tree" alpha/mapped no "It never posts to the PR."
run_gen "$tree"
sheet="$(cat "$tree/docs/skill-cheat-sheet.md")"
if [[ "$CODE" -eq 0 && "$sheet" == *"## Review map"* && "$sheet" == *"- [Review map](#review-map)"* &&
  "$sheet" == *"| Fixture job | author, reviewer | no |"* ]]; then
  ok "map row renders with skill link, job, audience and posts"
else
  fail "map row (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

mk_tree tree
map_config "$tree" alpha/mapped no "A quote the skill does not contain"
assert_fails "a map row whose basis quote is gone fails naming the skill" "$tree" \
  "review map: alpha/mapped no longer contains its basis quote"

mk_tree tree
map_config "$tree" alpha/missing no "x"
assert_fails "a map row naming no listed skill fails" "$tree" \
  'review map: "alpha/missing" is not a listed skill'

mk_tree tree
map_config "$tree" alpha/mapped maybe "x"
assert_fails "a map row with an unknown posts value fails" "$tree" \
  'review map: alpha/mapped has unknown posts value "maybe"'

test_harness::report
