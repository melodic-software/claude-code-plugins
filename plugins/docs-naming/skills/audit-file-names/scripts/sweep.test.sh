#!/usr/bin/env bash
# test-scope: plugins/docs-naming/skills/audit-file-names/scripts/fixtures/tree/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_OPTION_FILE_NAMES
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sweep.sh"
INVENTORY="$SCRIPT_DIR/inventory.sh"
BUILD="$SCRIPT_DIR/fixtures/build-fixture.sh"
EDIT_CONFIG="$SCRIPT_DIR/fixtures/edit-config.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" >/dev/null
  printf '%s' "$d"
}

pairs_for() {
  bash "$INVENTORY" --root "$1" | awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}'
}

view() {
  awk -F'\t' '$1=="REF" {print $3 ":" $5 ":" $6 ":" $7}'
}

root="$(new_fixture)"
pairs_for "$root" >"$TEST_TMPDIR/pairs.tsv"
out="$(bash "$SUT" --root "$root" --pairs "$TEST_TMPDIR/pairs.tsv")"
sites="$(printf '%s\n' "$out" | view)"

assert_contains "a markdown link is classified as one" "$sites" "README.md:md-link:current:edit"
assert_contains "a code span is classified as a backtick path" "$sites" "README.md:backtick-path:current:edit"
assert_contains "a raw URL is classified ahead of the other URL forms" "$sites" "README.md:raw-url:current:edit"
assert_contains "a forge URL is classified" "$sites" "README.md:github-url:current:edit"
assert_contains "a table cell is classified" "$sites" "README.md:table-or-key:current:edit"

assert_contains "a historical link is still repointed" "$sites" "docs/adr/0001-historical.md:md-link:historical:edit"
assert_contains "a historical backtick path is still repointed" "$sites" "docs/adr/0001-historical.md:backtick-path:historical:edit"
assert_contains "historical narrative is reported, never rewritten" "$sites" "docs/adr/0001-historical.md:bare-stem:historical:report"
assert_contains "a released link is reported, never rewritten" "$sites" "CHANGELOG.md:md-link:released:report"
assert_contains "a released backtick path is reported too" "$sites" "CHANGELOG.md:backtick-path:released:report"
assert_eq "no released site is ever an edit" "0" "$(printf '%s\n' "$sites" | grep -c '^CHANGELOG.md:.*:released:edit' || true)"

assert_contains "a hyphenated stem is unambiguous and edited" "$sites" "README.md:bare-stem:current:edit"
assert_contains "a one-word stem is ambiguous and reviewed" "$sites" "README.md:bare-stem:current:review"
assert_eq "the ambiguous stem is reviewed rather than edited at every current site" "0" "$(
  printf '%s\n' "$out" | awk -F'\t' '$1=="REF" && $2=="docs/BETA.md" && $5=="bare-stem" && $6=="current" && $7=="edit"' | grep -c . || true
)"

assert_contains "a generated record is marked for regeneration" "$sites" "build/out.json:plain:current:regenerate"
assert_eq "no generated site is ever an edit" "0" "$(printf '%s\n' "$sites" | grep -c '^build/out.json:.*:edit' || true)"

assert_lacks "an excluded path is never read or reported" "$sites" "docs/frozen/t/NOTES.md"

