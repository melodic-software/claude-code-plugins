#!/usr/bin/env bash
# Regression tests for detect.sh (self-contained — no external test lib).
#
# detect.sh scans the paths it is handed, so every case runs against a
# deterministic throwaway fixture tree under mktemp.
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

FIXTURES=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup_fixtures() {
  local d
  for d in "${FIXTURES[@]:-}"; do
    [[ -n "$d" ]] && rm -rf "$d"
  done
}
trap cleanup_fixtures EXIT

fixture_dir() {
  local d
  d="$(mktemp -d)"
  FIXTURES+=("$d")
  printf '%s' "$d"
}

# --help exits 0 with usage
out="$(bash "$SCRIPT" --help 2>&1)"
code=$?
assert_exit "--help exits 0" 0 "$code"
assert_contains "--help prints usage" "$out" "Usage: detect.sh"

# no args exits 2
out="$(bash "$SCRIPT" 2>&1)"
code=$?
assert_exit "no args exits 2" 2 "$code"

# missing path exits 2
out="$(bash "$SCRIPT" /nonexistent/definitely-missing.md 2>&1)"
code=$?
assert_exit "missing path exits 2" 2 "$code"

# --- tier classification -----------------------------------------------------

d="$(fixture_dir)"
mkdir -p "$d/.claude/rules" "$d/skill/context"
{
  printf '# Facts\n\n- one\n'
} >"$d/CLAUDE.md"
{
  printf '# Unscoped rule\n\nAlways loaded.\n'
} >"$d/.claude/rules/style.md"
{
  printf -- '---\npaths:\n  - "src/**"\n---\n\n# Scoped rule\n'
} >"$d/.claude/rules/scoped.md"
{
  printf -- '---\ndescription: x\n---\n\n## Hub\n\nSee [context/spec.md](context/spec.md) when parsing specs.\n'
} >"$d/skill/SKILL.md"
{
  printf '# Spec\n\nDetail.\n'
} >"$d/skill/context/spec.md"
{
  printf '# Notes\n\nFloating file.\n'
} >"$d/notes.md"
mkdir -p "$d/packages/api"
{
  printf '# API conventions\n\n- local fact\n'
} >"$d/packages/api/CLAUDE.md"

out="$(bash "$SCRIPT" "$d" 2>&1)"
code=$?
assert_exit "tier scan exits 0" 0 "$code"
assert_contains "root CLAUDE.md is always" "$out" "$d/CLAUDE.md	lines=3	words=4	h2=0	tier=always"
assert_contains "nested subtree CLAUDE.md is invocation" "$(printf '%s\n' "$out" | grep 'packages/api/CLAUDE.md')" "tier=invocation"

# Single-file mode must carry the same nesting semantics: the as-typed path
# is the tier-relevant form (bare CLAUDE.md = working-dir file; a nested
# relative path keeps its subtree nesting).
out_sf="$( (cd "$d" && bash "$SCRIPT" CLAUDE.md) 2>&1)"
assert_contains "single-file bare CLAUDE.md is always" "$(printf '%s\n' "$out_sf" | grep '^file')" "tier=always"
out_sf="$( (cd "$d" && bash "$SCRIPT" packages/api/CLAUDE.md) 2>&1)"
assert_contains "single-file nested CLAUDE.md is invocation" "$(printf '%s\n' "$out_sf" | grep '^file')" "tier=invocation"
assert_contains "unscoped rule is always" "$out" "style.md"
assert_contains "unscoped rule tier" "$(printf '%s\n' "$out" | grep 'style.md')" "tier=always"
assert_contains "paths-scoped rule is invocation" "$(printf '%s\n' "$out" | grep 'scoped.md')" "tier=invocation"
assert_contains "SKILL.md is invocation" "$(printf '%s\n' "$out" | grep 'SKILL.md	')" "tier=invocation"
assert_contains "context spoke is on-demand" "$(printf '%s\n' "$out" | grep 'spec.md	')" "tier=on-demand"
assert_contains "unplaceable file is unknown" "$(printf '%s\n' "$out" | grep 'notes.md')" "tier=unknown"

# resolved pointer with when-clause context emitted
assert_contains "pointer emitted with ctx" "$out" "pointer	$d/skill/SKILL.md	7	context/spec.md	resolved=yes"

# --- pointer resolution + URL skipping ---------------------------------------

d2="$(fixture_dir)"
mkdir -p "$d2"
{
  printf '# Hub\n\n[missing](gone.md) and [site](https://example.com/x.md) and [anchor](#local)\n'
} >"$d2/hub.md"
out="$(bash "$SCRIPT" "$d2" 2>&1)"
assert_contains "unresolved pointer flagged" "$out" "gone.md	resolved=no"
assert_not_contains "absolute URL skipped as pointer target" "$out" "	https://example.com/x.md	"
assert_contains "unresolved counted" "$out" "unresolved=1"

# --- orphan + chain detection ------------------------------------------------

