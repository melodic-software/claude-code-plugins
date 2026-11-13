#!/usr/bin/env bash
# plan_stress_test and the st-* eval suite that settles its default.
#
# Expected values come from the key contract in reference/config.md: each of the modes plan,
# proposal and incumbent takes auto, reviewer, devils-advocate or both; and from the negative
# control's rule in plugins/playbooks/skills/skill-authoring/reference/rewrite-a-plugin.md: the
# degraded copy keeps its frontmatter and loses its procedure.
# test-scope: plugins/planning/schemas/planning.schema.json
# test-scope: plugins/planning/reference/config.md
# test-scope: plugins/planning/skills/plan/SKILL.md
# test-scope: plugins/planning/evals/fixtures/stress-arm/*
# test-scope: plugins/planning/evals/st-*/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$PLUGIN_DIR/skills/setup/scripts/setup-apply.mjs"
ARM="$PLUGIN_DIR/evals/fixtures/stress-arm"

WORKROOT="$(mktemp -d)"
trap 'chmod -R u+w "$WORKROOT" 2>/dev/null; rm -rf "$WORKROOT"' EXIT
FAKE_HOME="$WORKROOT/home"
mkdir -p "$FAKE_HOME"

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

# check_file <label> <expected exit> <yaml text>: setup-apply --check on a repository holding it.
check_file() {
  local label="$1" expected="$2" text="$3" repo code
  repo="$(mktemp -d "$WORKROOT/repo.XXXXXX")"
  git -C "$repo" init -q
  mkdir -p "$repo/docs/conventions"
  printf '%s\n' "$text" >"$repo/docs/conventions/planning.yaml"
  HOME="$FAKE_HOME" node "$SETUP" --root "$repo" --check >/dev/null 2>&1
  code=$?
  if [[ "$code" -eq "$expected" ]]; then ok "$label"; else fail "$label (exit $code)"; fi
}

check_file 'every mode with every value passes' 0 'plan_stress_test:
  plan: auto
  proposal: reviewer
  incumbent: devils-advocate'
check_file 'one mode alone passes' 0 'plan_stress_test:
  incumbent: both'
check_file 'an unknown mode is refused' 1 'plan_stress_test:
  design: both'
check_file 'a value outside the list is refused' 1 'plan_stress_test:
  plan: never'
check_file 'a flat value is refused' 1 'plan_stress_test: both'

# The key is per mode, and its default matches the eval: auto in each mode.
schema_modes="$(node -e 'const p = require(process.argv[1]).properties.plan_stress_test.properties;
console.log(Object.keys(p).sort().map((k) => k + "=" + p[k].default).join(" "))' \
  "$PLUGIN_DIR/schemas/planning.schema.json" 2>&1)"
if [[ "$schema_modes" == 'incumbent=auto plan=auto proposal=auto' ]]; then
  ok 'the schema has exactly the three modes, each defaulting to auto'
else
  fail "the schema has exactly the three modes, each defaulting to auto (got: $schema_modes)"
fi

# The key resolves through the convention home: config.md lists it under "Convention-home keys" with
# default auto for each mode, and Step 3 of the plan skill resolves it through that section.
section() { awk -v start="$2" -v stop="$3" 'index($0, start) == 1 { on = 1; print; next } on && index($0, stop) == 1 { exit } on' "$1"; }
home_keys="$(section "$PLUGIN_DIR/reference/config.md" '## Convention-home keys' '## ')"
if grep -qE '^\| .plan_stress_test. \|.*\| .auto. for each \|' <<<"$home_keys"; then
  ok 'config.md lists plan_stress_test as a convention-home key defaulting to auto'
else
  fail 'config.md lists plan_stress_test as a convention-home key defaulting to auto'
fi
step3="$(section "$PLUGIN_DIR/skills/plan/SKILL.md" '### Step 3: Plan Stress-Test' '### ')"
for needle in 'plan_stress_test' 'reference/config.md' '"Convention-home keys"'; do
  if grep -qF "$needle" <<<"$step3"; then
    ok "plan Step 3 resolves the key through: $needle"
  else
    fail "plan Step 3 resolves the key through: $needle"
  fi
done

# Each arm's copy runs at verification standard, so the plan-reviewer can be dispatched, and gives
# every mode that arm's value; the copy's file passes the schema.
for value in reviewer devils-advocate both auto; do
  dest="$WORKROOT/copy-$value"
  if ! bash "$ARM/prepare-arm.sh" "$value" "$dest" >/dev/null; then
    fail "prepare-arm $value exits 0"
    continue
  fi
  got="$(cat "$dest/evals/fixtures/stress-arm/planning.yaml")"
  want="verification: standard
plan_stress_test:
  plan: $value
  proposal: $value
  incumbent: $value"
  if [[ "$got" == "$want" ]]; then ok "arm $value sets verification standard and all three modes"; else fail "arm $value sets verification standard and all three modes"; fi
  check_file "arm $value's file passes the schema" 0 "$got"
done