root2="$(new_fixture)"
printf 'docs/Alpha.md\tdocs/alpha.md\n' >"$TEST_TMPDIR/hazard.tsv"
haz_raw="$(bash "$SUT" --root "$root2" --pairs "$TEST_TMPDIR/hazard.tsv")"
haz="$(printf '%s\n' "$haz_raw" | view)"
assert_eq "a shorter stem is never edited on the strength of a text match" "0" "$(printf '%s\n' "$haz" | grep -c ':bare-stem:.*:edit' || true)"
assert_contains "a shorter stem is surfaced for review instead" "$haz" ":bare-stem:current:review"
root4="$(new_fixture)"
printf 'The compound Zeta-Two appears here, and the bare word never does.\n' >"$root4/docs/note.md"
git -C "$root4" add docs/note.md >/dev/null
git -C "$root4" commit -qm "compound only" >/dev/null
printf 'docs/Zeta.md\tdocs/zeta.md\n' >"$TEST_TMPDIR/compound.tsv"
compound="$(bash "$SUT" --root "$root4" --pairs "$TEST_TMPDIR/compound.tsv")"
assert_eq "a stem that appears only inside a hyphenated compound matches nothing" "0" "$(
  printf '%s\n' "$compound" | grep -c '^REF' || true
)"

root7="$(new_fixture)"
printf 'A near miss that is not the file: v1x2yschema appears here.\n' \
  >"$root7/docs/near-miss.md"
git -C "$root7" add docs/near-miss.md >/dev/null
git -C "$root7" commit -qm "near miss" >/dev/null
printf 'docs/v1.2.schema.md\tdocs/v1-2-schema.md\n' >"$TEST_TMPDIR/meta.tsv"
meta="$(bash "$SUT" --root "$root7" --pairs "$TEST_TMPDIR/meta.tsv")"

assert_eq "a dot in a stem does not match an arbitrary character" "0" \
  "$(printf '%s\n' "$meta" | grep -c 'near-miss.md' || true)"

root8="$(new_fixture)"
printf 'The real one: v1.2.schema is cited here.\n' >"$root8/docs/real-hit.md"
git -C "$root8" add docs/real-hit.md >/dev/null
git -C "$root8" commit -qm "real hit" >/dev/null
hit="$(bash "$SUT" --root "$root8" --pairs "$TEST_TMPDIR/meta.tsv")"

assert_contains "the literal stem is still matched" "$hit" "docs/real-hit.md"

root5="$(new_fixture)"
# shellcheck disable=SC2016  # backticks are literal markdown in the seeded line
printf 'A label link: [`Alpha-One`](Alpha-One.md) and a plain one: [see](Alpha-One.md).\n' \
  >"$root5/docs/labels.md"
git -C "$root5" add docs/labels.md >/dev/null
git -C "$root5" commit -qm labels >/dev/null
labels_raw="$(bash "$SUT" --root "$root5" --pairs "$TEST_TMPDIR/pairs.tsv")"
labels="$(printf '%s\n' "$labels_raw" | awk -F'\t' '$1=="REF" && $3=="docs/labels.md" {print $5}')"

assert_contains "the link target is recorded" "$labels" "md-link"
assert_contains "and the label beside it is recorded as a bare stem" "$labels" "bare-stem"
assert_eq "exactly two sites on the one line" "2" "$(printf '%s\n' "$labels" | grep -c . || true)"

root6="$(new_fixture)"
printf 'Only the path, no label: [see](Alpha-One.md) and nothing else.\n' \
  >"$root6/docs/plain.md"
git -C "$root6" add docs/plain.md >/dev/null
git -C "$root6" commit -qm plain >/dev/null
plain_raw="$(bash "$SUT" --root "$root6" --pairs "$TEST_TMPDIR/pairs.tsv")"
plain="$(printf '%s\n' "$plain_raw" | awk -F'\t' '$1=="REF" && $3=="docs/plain.md" {print $5}')"

assert_eq "a line whose only stem occurrence is the basename is one site" "1" \
  "$(printf '%s\n' "$plain" | grep -c . || true)"
assert_eq "and that site is not a bare stem" "0" "$(printf '%s\n' "$plain" | grep -c 'bare-stem' || true)"

root9="$(new_fixture)"
mkdir -p "$root9/docs/adr/deep" "$root9/notes"
printf '# Deep\n\nCites [Alpha One](../../Alpha-One.md) and the narrative stem Alpha-One.\n' \
  >"$root9/docs/adr/deep/0003-deep.md"
