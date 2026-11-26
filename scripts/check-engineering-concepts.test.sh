#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SCRIPT="$SELF_DIR/check-engineering-concepts.sh"
FIXTURES="$SELF_DIR/fixtures/engineering-concepts"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "${WORK:?}"' EXIT

PLUGINS="$WORK/plugins"
mkdir -p "$PLUGINS/fx/skills/real" "$WORK/empty-data"
: >"$PLUGINS/fx/skills/real/SKILL.md"

expect() {
  local name="$1" want="$2" needle="$3" out rc
  shift 3
  out="$(bash "$SCRIPT" "$@" 2>&1)"
  rc=$?
  if [[ "$rc" -ne "$want" ]]; then
    bad "$name" "expected exit $want, got $rc; output: $out"
    return
  fi
  if [[ "$needle" != "-" && "$out" != *"$needle"* ]]; then
    bad "$name" "expected output to contain '$needle'; got: $out"
    return
  fi
  ok "$name"
}

run_data() {
  local name="$1" want="$2" needle="$3" dir="$4"
  expect "$name" "$want" "$needle" --data-dir "$FIXTURES/$dir" --plugins-dir "$PLUGINS"
}

FIELDS='"concern":"c","kind":"practice","stage":"any","reversibility":"unrated","source_url":"https://example.com/s","owner":"fx:real"'
record() { printf '{"id":"%s","name":"%s",%s}' "$1" "$2" "$FIELDS"; }

reject_case() {
  local name="$1" line="$2" want_at="$3" dir="$WORK/reject-$RANDOM"
  mkdir -p "$dir"
  printf '%s\n' "$line" >"$dir/a.jsonl"
  expect "$name" 1 "$want_at" --data-dir "$dir" --plugins-dir "$PLUGINS"
}

run_data "clean records pass" 0 "ok" data-ok
run_data "duplicate id fails and names the id" 1 "fx-dup" data-dup-id
run_data "duplicate alias fails, ignoring case, and names the alias" 1 "shared term" data-dup-alias
run_data "alias equal to another record's id fails" 1 "fx-two" data-alias-is-id
run_data "owner skill that does not exist fails" 1 "fx:gone" data-missing-owner
run_data "owner that is neither a skill nor an https URL fails" 1 "a.jsonl:1: owner is neither" data-bad-owner
run_data "ids that differ only by whitespace fail with the offending line" 1 "a.jsonl:2: id" data-id-padded
run_data "a leading-space id fails with the offending line" 1 "a.jsonl:3: id" data-id-padded
run_data "a name equal to another record's alias fails, ignoring case" 1 "shared name" data-name-vs-alias
run_data "two names equal ignoring case fail" 1 "same name" data-dup-name
run_data "a name equal to another record's id fails, ignoring case" 1 "FX-One" data-name-is-id
run_data "a record's name and id may equal its own aliases" 0 "1 records" data-own-name-alias

mkdir -p "$WORK/crlf-data"
printf '%s\r\n' "$(record fx-a "Fixture A")" '' '   ' "$(record fx-b "Fixture B")" >"$WORK/crlf-data/a.jsonl"
expect "a CRLF file with blank and whitespace-only lines passes" 0 "2 records" --data-dir "$WORK/crlf-data" --plugins-dir "$PLUGINS"
rm -rf "${WORK:?}/crlf-data"

expect "empty data directory passes" 0 "ok" --data-dir "$WORK/empty-data" --plugins-dir "$PLUGINS"
expect "missing data directory passes" 0 "ok" --data-dir "$WORK/no-such-dir" --plugins-dir "$PLUGINS"
expect "the real data directory passes" 0 "ok"

printf '%s\n' '{"id":"fx-broken",' >"$WORK/empty-data/broken.jsonl"
expect "a line that is not JSON fails with its file and line" 1 "broken.jsonl:1" --data-dir "$WORK/empty-data" --plugins-dir "$PLUGINS"
rm -f "$WORK/empty-data/broken.jsonl"

