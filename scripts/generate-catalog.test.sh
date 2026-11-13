#!/usr/bin/env bash
# Unit tests for generate-catalog.mjs's marker handling. Each scenario builds a
# throwaway tree (the real taxonomy, a one-plugin marketplace, a catalog page)
# and drives the generator through CHECK_DATA_ROOT: either marker form is read,
# regenerating keeps the form found, and a page with both forms or unbalanced
# markers fails without being rewritten.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SELF_DIR/generate-catalog.mjs"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

tree=""

OLD_START='<!-- catalog:start -->'
OLD_END='<!-- catalog:end -->'
GEN_START='<!-- BEGIN GENERATED: catalog. Run node scripts/generate-catalog.mjs -->'
GEN_END='<!-- END GENERATED: catalog -->'
ROW="- [\`alpha\`](../plugins/alpha): Fixture plugin for catalog generator tests."

# mk_tree <out-var> <catalog line...>
mk_tree() {
  local dir
  fixture_tree::build "$1" --no-lib || return 1
  dir="${!1}"
  shift
  mkdir -p "$dir/docs" "$dir/.claude-plugin" "$dir/plugins/alpha/.claude-plugin"
  cp "$REPO_ROOT/docs/catalog-taxonomy.md" "$dir/docs/catalog-taxonomy.md"
  printf '%s\n' '{ "plugins": [ { "name": "alpha", "source": "./plugins/alpha", "category": "discovery" } ] }' \
    >"$dir/.claude-plugin/marketplace.json"
  printf '%s\n' '{ "description": "Fixture plugin for catalog generator tests." }' \
    >"$dir/plugins/alpha/.claude-plugin/plugin.json"
  {
    printf '# Catalog (fixture)\n\n'
    printf '%s\n' "$@"
    printf '\nTrailing prose.\n'
  } >"$dir/docs/catalog.md"
}

run_gen() { # run_gen <tree> [extra args...]: stdout+stderr to $OUT, exit code in $CODE
  local tree="$1"
  shift
  OUT="$(CHECK_DATA_ROOT="$tree" node "$GENERATOR" "$@" 2>&1)"
  CODE=$?
}

# expect_page <label> <tree> <start> <end>: the page is the fixture page with
# the generated block between the given markers.
expect_page() {
  local label="$1" tree="$2" start="$3" end="$4" want
  want="$(printf '# Catalog (fixture)\n\n%s\n\n## Discovery\n\n%s\n\n%s\n\nTrailing prose.' "$start" "$ROW" "$end")"
  if [[ "$(cat "$tree/docs/catalog.md")" == "$want" ]]; then
    ok "$label"
  else
    fail "$label (got: $(cat "$tree/docs/catalog.md"))"
  fi
}

# assert_refused <label> <tree> <expected substring>: generate fails naming the
# defect and leaves the page as it was.
assert_refused() {
  local label="$1" tree="$2" expected="$3" before
  before="$(cat "$tree/docs/catalog.md")"
  run_gen "$tree"
  if [[ "$CODE" -ne 0 && "$OUT" == *"$expected"* && "$(cat "$tree/docs/catalog.md")" == "$before" ]]; then
    ok "$label"
  else
    fail "$label (exit=$CODE, output: $OUT)"
  fi
  rm -rf "$tree"
}

for form in old generated; do
  if [[ "$form" == old ]]; then start="$OLD_START" end="$OLD_END"; else start="$GEN_START" end="$GEN_END"; fi
  mk_tree tree "$start" "$end"
  run_gen "$tree" --check
  if [[ "$CODE" -eq 1 && "$OUT" == *"Catalog drift"* ]]; then
    ok "$form markers: --check on an empty block reports drift"
  else
    fail "$form markers: empty block --check (exit=$CODE: $OUT)"
  fi
  run_gen "$tree"
  if [[ "$CODE" -eq 0 ]]; then ok "$form markers: generate exits 0"; else fail "$form markers: generate (exit=$CODE: $OUT)"; fi
  expect_page "$form markers: regenerating keeps the $form markers" "$tree" "$start" "$end"
  run_gen "$tree" --check
  if [[ "$CODE" -eq 0 && "$OUT" == *"in sync"* ]]; then
    ok "$form markers: --check passes after generate"
  else
    fail "$form markers: --check after generate (exit=$CODE: $OUT)"
  fi
  rm -rf "$tree"
done

mk_tree tree "$OLD_START" "$OLD_END" "$GEN_START" "$GEN_END"
assert_refused "a page with both marker forms fails" "$tree" "carries markers of more than one form"

mk_tree tree "$GEN_START"
assert_refused "a start marker with no end marker fails" "$tree" "has unbalanced markers"

mk_tree tree "$OLD_END" "$OLD_START"
assert_refused "an end marker before its start marker fails" "$tree" "has unbalanced markers"

mk_tree tree "no markers here"
assert_refused "a page with no markers fails, naming the BEGIN GENERATED pair first" "$tree" \
  "is missing the catalog markers ($GEN_START … $GEN_END or $OLD_START … $OLD_END)"

mk_tree tree "$GEN_START" "$GEN_END" "$GEN_START" "$GEN_END"
assert_refused "a repeated marker pair fails" "$tree" "has unbalanced markers"

mk_tree tree '<!-- BEGIN GENERATED: catalog. Run something else -->' "$GEN_END"
assert_refused "a BEGIN GENERATED line with other instruction text fails naming the expected line" "$tree" \
  "differs from the expected line $GEN_START"

mk_tree tree "$OLD_START" "$OLD_END" "$GEN_END"
assert_refused "the more-than-one-form message lists the stray end marker found" "$tree" \
  "more than one form ($GEN_END; $OLD_START, $OLD_END)"

mk_tree tree "$OLD_START" "$OLD_END"
printf '%s\n' '{ "description": "Fixture plugin.\n<!-- END GENERATED: catalog -->" }' \
  >"$tree/plugins/alpha/.claude-plugin/plugin.json"
assert_refused "generated content holding a marker line fails before writing" "$tree" \
  "generated content holding the marker line $GEN_END"

test_harness::report
