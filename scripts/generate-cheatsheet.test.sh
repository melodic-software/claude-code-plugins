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
mk_tree() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/docs" "$dir/.claude-plugin" \
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
    >"$dir/docs/SKILL-CHEAT-SHEET.md"
  write_skill "$dir" alpha mapped \
    'cheatsheet-stage: plan' \
    'cheatsheet-summary: Fixture skill mapped to the plan stage'
  write_skill "$dir" alpha setup
  write_skill "$dir" beta looper \
    'cheatsheet-stage: operator' \
    'cheatsheet-cadence: continuous' \
    'cheatsheet-summary: Fixture operator skill with a cadence'
  printf '%s' "$dir"
}

run_gen() { # run_gen <tree> [extra args...] — stdout+stderr to $OUT, exit code in $CODE
  local tree="$1"
  shift
  OUT="$(node "$GENERATOR" --root "$tree" "$@" 2>&1)"
  CODE=$?
}

# assert_fails <label> <tree> <expected substring>
assert_fails() {
  local label="$1" tree="$2" expected="$3"
  run_gen "$tree"
  if [[ "$CODE" -ne 0 && "$OUT" == *"$expected"* ]]; then
    ok "$label"
  else
    fail "$label (exit=$CODE, output: $OUT)"
  fi
  rm -rf "$tree"
}

# --- green path: generate, idempotent --check, content shape -----------------
tree="$(mk_tree)"
run_gen "$tree"
if [[ "$CODE" -eq 0 ]]; then ok "green generate exits 0"; else fail "green generate (exit=$CODE: $OUT)"; fi
run_gen "$tree" --check
if [[ "$CODE" -eq 0 ]]; then ok "green --check exits 0 after generate"; else fail "green --check (exit=$CODE: $OUT)"; fi
sheet="$(cat "$tree/docs/SKILL-CHEAT-SHEET.md")"
[[ "$sheet" == *"- [3. Plan](#3-plan)"* ]] && ok "TOC anchor emitted" || fail "TOC anchor missing: $sheet"
[[ "$sheet" == *'[`/alpha:mapped`](../plugins/alpha/skills/mapped/SKILL.md)'* ]] \
  && ok "mapped row links its SKILL.md" || fail "mapped row missing: $sheet"
[[ "$sheet" == *"| continuous |"* ]] && ok "operator table carries cadence column" || fail "cadence column missing"
[[ "$sheet" != *"alpha:setup"* ]] && ok "rule-excluded setup skill omitted" || fail "setup skill leaked into sheet"
if command -v npx >/dev/null 2>&1 && npx --no-install markdownlint-cli2 --help >/dev/null 2>&1; then
  if npx --no-install markdownlint-cli2 --config "$REPO_ROOT/.markdownlint-cli2.jsonc" \
    "$tree/docs/SKILL-CHEAT-SHEET.md" >/dev/null 2>&1; then
    ok "fixture sheet is markdownlint-clean"
  else
    fail "fixture sheet fails markdownlint"
  fi
else
  echo "skip: markdownlint-cli2 not installed locally"
fi

# --- drift: hand-edit after generate, --check fails ---------------------------
sed -i.bak 's/Fixture skill mapped to the plan stage/edited by hand/' \
  "$tree/plugins/alpha/skills/mapped/SKILL.md" \
  && rm -f "$tree/plugins/alpha/skills/mapped/SKILL.md.bak"
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"drift"* ]]; then ok "--check fails on drift"; else fail "drift not detected (exit=$CODE: $OUT)"; fi
rm -rf "$tree"

# --- enforcement failure modes -------------------------------------------------
tree="$(mk_tree)"
write_skill "$tree" alpha mapped # metadata stripped entirely
assert_fails "missing cheatsheet-stage names the skill" "$tree" \
  "alpha/mapped: no cheatsheet-stage and no exclusion entry"

tree="$(mk_tree)"
write_skill "$tree" alpha setup 'cheatsheet-stage: plan' \
  'cheatsheet-summary: Excluded skill wrongly carrying a stage'