printf 'Notes cite Alpha-One.md here.\n' >"$root9/notes/n.md"
git -C "$root9" add -A >/dev/null
git -C "$root9" commit -qm "a deep historical file and an unclaimed one" >/dev/null
home9="$TEST_TMPDIR/home9-$RANDOM"
mkdir -p "$home9/.claude"
jq9="$TEST_TMPDIR/jq-bin"
mkdir -p "$jq9"
ln -sf "$(mise which jq 2>/dev/null || command -v jq)" "$jq9/jq"

jq -n '{schema: 1, file_names: {tiers: [
  {name: "personal-loose", paths: ["docs/adr/deep/**"], forms: "all"}]}}' \
  >"$home9/.claude/docs-naming.json"
floor="$(HOME="$home9" PATH="$jq9:$PATH" bash "$SUT" --root "$root9" --pairs "$TEST_TMPDIR/pairs.tsv" | view)"

assert_contains "the team's historical tier still owns the deeper file" "$floor" \
  "docs/adr/deep/0003-deep.md:md-link:historical:edit"
assert_eq "and a personal tier cannot loosen its frozen forms" "0" \
  "$(printf '%s\n' "$floor" | grep -c '^docs/adr/deep/0003-deep.md:.*:personal-loose:' || true)"
assert_eq "the narrative stem there is still reported, never edited" "0" \
  "$(printf '%s\n' "$floor" | grep -c '^docs/adr/deep/0003-deep.md:bare-stem:.*:edit' || true)"

jq -n '{schema: 1, file_names: {tiers: [
  {name: "personal-frozen", paths: ["notes/**"], forms: "none"}]}}' \
  >"$home9/.claude/docs-naming.json"
adds="$(HOME="$home9" PATH="$jq9:$PATH" bash "$SUT" --root "$root9" --pairs "$TEST_TMPDIR/pairs.tsv" | view)"

assert_contains "a personal tier still claims a file no team tier covers" "$adds" \
  "notes/n.md:plain:personal-frozen:report"

rm "$home9/.claude/docs-naming.json"
opt="$(HOME="$home9" PATH="$jq9:$PATH" bash "$SUT" --root "$root9" --pairs "$TEST_TMPDIR/pairs.tsv" \
  --user-config '{"tiers": [{"name": "option-frozen", "paths": ["notes/**"], "forms": "none"}]}' | view)"
assert_contains "a --user-config tier reaches the resolver and claims an unclaimed file" "$opt" \
  "notes/n.md:plain:option-frozen:report"
opt="$(HOME="$home9" PATH="$jq9:$PATH" bash "$SUT" --root "$root9" --pairs "$TEST_TMPDIR/pairs.tsv" \
  --user-config '{"tiers": [{"name": "option-loose", "paths": ["docs/adr/deep/**"], "forms": "all"}]}' | view)"
assert_eq "a --user-config tier cannot loosen a team tier" "0" \
  "$(printf '%s\n' "$opt" | grep -c '^docs/adr/deep/0003-deep.md:.*:option-loose:' || true)"

root3="$(new_fixture)"
bash "$EDIT_CONFIG" "$root3" '.file_names.sweep_exclude_sites = ["README.md:forge URL"]'
excl="$(bash "$SUT" --root "$root3" --pairs "$TEST_TMPDIR/pairs.tsv" | view)"
assert_contains "a per-site exclusion is reported as skipped" "$excl" "README.md:github-url:current:skip"
assert_contains "its neighbors on other lines are unaffected" "$excl" "README.md:md-link:current:edit"

assert_contains "each declared tier reports how many files it claimed" "$out" "TIER	historical	links-and-paths	1"
assert_contains "the released tier is reported too" "$out" "TIER	released	none	1"
assert_contains "the site total is reported" "$out" "SITES	"

assert_eq "the tree is byte-identical after a sweep" "" "$(git -C "$root" status --porcelain)"

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