if bash "$ARM/prepare-arm.sh" reviewer "$WORKROOT/copy-reviewer" >/dev/null 2>&1; then
  fail 'prepare-arm refuses a dest that exists'
else
  ok 'prepare-arm refuses a dest that exists'
fi
if bash "$ARM/prepare-arm.sh" never "$WORKROOT/copy-never" >/dev/null 2>&1; then
  fail 'prepare-arm refuses a value outside the list'
else
  ok 'prepare-arm refuses a value outside the list'
fi

# The negative control: same frontmatter, no procedure, and the other skills untouched.
control="$WORKROOT/control"
bash "$ARM/prepare-arm.sh" devils-advocate "$control" --degrade-devils-advocate >/dev/null
source_skill="$PLUGIN_DIR/skills/devils-advocate/SKILL.md"
degraded="$control/skills/devils-advocate/SKILL.md"
frontmatter() { awk 'NR == 1 || !done { print } NR > 1 && /^---$/ { done = 1 }' "$1"; }
if [[ "$(frontmatter "$degraded")" == "$(frontmatter "$source_skill")" ]]; then
  ok 'the degraded skill keeps its frontmatter'
else
  fail 'the degraded skill keeps its frontmatter'
fi
if [[ "$(cat "$degraded")" == "$(frontmatter "$source_skill")"$'\n\n'"$(cat "$ARM/devils-advocate-degraded-body.md.txt")" ]]; then
  ok 'the degraded skill body is devils-advocate-degraded-body.md.txt'
else
  fail 'the degraded skill body is devils-advocate-degraded-body.md.txt'
fi
for heading in '## Analysis Process' '### Round 1' '## Output Format'; do
  if grep -qF "$heading" "$source_skill" && ! grep -qF "$heading" "$degraded"; then
    ok "the degraded skill lost: $heading"
  else
    fail "the degraded skill lost: $heading"
  fi
done
if cmp -s "$PLUGIN_DIR/skills/plan/SKILL.md" "$control/skills/plan/SKILL.md"; then
  ok 'the control leaves the plan skill alone'
else
  fail 'the control leaves the plan skill alone'
fi

# The echo check itself fails on a grader that a quoted workspace file satisfies, and ignores a
# must-not-flag grader.
echo_case="$WORKROOT/echo-case"
echo_ws="$WORKROOT/echo-ws"
mkdir -p "$echo_case/graders" "$echo_ws"
printf 'Retry the upload three times.\n' >"$echo_ws/PLAN.md"
printf -- "---\ntype: regex\npattern: 'upload +three'\nflags: mi\ntarget: last_message\n---\n" >"$echo_case/graders/quoted.md"
if node "$PLUGIN_DIR/tests/lib/st-grader-echo.mjs" "$echo_case" "$echo_ws" >/dev/null 2>&1; then
  fail 'the echo check fails on a quotable grader'
else
  ok 'the echo check fails on a quotable grader'
fi
printf -- "---\ntype: regex\npattern: 'upload +three'\nflags: mi\nmatch: not_contains\ntarget: last_message\n---\n" >"$echo_case/graders/quoted.md"
if node "$PLUGIN_DIR/tests/lib/st-grader-echo.mjs" "$echo_case" "$echo_ws" >/dev/null 2>&1; then
  ok 'the echo check skips a must-not-flag grader'
else
  fail 'the echo check skips a must-not-flag grader'
fi

# Every case: its scaffold builds a committed workspace holding the arm's setting and the draft,
# and no detection grader passes on the workspace's own text, so quoting the draft back scores
# nothing.
cases=0
for case_dir in "$PLUGIN_DIR"/evals/st-*/; do
  name="$(basename "$case_dir")"
  cases=$((cases + 1))
  workspace="$WORKROOT/ws-$name"
  mkdir -p "$workspace"
  if ! env -C "$workspace" bash "$case_dir/scaffold.sh" >/dev/null 2>&1; then
    fail "$name: scaffold exits 0"
    continue
  fi
  if cmp -s "$ARM/planning.yaml" "$workspace/docs/conventions/planning.yaml"; then
    ok "$name: the workspace holds the arm's setting"
  else
    fail "$name: the workspace holds the arm's setting"
  fi
  if [[ -f "$workspace/.work/review-target/PLAN.md" && -f "$workspace/.work/review-target/design/design-resolution.md" ]]; then
    ok "$name: the draft and its design record exist"
  else
    fail "$name: the draft and its design record exist"
  fi
  if [[ -z "$(git -C "$workspace" status --porcelain)" ]]; then
    ok "$name: the workspace is committed clean"
  else
    fail "$name: the workspace is committed clean"
  fi
  if echoed="$(node "$PLUGIN_DIR/tests/lib/st-grader-echo.mjs" "$case_dir" "$workspace" 2>&1)"; then
    ok "$name: no detection grader passes on the workspace's text"
  else
    fail "$name: $echoed"
  fi
done
if [[ "$cases" -eq 12 ]]; then ok 'the suite holds 12 cases'; else fail "the suite holds 12 cases (found $cases)"; fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
