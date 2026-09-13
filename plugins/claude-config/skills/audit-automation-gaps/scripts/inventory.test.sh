#!/usr/bin/env bash
# Tests for inventory.sh (self-contained, ships with the plugin).
#
# The behaviour under test is the one the previous revision got wrong: a location
# the script could not read must report WHY, never 0. A silent zero is
# indistinguishable from a real absence, which is what made the old output
# misleading rather than merely incomplete.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/inventory.sh"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}
# Pulls the one hook-location row whose LOCATION column is <label>.
row_for() {
  printf '%s\n' "$2" | awk -v want="$1" '$1 == want { print; exit }'
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rc=0
bash "$INVENTORY" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

help_out="$(bash "$INVENTORY" --help 2>/dev/null)"
assert_contains "--help documents the never-zero contract" "$help_out" "It never reports that location as 0."

# --- Default run over the real repository -------------------------------------

out="$(bash "$INVENTORY" 2>/dev/null)"
rc=0
bash "$INVENTORY" >/dev/null 2>&1 || rc=$?
assert_exit "default run exits 0" 0 "$rc"

# Count table shape: a header row, then one row per documented hook location.
assert_contains "table header present" "$out" "LOCATION"
assert_contains "table header carries PROBED" "$out" "PROBED"
assert_contains "table header carries DECLARING" "$out" "DECLARING"
assert_contains "table header carries HANDLERS" "$out" "HANDLERS"
for loc in user-settings project-settings local-settings managed-policy \
  plugin-hooks-json skill-frontmatter subagent-frontmatter; do
  if [[ -n "$(row_for "$loc" "$out")" ]]; then
    pass "hook location row: $loc"
  else
    fail "hook location row: $loc" "no row whose first column is $loc"
  fi
done

# The output must stay a count table. A row dump of every hook would cost more
# context than the audit it feeds, so the whole report stays small.
line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [[ "$line_count" -lt 60 ]]; then
  pass "default output stays compact ($line_count lines)"
else
  fail "default output stays compact" "expected under 60 lines, got $line_count"
fi

# Conditional versus standing split.
skill_row="$(row_for skill-frontmatter "$out")"
agent_row="$(row_for subagent-frontmatter "$out")"
project_row="$(row_for project-settings "$out")"
assert_contains "skill frontmatter is conditional" "$skill_row" "conditional"
assert_contains "subagent frontmatter is conditional" "$agent_row" "conditional"
assert_contains "project settings are standing" "$project_row" "standing"
assert_not_contains "project settings are not conditional" "$project_row" "conditional"
assert_contains "the conditional rows are explained" "$out" "not part of the standing set"

# Enablement inputs are emitted, a verdict is not.
assert_contains "enablement section present" "$out" "Plugin enablement inputs"
assert_contains "precedence is named, not merge" "$out" "PRECEDENCE, not merge"
assert_contains "hook merge mechanic is named" "$out" "MERGE across settings levels"
assert_contains "enablement verdict is declined" "$out" "No effective enablement is computed here"
assert_contains "cloud-session scope difference is stated" "$out" "cloud session"

# --- An unreadable scope reports unreadable, never 0 ---------------------------

# A path that exists but is not a regular file: deterministic on every uid,
# unlike chmod 000, which root reads anyway.
FIX="$WORK/fixture"
mkdir -p "$FIX/.claude"
mkdir -p "$FIX/user-settings.json"
printf '{"hooks":{}}\n' >"$FIX/.claude/settings.json"
unreadable_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$FIX/user-settings.json" \
  bash "$INVENTORY" 2>/dev/null)"
user_row="$(row_for user-settings "$unreadable_out")"
assert_contains "unreadable user settings report unreadable" "$user_row" "unreadable"
if printf '%s\n' "$user_row" | grep -Eq '(^| )0( |$)'; then
  fail "unreadable scope carries no count" "row printed a 0: $user_row"
else
  pass "unreadable scope carries no count"
fi

# Present but unparsable is invalid-json, which is also not an absence.
printf 'not json at all\n' >"$WORK/broken.json"
broken_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$WORK/broken.json" \
  bash "$INVENTORY" 2>/dev/null)"
assert_contains "unparsable settings report invalid-json" "$(row_for user-settings "$broken_out")" "invalid-json"

# A genuinely missing file is absent, and absent is distinct from unreadable.
absent_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$WORK/nope.json" \
  bash "$INVENTORY" 2>/dev/null)"
absent_row="$(row_for user-settings "$absent_out")"
assert_contains "missing settings report absent" "$absent_row" "absent"
assert_not_contains "absent is not reported as unreadable" "$absent_row" "unreadable"

# Missing jq is a skipped read, not an empty landscape.
nojq_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_JQ="jq-that-does-not-exist" \
  bash "$INVENTORY" 2>/dev/null)"
assert_contains "missing jq reports skipped" "$(row_for project-settings "$nojq_out")" "skipped"

# Managed policy is probed at a sourced per-OS path, or reported not-probed;
# either way it is never silently dropped or reported as a bare 0.
managed_row="$(row_for managed-policy "$out")"
if [[ -n "$managed_row" ]]; then
  case "$managed_row" in
  *present* | *absent* | *unreadable* | *invalid-json* | *skipped* | *not-probed*) pass "managed policy carries a status" ;;
  *) fail "managed policy carries a status" "unrecognised status in: $managed_row" ;;
  esac
else
  fail "managed policy carries a status" "no managed-policy row"
fi

# --- A repository with no plugins at all --------------------------------------

empty_out="$(INVENTORY_PROJECT_DIR="$FIX" bash "$INVENTORY" 2>/dev/null)"
assert_contains "a plugin-free repo still emits the plugin row" "$empty_out" "plugin-hooks-json"
assert_contains "a plugin-free repo still emits components" "$empty_out" "Components in this repository"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