d3="$(fixture_dir)"
mkdir -p "$d3/skill/context"
{
  # shellcheck disable=SC2016  # literal backticks belong in the fixture text
  printf -- '---\ndescription: x\n---\n\n## Hub\n\nSee [context/linked.md](context/linked.md) for detail.\n\nAlso see `context/ticked.md` when calibrating.\n'
} >"$d3/skill/SKILL.md"
{
  printf '# Linked\n\nOnward: [deep.md](deep.md)\n'
} >"$d3/skill/context/linked.md"
{
  printf '# Deep\n\nBottom.\n'
} >"$d3/skill/context/deep.md"
{
  printf '# Orphan\n\nUnreferenced.\n'
} >"$d3/skill/context/orphan.md"
{
  printf '# Ticked\n\nReferenced by backtick mention only.\n'
} >"$d3/skill/context/ticked.md"
{
  printf '# Cycle A\n\nSee [cycle-b.md](cycle-b.md).\n'
} >"$d3/skill/context/cycle-a.md"
{
  printf '# Cycle B\n\nSee [cycle-a.md](cycle-a.md).\n'
} >"$d3/skill/context/cycle-b.md"
out="$(bash "$SCRIPT" "$d3" 2>&1)"
assert_contains "orphan spoke detected" "$out" "orphan	$d3/skill/context/orphan.md"
assert_not_contains "linked spoke not orphaned" "$out" "orphan	$d3/skill/context/linked.md"
assert_not_contains "chain-target spoke not orphaned" "$out" "orphan	$d3/skill/context/deep.md"
assert_not_contains "backtick-mentioned spoke not orphaned" "$out" "orphan	$d3/skill/context/ticked.md"
assert_contains "disconnected cycle member A is orphaned" "$out" "orphan	$d3/skill/context/cycle-a.md"
assert_contains "disconnected cycle member B is orphaned" "$out" "orphan	$d3/skill/context/cycle-b.md"
assert_contains "spoke-to-spoke chain detected" "$out" "chain	$d3/skill/context/linked.md	3	deep.md"
assert_contains "summary counts orphans and chains" "$out" "orphans=3	chains=3"

# --- TOC heuristic -----------------------------------------------------------

d4="$(fixture_dir)"
{
  printf '# Ref\n\n- [a](#a)\n- [b](#b)\n- [c](#c)\n\n## a\n\n## b\n\n## c\n'
} >"$d4/ref.md"
{
  printf '# Ref2\n\n- [a](#a)\n\n## a\n'
} >"$d4/ref2.md"
{
  printf '# Deep anchors\n'
  for i in $(seq 1 45); do printf 'filler line %s\n' "$i"; done
  printf -- '- [a](#a)\n- [b](#b)\n- [c](#c)\n'
} >"$d4/ref3.md"
{
  printf '# Compact\n\nJump: [a](#a) [b](#b) [c](#c)\n\n## a\n\n## b\n\n## c\n'
} >"$d4/ref4.md"
out="$(bash "$SCRIPT" "$d4" 2>&1)"
assert_contains "3+ anchor links near top = toc yes" "$(printf '%s\n' "$out" | grep 'ref.md	')" "toc=yes"
assert_contains "under 3 anchors = toc no" "$(printf '%s\n' "$out" | grep 'ref2.md	')" "toc=no"
assert_contains "anchors deep in the body = toc no" "$(printf '%s\n' "$out" | grep 'ref3.md	')" "toc=no"
assert_contains "one-line compact TOC = toc yes" "$(printf '%s\n' "$out" | grep 'ref4.md	')" "toc=yes"

# --- de-duplication when a file arrives twice --------------------------------

out="$(bash "$SCRIPT" "$d4" "$d4/ref.md" 2>&1)"
n="$(printf '%s\n' "$out" | grep -c "file	$d4/ref.md	")"
if [[ "$n" == "1" ]]; then
  pass "duplicate target deduplicated"
else
  fail "duplicate target deduplicated" "1 file record" "$n file records"
fi

# --- corpus exclusions are scan-root-relative --------------------------------

d5="$(fixture_dir)"
mkdir -p "$d5/evals/fixtures/sample-skill/context"
{
  printf -- '---\ndescription: x\n---\n\n## Hub\n\n[bare](context/x.md)\n'
} >"$d5/evals/fixtures/sample-skill/SKILL.md"
{
  printf '# X\n\nSpoke.\n'
} >"$d5/evals/fixtures/sample-skill/context/x.md"
{
  printf '# Top\n\nOutside fixtures.\n'
} >"$d5/top.md"

out="$(bash "$SCRIPT" "$d5" 2>&1)"
assert_contains "corpus sweep sees non-fixture file" "$out" "file	$d5/top.md"
assert_not_contains "corpus sweep excludes evals/fixtures" "$out" "sample-skill"

out="$(bash "$SCRIPT" "$d5/evals/fixtures/sample-skill" 2>&1)"
assert_contains "explicit fixture-dir descent scans it" "$out" "file	$d5/evals/fixtures/sample-skill/SKILL.md"
assert_contains "explicit fixture-dir descent runs hub analysis" "$out" "pointer	$d5/evals/fixtures/sample-skill/SKILL.md"

# --- summary -----------------------------------------------------------------

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit "$((FAILED > 0 ? 1 : 0))"
