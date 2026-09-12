#!/usr/bin/env bash
# Self-contained tests for sweep.sh, driven against the committed fixture tree
# in fixtures/tree via fixtures/build-fixture.sh.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sweep.sh"
INVENTORY="$SCRIPT_DIR/inventory.sh"
BUILD="$SCRIPT_DIR/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

assert_lacks() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" >/dev/null
  printf '%s' "$d"
}

pairs_for() {
  bash "$INVENTORY" --root "$1" | awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}'
}

# A `file:form:tier:action` view of the sweep, one line per site.
view() {
  awk -F'\t' '$1=="REF" {print $3 ":" $5 ":" $6 ":" $7}'
}

root="$(new_fixture)"
pairs_for "$root" >"$TEST_TMPDIR/pairs.tsv"
out="$(bash "$SUT" --root "$root" --pairs "$TEST_TMPDIR/pairs.tsv")"
sites="$(printf '%s\n' "$out" | view)"

# --- the form ladder ---------------------------------------------------------

assert_contains "a markdown link is classified as one" "$sites" "README.md:md-link:current:edit"
assert_contains "a code span is classified as a backtick path" "$sites" "README.md:backtick-path:current:edit"
assert_contains "a raw URL is classified ahead of the other URL forms" "$sites" "README.md:raw-url:current:edit"
assert_contains "a forge URL is classified" "$sites" "README.md:github-url:current:edit"
assert_contains "a table cell is classified" "$sites" "README.md:table-or-key:current:edit"

# --- tiers decide the action -------------------------------------------------

assert_contains "a historical link is still repointed" "$sites" "docs/adr/0001-historical.md:md-link:historical:edit"
assert_contains "a historical backtick path is still repointed" "$sites" "docs/adr/0001-historical.md:backtick-path:historical:edit"
assert_contains "historical narrative is reported, never rewritten" "$sites" "docs/adr/0001-historical.md:bare-stem:historical:report"
assert_contains "a released link is reported, never rewritten" "$sites" "CHANGELOG.md:md-link:released:report"
assert_contains "a released backtick path is reported too" "$sites" "CHANGELOG.md:backtick-path:released:report"
assert_eq "no released site is ever an edit" "0" "$(printf '%s\n' "$sites" | grep -c '^CHANGELOG.md:.*:released:edit' || true)"

# --- bare stems --------------------------------------------------------------

assert_contains "a hyphenated stem is unambiguous and edited" "$sites" "README.md:bare-stem:current:edit"
assert_contains "a one-word stem is ambiguous and reviewed" "$sites" "README.md:bare-stem:current:review"
assert_eq "the ambiguous stem is reviewed rather than edited at every current site" "0" "$(
  printf '%s\n' "$out" | awk -F'\t' '$1=="REF" && $2=="docs/BETA.md" && $5=="bare-stem" && $6=="current" && $7=="edit"' | grep -c . || true
)"

# --- generated records are never text-edited ---------------------------------

assert_contains "a generated record is marked for regeneration" "$sites" "build/out.json:plain:current:regenerate"
assert_eq "no generated site is ever an edit" "0" "$(printf '%s\n' "$sites" | grep -c '^build/out.json:.*:edit' || true)"

# --- sweep exclusions --------------------------------------------------------

assert_lacks "an excluded path is never read or reported" "$sites" "docs/topics/t/PLAN.md"

# --- the substring hazard ----------------------------------------------------
#
# `Alpha` must never match inside `Alpha-One`: an anchored stem is what keeps a
# rename from turning a hyphenated sibling into a link to nothing.
root2="$(new_fixture)"
printf 'docs/Alpha.md\tdocs/alpha.md\n' >"$TEST_TMPDIR/hazard.tsv"
haz_raw="$(bash "$SUT" --root "$root2" --pairs "$TEST_TMPDIR/hazard.tsv")"
haz="$(printf '%s\n' "$haz_raw" | view)"
# `Alpha` still matches the WORD Alpha in "Alpha One" prose, which is exactly
# why a one-word stem is only ever reviewed. What must never happen is an edit,
# because rewriting it would turn `Alpha-One` into a link to nothing.
assert_eq "a shorter stem is never edited on the strength of a text match" "0" "$(printf '%s\n' "$haz" | grep -c ':bare-stem:.*:edit' || true)"
assert_contains "a shorter stem is surfaced for review instead" "$haz" ":bare-stem:current:review"
# The decisive case: a tree where the stem appears ONLY inside a hyphenated
# compound. A word-boundary match would report it; the anchored pattern reports
# nothing at all.
root4="$(new_fixture)"
printf 'The compound Zeta-Two appears here, and the bare word never does.\n' >"$root4/docs/note.md"
git -C "$root4" add docs/note.md >/dev/null
git -C "$root4" commit -qm "compound only" >/dev/null
printf 'docs/Zeta.md\tdocs/zeta.md\n' >"$TEST_TMPDIR/compound.tsv"
compound="$(bash "$SUT" --root "$root4" --pairs "$TEST_TMPDIR/compound.tsv")"
assert_eq "a stem that appears only inside a hyphenated compound matches nothing" "0" "$(
  printf '%s\n' "$compound" | grep -c '^REF' || true
)"

# --- per-site exclusions -----------------------------------------------------

root3="$(new_fixture)"
jq '.file_names.sweep_exclude_sites = ["README.md:forge URL"]' \
  "$root3/.claude/docs-hygiene.json" >"$root3/.claude/t.json"
mv "$root3/.claude/t.json" "$root3/.claude/docs-hygiene.json"
excl="$(bash "$SUT" --root "$root3" --pairs "$TEST_TMPDIR/pairs.tsv" | view)"
assert_contains "a per-site exclusion is reported as skipped" "$excl" "README.md:github-url:current:skip"
assert_contains "its neighbours on other lines are unaffected" "$excl" "README.md:md-link:current:edit"

# --- tier reporting and totals -----------------------------------------------

assert_contains "each declared tier reports how many files it claimed" "$out" "TIER	historical	links-and-paths	1"
assert_contains "the released tier is reported too" "$out" "TIER	released	none	1"
assert_contains "the site total is reported" "$out" "SITES	"

# --- read-only ---------------------------------------------------------------

assert_eq "the tree is byte-identical after a sweep" "" "$(git -C "$root" status --porcelain)"

# --- stdin and usage ---------------------------------------------------------

stdin_out="$(bash "$SUT" --root "$root" --pairs - <"$TEST_TMPDIR/pairs.tsv" | view)"
assert_contains "pairs can arrive on standard input" "$stdin_out" "README.md:md-link:current:edit"

assert_eq "--help exits 0" "0" "$(
  bash "$SUT" --help >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a missing --pairs exits 2" "2" "$(
  bash "$SUT" --root "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "an unreadable pairs file exits 2" "2" "$(
  bash "$SUT" --root "$root" --pairs "$TEST_TMPDIR/absent.tsv" >/dev/null 2>&1
  printf '%s' "$?"
)"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
