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

run_data "clean records pass" 0 "ok" data-ok
run_data "duplicate id fails and names the id" 1 "fx-dup" data-dup-id
run_data "duplicate alias fails, ignoring case, and names the alias" 1 "shared term" data-dup-alias
run_data "alias equal to another record's id fails" 1 "fx-two" data-alias-is-id
run_data "owner skill that does not exist fails" 1 "fx:gone" data-missing-owner
run_data "owner that is neither a skill nor an https URL fails" 1 "http://example.com/not-https" data-bad-owner

expect "empty data directory passes" 0 "ok" --data-dir "$WORK/empty-data" --plugins-dir "$PLUGINS"
expect "missing data directory passes" 0 "ok" --data-dir "$WORK/no-such-dir" --plugins-dir "$PLUGINS"
expect "the real data directory passes" 0 "ok"

printf '%s\n' '{"id":"fx-broken",' >"$WORK/empty-data/broken.jsonl"
expect "a line that is not JSON fails with its file and line" 1 "broken.jsonl:1" --data-dir "$WORK/empty-data" --plugins-dir "$PLUGINS"
rm -f "$WORK/empty-data/broken.jsonl"

expect "unknown option exits 2" 2 "usage" --bogus
expect "an index file that does not exist exits 2" 2 "not found" --index "$WORK/no-such-index.md"

expect "conforming index passes" 0 "ok" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/valid.md"
expect "index without the standards-contract key fails" 1 "standards-contract" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/no-contract-key.md"
expect "index with a non-semver contract version fails" 1 "semver" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/bad-version.md"
expect "index without frontmatter fails" 1 "frontmatter" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/no-frontmatter.md"
expect "index with other table columns fails" 1 "Surface | Applies when | File" --data-dir "$WORK/empty-data" --index "$FIXTURES/index/bad-header.md"

test_harness::report