assert_fails "excluded skill carrying stage is a conflict" "$tree" \
  "alpha/setup: excluded (infra setup) but carries cheatsheet-* metadata"

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: design' \
  'cheatsheet-summary: Unknown stage enum value'
assert_fails "unknown stage enum" "$tree" 'unknown cheatsheet-stage "design"'

tree="$(mk_tree)"
write_skill "$tree" beta looper 'cheatsheet-stage: operator' \
  'cheatsheet-cadence: hourly' 'cheatsheet-summary: Unknown cadence enum value'
assert_fails "unknown cadence enum" "$tree" 'unknown cheatsheet-cadence "hourly"'

tree="$(mk_tree)"
long_summary="$(printf 'x%.0s' $(seq 1 101))"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  "cheatsheet-summary: $long_summary"
assert_fails "summary over 100 codepoints" "$tree" "exceeds 100 codepoints"

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  'cheatsheet-summary: "quoted summaries are rejected"'
assert_fails "charset guard rejects YAML-special lead" "$tree" \
  "starts with a YAML-special character"

# Remaining summaryError branches (the " #" branch is unreachable through the
# generator — its reader strips trailing comments before the guard — and is
# exercised by the sweep applier and skill-quality's cap check instead).
tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' 'cheatsheet-summary:'
assert_fails "empty summary" "$tree" "empty summary"

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  'cheatsheet-summary: bad: mapping indicator inside'
assert_fails "summary with colon-space" "$tree" 'contains ": "'

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  'cheatsheet-summary: ends with a colon:'
assert_fails "summary with trailing colon" "$tree" "ends with a colon or whitespace"

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  "$(printf 'cheatsheet-summary: has\ttab inside')"
assert_fails "summary with control character" "$tree" "tab or control character"

tree="$(mk_tree)"
write_skill "$tree" alpha mapped 'cheatsheet-stage: plan' \
  'cheatsheet-cadence: daily' 'cheatsheet-summary: Cadence outside operator stage'
assert_fails "cadence without operator stage" "$tree" \
  "cheatsheet-cadence is only valid with cheatsheet-stage operator"

tree="$(mk_tree)"
write_skill "$tree" beta looper 'cheatsheet-stage: operator' \
  'cheatsheet-summary: Operator row with no cadence'
assert_fails "operator without cadence" "$tree" \
  "cheatsheet-stage operator requires cheatsheet-cadence"

tree="$(mk_tree)"
sed -i.bak 's/EXCLUDED_SKILLS = new Map()/EXCLUDED_SKILLS = new Map([["alpha\/ghost", "gone"]])/' \
  "$tree/scripts/cheatsheet-config.mjs" \
  && rm -f "$tree/scripts/cheatsheet-config.mjs.bak"
assert_fails "orphaned exclusion entry" "$tree" \
  'orphaned exclusion: skill "alpha/ghost" does not exist'

# --- blank line inside metadata block does not truncate later keys --------------
tree="$(mk_tree)"
cat >"$tree/plugins/beta/skills/looper/SKILL.md" <<'EOF'
---
name: looper
description: fixture skill for cheat-sheet generator tests
metadata:
  cheatsheet-stage: operator

  cheatsheet-cadence: continuous
  cheatsheet-summary: Keys after a blank line still read
---

# looper
EOF
run_gen "$tree"
if [[ "$CODE" -eq 0 ]] && grep -q "Keys after a blank line still read" "$tree/docs/SKILL-CHEAT-SHEET.md"; then
  ok "blank line inside metadata block is tolerated"
else
  fail "blank line truncated metadata keys (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

# --- spine drift ----------------------------------------------------------------
tree="$(mk_tree)"
printf '## 3. Blueprint (renamed upstream)\n' \
  >"$tree/plugins/session-flow/skills/workflow/context/steps.md"
assert_fails "spine-drift assertion fires on renamed stage" "$tree" "spine drift"

echo
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
