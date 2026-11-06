#!/usr/bin/env bash
# plan_size_bands and plan_inventory_min_files: the plan skill's size bands and file-inventory
# threshold, read through the convention home.
#
# Expected values come from the key contract in reference/config.md "Convention-home keys": the
# bands default to trivial 1, small 5, medium 15, each an integer with the schema's minimum; the
# inventory threshold defaults to 10, 1 or more.
# test-scope: plugins/planning/schemas/planning.schema.json
# test-scope: plugins/planning/reference/config.md
# test-scope: plugins/planning/skills/plan/SKILL.md
# test-scope: plugins/planning/skills/plan/context/plan-template.md
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$PLUGIN_DIR/skills/setup/scripts/setup-apply.mjs"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT
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

check_file 'all three bands pass' 0 'plan_size_bands:
  trivial: 2
  small: 8
  medium: 25'
check_file 'one band alone passes' 0 'plan_size_bands:
  medium: 30'
check_file 'an unknown band is refused' 1 'plan_size_bands:
  large: 40'
check_file 'a trivial band of 0 is refused' 1 'plan_size_bands:
  trivial: 0'
check_file 'a flat value is refused' 1 'plan_size_bands: 5'
check_file 'an inventory threshold passes' 0 'plan_inventory_min_files: 20'
check_file 'an inventory threshold of 0 is refused' 1 'plan_inventory_min_files: 0'

# Defaults are today's values.
got="$(node -e 'const p = require(process.argv[1]).properties;
const b = p.plan_size_bands.properties;
console.log(Object.keys(b).map((k) => k + "=" + b[k].default).join(" ") + " inventory=" + p.plan_inventory_min_files.default)' \
  "$PLUGIN_DIR/schemas/planning.schema.json" 2>&1)"
if [[ "$got" == 'trivial=1 small=5 medium=15 inventory=10' ]]; then
  ok 'the schema defaults are trivial 1, small 5, medium 15, inventory 10'
else
  fail "the schema defaults are trivial 1, small 5, medium 15, inventory 10 (got: $got)"
fi

section() { awk -v start="$2" -v stop="$3" 'index($0, start) == 1 { on = 1; print; next } on && index($0, stop) == 1 { exit } on' "$1"; }
home_keys="$(section "$PLUGIN_DIR/reference/config.md" '## Convention-home keys' '## ')"
for row in '^\| .plan_size_bands. \|.*\| .trivial: 1., .small: 5., .medium: 15. \|' '^\| .plan_inventory_min_files. \|.*\| .10. \|'; do
  if grep -qE "$row" <<<"$home_keys"; then ok "config.md row: $row"; else fail "config.md row: $row"; fi
done
if grep -qF 'must rise strictly' <<<"$home_keys"; then
  ok 'config.md states the rising-order rule'
else
  fail 'config.md states the rising-order rule'
fi

step2="$(section "$PLUGIN_DIR/skills/plan/SKILL.md" '### Step 2: Formulate the Plan' '### ')"
for needle in 'plan_size_bands' 'plan_inventory_min_files' '"Convention-home keys"' '| Small (2-5 files, clear scope) |' '| Medium (5-15 files, some unknowns) |'; do
  if grep -qF -- "$needle" <<<"$step2"; then ok "plan Step 2 carries: $needle"; else fail "plan Step 2 carries: $needle"; fi
done
if grep -qE '≥ ?10 files|<10 files' "$PLUGIN_DIR/skills/plan/SKILL.md" "$PLUGIN_DIR/skills/plan/context/plan-template.md"; then
  fail 'no hard-coded ≥10 inventory threshold remains'
else
  ok 'no hard-coded ≥10 inventory threshold remains'
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
