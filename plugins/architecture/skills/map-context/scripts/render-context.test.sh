#!/usr/bin/env bash
# Tests for render-context.sh that do not depend on a fresh collection.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$SCRIPT_DIR/render-context.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

cat >"$TEST_TMPDIR/ok.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "subject": "billing",
  "focal": {"name":"billing","origin":"derived"},
  "actors": [
    {"name":"Clerk","description":"Files a claim","origin":"operator"}
  ],
  "externals": [
    {"host":"api.partner.example","kind":"http","port":"","origin":"derived","file":"src/appsettings.json","key":"Partner.BaseUrl"}
  ]
}
JSON

mkdir -p "$TEST_TMPDIR/ok"
out="$(bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/ok" --dialect mermaid)"
assert_equals "mermaid: exits 0" "$?" "0"
assert_contains "mermaid: summary" "$out" "context: focal=billing externals=1 actors=1 thin=no"
md="$(cat "$TEST_TMPDIR/ok/context.md")"
assert_contains "mermaid: focal system" "$md" "System("
assert_contains "mermaid: person is distinct from the external system" "$md" "Person("
assert_contains "mermaid: external system element" "$md" "System_Ext("
assert_contains "mermaid: C4Context has a title" "$md" "C4Context"

mkdir -p "$TEST_TMPDIR/dsl"
bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/dsl" --dialect structurizr >"$TEST_TMPDIR/dsl.out"
dsl="$(cat "$TEST_TMPDIR/dsl/context.dsl")"
assert_contains "structurizr: systemContext view" "$dsl" "systemContext "
assert_contains "structurizr: person element" "$dsl" "= person "
assert_contains "structurizr: external tag" "$dsl" "External"
assert_contains "structurizr: person shape" "$dsl" "shape Person"

for shape in compact pretty; do
  if [[ "$shape" == "compact" ]]; then
    printf '%s\n' '{"schema_version": 1, "generated_on": "2026-09-28", "subject": "billing", "focal": {"name":"billing","origin":"derived"}, "actors": [], "externals": [{"host":"api.partner.example","kind":"http","port":"","origin":"derived","file":"a.json","key":"Url"}]}' >"$TEST_TMPDIR/$shape.json"
  else
    printf '{\n  "schema_version": 1,\n  "focal": {\n    "name": "billing"\n  },\n  "actors": [\n    {\n      "name": "Clerk"\n    }\n  ],\n  "externals": []\n}\n' >"$TEST_TMPDIR/$shape.json"
  fi
  rm -rf "$TEST_TMPDIR/layout-$shape"
  mkdir -p "$TEST_TMPDIR/layout-$shape"
  bad="$(bash "$RENDER" --record "$TEST_TMPDIR/$shape.json" --out "$TEST_TMPDIR/layout-$shape" 2>&1)"
  assert_equals "layout: a $shape record exits 1" "$?" "1"
  assert_contains "layout: and names the layout problem ($shape)" "$bad" "one-object-per-line layout"
  assert_not_contains "layout: with no summary line ($shape)" "$bad" "context:"
  assert_equals "layout: and writes no artifact ($shape)" "$(ls -A "$TEST_TMPDIR/layout-$shape")" ""
done

printf '{"schema_version": 2, "focal": {"name":"x","origin":"derived"}, "actors": [], "externals": []}\n' >"$TEST_TMPDIR/v2.json"
mkdir -p "$TEST_TMPDIR/layout-v2"
bad="$(bash "$RENDER" --record "$TEST_TMPDIR/v2.json" --out "$TEST_TMPDIR/layout-v2" 2>&1)"
assert_equals "schema: version 2 exits 1" "$?" "1"
assert_contains "schema: and says which version it wanted" "$bad" "schema_version 1"
assert_equals "schema: and writes nothing" "$(ls -A "$TEST_TMPDIR/layout-v2")" ""

help_out="$(bash "$RENDER" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: describes the summary line" "$help_out" "context:"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