reject_case "an id with a trailing newline fails" '{"id":"p24\n","name":"N",'"$FIELDS"'}' "a.jsonl:1:"
reject_case "a missing concern fails" '{"id":"fx-a","name":"N","kind":"practice","stage":"any","reversibility":"unrated","source_url":"https://example.com/s","owner":"fx:real"}' "a.jsonl:1: concern is missing"
reject_case "an http source_url fails" '{"id":"fx-a","name":"N","concern":"c","kind":"practice","stage":"any","reversibility":"unrated","source_url":"http://example.com/s","owner":"fx:real"}' "a.jsonl:1: source_url"
reject_case "aliases that are a string fail" '{"id":"fx-a","name":"N","aliases":"x",'"$FIELDS"'}' "a.jsonl:1: aliases"
reject_case "aliases holding an empty string fail" '{"id":"fx-a","name":"N","aliases":[""],'"$FIELDS"'}' "a.jsonl:1: aliases"
reject_case "a missing name fails" '{"id":"fx-a",'"$FIELDS"'}' "a.jsonl:1: name is missing"
reject_case "counterweights that are a string fail" '{"id":"fx-a","name":"N","counterweights":"x",'"$FIELDS"'}' "a.jsonl:1: counterweights"
reject_case "a BOM-prefixed line fails" "$(printf '\xef\xbb\xbf')$(record fx-a N)" "a.jsonl:1: not JSON"

mkdir -p "$WORK/no-newline"
printf '%s\n%s\n%s' "$(record fx-a "Name A")" "$(record fx-b "Name B")" '{"id":"fx-c",' >"$WORK/no-newline/a.jsonl"
expect "a bad last line with no trailing newline reports its real line" 1 "a.jsonl:3: not JSON" --data-dir "$WORK/no-newline" --plugins-dir "$PLUGINS"

sed 's/$/\r/' "$FIXTURES/index/valid.md" >"$WORK/crlf-index.md"
expect "a conforming index with CRLF line endings passes" 0 "ok" --data-dir "$WORK/empty-data" --index "$WORK/crlf-index.md"

mkdir -p "$WORK/parity"
cp "$FIXTURES/data-parity/a.jsonl" "$WORK/parity/a.jsonl"
printf '\xef\xbb\xbf%s' "$(record fx-bom "BOM Name")" >>"$WORK/parity/a.jsonl"
check_lines="$(bash "$SCRIPT" --data-dir "$WORK/parity" --plugins-dir "$PLUGINS" 2>&1 | sed -n 's/.*a\.jsonl:\([0-9]*\):.*/\1/p' | sort -n | tr '\n' ' ')"
lookup_lines="$(node "$SELF_DIR/../plugins/engineering-concepts/scripts/lookup.mjs" --data-dir "$WORK/parity" --project "$WORK" --home "$WORK" 2>&1 >/dev/null | sed -n 's/.*"event":"record rejected".*"line":\([0-9]*\),.*/\1/p' | sort -n | tr '\n' ' ')"
want_lines="$(seq 3 24 | tr '\n' ' ')27 28 "
if [[ "$check_lines" == "$want_lines" && "$lookup_lines" == "$want_lines" ]]; then
  ok "the check and the lookup reject exactly the same lines"
else
  bad "the check and the lookup reject exactly the same lines" "want: $want_lines; check: $check_lines; lookup: $lookup_lines"
fi

expect "unknown option exits 2" 2 "usage" --bogus
expect "the usage text says collisions are checked here only" 2 "checked here only" --bogus
expect "an index file that does not exist exits 2" 2 "not found" --index "$WORK/no-such-index.md"

expect "conforming index passes" 0 "ok" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/valid.md"
expect "index without the standards-contract key fails" 1 "standards-contract" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/no-contract-key.md"
expect "index with a non-semver contract version fails" 1 "semver" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/bad-version.md"
expect "index without frontmatter fails" 1 "frontmatter" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/no-frontmatter.md"
expect "index with other table columns fails" 1 "Surface | Applies when | File" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/bad-header.md"
expect "index with an extra frontmatter key fails" 1 "only frontmatter key" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/extra-key.md"
expect "index row with the wrong number of cells fails with its line" 1 "bad-row-cells.md:10: row has 2 cells, want 3" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/bad-row-cells.md"
expect "index with another contract major version fails" 1 "major" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/major-two.md"
expect "index with a header and no rows passes" 0 "ok" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/no-rows.md"

test_harness::report
