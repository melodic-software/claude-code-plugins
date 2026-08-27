#!/usr/bin/env bash
# Regression tests for precompute.sh.
#
# The point of the suite is the count agreement. precompute.sh feeds a skill's
# `## Pre-computed context` header, so a count that disagrees with the engines
# is not a cosmetic defect: it sets the model's expectation of the repository
# before any work starts. These cases pin the counts to the same discovery
# functions the engines call, on the two layouts a root-only
# `find .claude/rules` misses entirely.
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/precompute.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi
}

# A repository whose rules live in three places the root-only `find` cannot see
# as one set: the root tree, a nested package tree, and a symlinked shared set.
build_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude/rules" "$dir/packages/api/.claude/rules" \
    "$dir/shared-rules" "$dir/libs/.claude"
  : >"$dir/.claude/rules/root.md"
  : >"$dir/packages/api/.claude/rules/api.md"
  : >"$dir/shared-rules/team.md"
  ln -s ../../shared-rules "$dir/libs/.claude/rules"
  : >"$dir/CLAUDE.md"
  printf '%s' "$dir"
}

run_in() {
  local dir="$1"
  shift
  (cd "$dir" && bash "$SCRIPT" "$@" 2>/dev/null)
}

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1
assert_eq "a missing mode is a usage error" "2" "$?"

bash "$SCRIPT" nope >/dev/null 2>&1
assert_eq "an unknown mode is a usage error" "2" "$?"

usage="$(bash "$SCRIPT" nope 2>&1)"
assert_contains "the usage line names every mode" "$usage" "audit|check|realign"

# --------------------------------------------------------------------------
# The counts agree with the discovery layer
#
# This is the regression. Before the consolidation these lines ran a bare
# `find .claude/rules`, which reports 1 on the fixture below while the check
# gate walks 3 -- the header understating the repository by two thirds.
# --------------------------------------------------------------------------
repo="$(build_fixture)"

# shellcheck source=lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"
expected_rules="$(cd "$repo" && ip_discover_rules . | wc -l | tr -d ' ')"
assert_eq "the fixture really does hide rules from a root-only find" "3" "$expected_rules"
open_coded="$(cd "$repo" && find .claude/rules -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "and the open-coded pattern really does miss them" "1" "$open_coded"

audit_out="$(run_in "$repo" audit)"
assert_contains "audit counts rules through the discovery layer" \
  "$audit_out" "- Rules files: $expected_rules"

check_out="$(run_in "$repo" check)"
assert_contains "check counts rules through the same layer" \
  "$check_out" "- Rules files: $expected_rules"

assert_eq "the two modes report the same count" \
  "$(printf '%s' "$audit_out" | grep 'Rules files:')" \
  "$(printf '%s' "$check_out" | grep 'Rules files:')"

# --------------------------------------------------------------------------
# Presence probes
# --------------------------------------------------------------------------
assert_contains "check reports a present CLAUDE.md" "$check_out" '- Root CLAUDE.md: present'
assert_contains "check reports an absent AGENTS.md" "$check_out" '- Root AGENTS.md: absent'

: >"$repo/AGENTS.md"
assert_contains "an empty AGENTS.md is present, not absent" \
  "$(run_in "$repo" check)" '- Root AGENTS.md: present'
assert_contains "and its line count is 0 rather than absent" \
  "$(run_in "$repo" audit)" "- Root AGENTS.md lines: 0"

# --------------------------------------------------------------------------
# Nested instruction counts follow the corpus rules, not a bare walk
#
# ip_discover_nested_instructions is tracked-only inside a repository and
# excludes vendored trees. A bare `find` counts both, which would tell the
# operator there is on-demand instruction content where none actually loads.
# --------------------------------------------------------------------------
mkdir -p "$repo/node_modules/pkg" "$repo/vendor/upstream" "$repo/docs"
: >"$repo/node_modules/pkg/CLAUDE.md"
: >"$repo/vendor/upstream/AGENTS.md"
: >"$repo/docs/CLAUDE.md"

assert_contains "vendored and node_modules instruction files are not counted" \
  "$(run_in "$repo" audit)" "- Nested instruction files: 1"

# Inside a repository the count is tracked-only, so an uncommitted file drops.
git -C "$repo" init -q .
git -C "$repo" -c user.email=t@t -c user.name=t add CLAUDE.md AGENTS.md >/dev/null 2>&1
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
assert_contains "an untracked nested file is not counted inside a repository" \
  "$(run_in "$repo" audit)" "- Nested instruction files: 0"

# --------------------------------------------------------------------------
# Degradation
#
# This output lands in a skill header, so every mode must exit 0 and print a
# usable value even where the probes have nothing to read.
# --------------------------------------------------------------------------
empty="$(mktemp -d)"
for mode in audit check realign; do
  out="$(run_in "$empty" "$mode")"
  rc=$?
  assert_eq "$mode exits 0 in an empty directory" "0" "$rc"
  if [[ -n "$out" ]]; then
    pass "$mode still prints orientation in an empty directory"
  else
    fail "$mode still prints orientation in an empty directory" "non-empty output" "(empty)"
  fi
done
assert_contains "an absent CLAUDE.md reads as absent, not 0" \
  "$(run_in "$empty" audit)" "- Root CLAUDE.md lines: absent"
assert_contains "an empty directory reports zero rules" \
  "$(run_in "$empty" check)" "- Rules files: 0"

# --------------------------------------------------------------------------
# The probe must never modify the repository it describes
# --------------------------------------------------------------------------
before="$(git -C "$repo" status --porcelain)"
run_in "$repo" audit >/dev/null
run_in "$repo" check >/dev/null
run_in "$repo" realign >/dev/null
assert_eq "the probes leave the working tree untouched" \
  "$before" "$(git -C "$repo" status --porcelain)"

rm -rf "$repo" "$empty"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
