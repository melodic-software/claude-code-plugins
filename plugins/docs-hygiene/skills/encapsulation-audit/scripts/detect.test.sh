#!/usr/bin/env bash
# Regression tests for detect.sh (self-contained — no external test lib).
#
# detect.sh resolves its scan root via `git rev-parse --show-toplevel`, so
# every scan case runs against a deterministic throwaway fixture repo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/detect.sh"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "exit $2" "exit $3"
  fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}
assert_silent() {
  if [[ -z "$2" ]]; then
    pass "$1"
  else
    fail "$1" "empty output" "$2"
  fi
}

FIXTURE_REPOS=()
cleanup_fixtures() {
  local r
  for r in "${FIXTURE_REPOS[@]:-}"; do
    [[ -n "$r" ]] && rm -rf "$r"
  done
}
trap cleanup_fixtures EXIT

# Build a throwaway git repo carrying one file with the given content, and
# echo its path. detect.sh scans the working tree of whatever repo it runs in.
fixture_repo() {
  local file_relpath="$1" line_content="$2"
  local repo
  repo="$(mktemp -d)"
  git init --quiet "$repo"
  (
    cd "$repo" || exit 1
    mkdir -p "$(dirname "$file_relpath")"
    printf '%s\n' "$line_content" >"$file_relpath"
  )
  FIXTURE_REPOS+=("$repo")
  printf '%s' "$repo"
}

skill_root=".claude/skills"

# --help exits 0 with non-empty usage
out="$(bash "$SCRIPT" --help 2>&1)"
code=$?
assert_exit "--help exits 0" 0 "$code"
assert_contains "--help prints usage" "$out" "encapsulation-audit detect"

# Unknown arg → exit 2 with diagnostic
out="$(bash "$SCRIPT" --bogus-arg 2>&1)"
code=$?
assert_exit "unknown arg exits 2" 2 "$code"
assert_contains "unknown arg diagnostic" "$out" "unknown arg"

# Empty repo (no in-scope surfaces at all) → environment error
empty_repo="$(mktemp -d)"
git init --quiet "$empty_repo"
FIXTURE_REPOS+=("$empty_repo")
out="$(cd "$empty_repo" && bash "$SCRIPT" 2>&1)"
code=$?
assert_exit "empty repo → exit 2 (no in-scope surfaces)" 2 "$code"
assert_contains "empty repo diagnostic" "$out" "no in-scope"

# Clean in-scope file → exit 0, silent
clean_repo="$(fixture_repo ".claude/rules/clean.md" "nothing to see here")"
out="$(cd "$clean_repo" && bash "$SCRIPT" 2>/dev/null)"
code=$?
assert_exit "clean repo → exit 0" 0 "$code"
assert_silent "clean repo emits nothing" "$out"

# Private-subdir cite from a rule file → violation, TSV row emitted
viol_repo="$(fixture_repo ".claude/rules/viol.md" \
  "see ${skill_root}/foo/context/notes.md for detail")"
out="$(cd "$viol_repo" && bash "$SCRIPT" 2>/dev/null)"
code=$?
assert_exit "private-subdir cite → exit 1" 1 "$code"
expected_row="$(printf '.claude/rules/viol.md\t1\t%s/foo/context/' "$skill_root")"
assert_contains "violation row is file<TAB>line<TAB>match" "$out" "$expected_row"

# Heading-anchor cite → violation
anchor_repo="$(fixture_repo "docs/guide.md" \
  "see ${skill_root}/foo/SKILL.md#some-heading")"
out="$(cd "$anchor_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "SKILL.md#anchor cite → exit 1" 1 "$?"
assert_contains "anchor cite emitted" "$out" "${skill_root}/foo/SKILL.md#"

# Bare SKILL.md path cite → legal (discouraged but public)
bare_repo="$(fixture_repo "docs/guide.md" \
  "see ${skill_root}/foo/SKILL.md")"
out="$(cd "$bare_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "bare SKILL.md cite → exit 0" 0 "$?"
assert_silent "bare SKILL.md cite emits nothing" "$out"

# *.schema.json at any depth → violation
schema_repo="$(fixture_repo ".claude/rules/schema.md" \
  "validate against ${skill_root}/foo/output.schema.json")"
out="$(cd "$schema_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "schema.json cite → exit 1" 1 "$?"
assert_contains "schema.json cite emitted" "$out" "output.schema.json"

# Plain data file at skill root → legal (data-file carve-out)
data_repo="$(fixture_repo ".claude/rules/data.md" \
  "reads ${skill_root}/foo/catalog.json at runtime")"
out="$(cd "$data_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "root data-file cite → exit 0" 0 "$?"
assert_silent "root data-file cite emits nothing" "$out"

# Root instruction file is in scope
readme_repo="$(fixture_repo "README.md" \
  "internals at ${skill_root}/foo/reference/table.md")"
out="$(cd "$readme_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "README.md violation → exit 1" 1 "$?"
assert_contains "README.md hit emitted" "$out" "README.md"

# .github/ workflows are in scope
gh_repo="$(fixture_repo ".github/workflows/ci.yml" \
  "run: cat ${skill_root}/foo/lib/helper.sh")"
out="$(cd "$gh_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit ".github violation → exit 1" 1 "$?"
assert_contains ".github hit emitted" "$out" "${skill_root}/foo/lib/"

# Mixed line: scripts/ entry cite + other-skill private cite. The genuine cite
# must survive (exit 1, emitted) while the scripts/ cite stays carved out —
# per-cite granularity, not whole-line masking.
mixed_repo="$(fixture_repo ".claude/rules/mixed.md" \
  "see ${skill_root}/alpha/scripts/foo.sh and ${skill_root}/beta/research/bar.md")"
out="$(cd "$mixed_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "mixed line: scripts/ + private → exit 1 (masking fix)" 1 "$?"
assert_contains "mixed line: emits the private cite" "$out" "${skill_root}/beta/research/"
assert_not_contains "mixed line: scripts/ cite stays carved out" "$out" "/scripts/"

# Pure scripts/ line stays carved out (entry-surface carve-out)
pure_repo="$(fixture_repo ".claude/rules/pure-scripts.md" \
  "see ${skill_root}/alpha/scripts/foo.sh")"
out="$(cd "$pure_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "pure scripts/ line → exit 0 (carve-out)" 0 "$?"
assert_silent "pure scripts/ line emits nothing" "$out"

# Self-citation: skills dir is out of scope by default...
self_repo="$(fixture_repo "${skill_root}/foo/SKILL.md" \
  "progressive disclosure: ${skill_root}/foo/context/detail.md")"
# ...a clean in-scope file keeps the default run off the exit-2 path.
mkdir -p "$self_repo/.claude/rules"
printf 'clean\n' >"$self_repo/.claude/rules/clean.md"
out="$(cd "$self_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "self-citation out of scope by default → exit 0" 0 "$?"

# ...surfaces raw with --include-skills...
out="$(cd "$self_repo" && bash "$SCRIPT" --include-skills 2>/dev/null)"
assert_exit "self-citation raw with --include-skills → exit 1" 1 "$?"
assert_contains "self-citation raw hit emitted" "$out" "${skill_root}/foo/context/"

# ...and is filtered legal with --include-skills --apply-filters
err="$(cd "$self_repo" && bash "$SCRIPT" --include-skills --apply-filters 2>&1 >/dev/null)"
code=$?
assert_exit "self-citation filtered legal → exit 0" 0 "$code"
assert_contains "summary counts self-citation as legal" "$err" "raw=1 legal=1 illegal=0"

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
printf '\nAll %d checks passed.\n' "$CASE_NUM"
