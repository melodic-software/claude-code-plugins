#!/usr/bin/env bash
# Tests for render-context.sh that do not depend on a fresh collection.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="$SCRIPT_DIR/render-context.sh"
source "$SCRIPT_DIR/../../../lib/likec4-golden.sh"
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
out="$(bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/ok" --dialect c4-plantuml)"
assert_equals "c4-plantuml: exits 0" "$?" "0"
assert_contains "c4-plantuml: summary" "$out" "context: focal=billing externals=1 actors=1 thin=no dialect=c4-plantuml"
md="$(cat "$TEST_TMPDIR/ok/context.md")"
assert_contains "c4-plantuml: fence tag" "$md" '```plantuml'
assert_contains "c4-plantuml: context include" "$md" "!include <C4/C4_Context>"
assert_contains "c4-plantuml: focal system" "$md" "System(e_billing"
assert_contains "c4-plantuml: person is distinct from the external system" "$md" "Person("
assert_contains "c4-plantuml: external system element" "$md" "System_Ext("
assert_contains "c4-plantuml: closes the diagram" "$md" "@enduml"
assert_not_contains "c4-plantuml: no mermaid C4" "$md" "C4Context"

mkdir -p "$TEST_TMPDIR/likec4"
out="$(bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/likec4" --dialect likec4)"
assert_contains "likec4: summary" "$out" "dialect=likec4"
lmd="$(cat "$TEST_TMPDIR/likec4/context.md")"
assert_contains "likec4: fence tag" "$lmd" '```likec4'
assert_contains "likec4: person element" "$lmd" "= person "
assert_contains "likec4: external element" "$lmd" "= externalSystem \"api.partner.example\""
assert_contains "likec4: relationship" "$lmd" "e_billing -> e_api_partner_example"
assert_contains "likec4: view" "$lmd" "view context {"
assert_likec4_golden "context.c4" "$TEST_TMPDIR/likec4/context.md"

mkdir -p "$TEST_TMPDIR/none"
out="$(bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/none")"
assert_equals "none: exits 0" "$?" "0"
assert_contains "none: summary names the dialect" "$out" "dialect=none"
nmd="$(cat "$TEST_TMPDIR/none/context.md")"
assert_contains "none: the prose says no view was emitted" "$nmd" "unset (no C4 view emitted)"
assert_contains "none: the evidence table is still written" "$nmd" "Partner.BaseUrl"
assert_equals "none: no diagram fence" "$(grep -c '^```' "$TEST_TMPDIR/none/context.md")" "0"

for refused in mermaid structurizr; do
  bash "$RENDER" --record "$TEST_TMPDIR/ok.json" --out "$TEST_TMPDIR/none" --dialect "$refused" >/dev/null 2>&1
  assert_equals "$refused is a usage error" "$?" "2"
done

hostile="$TEST_TMPDIR/hostile.json"
sed 's/"host":"api.partner.example"/"host":"evil\\")\\n@enduml```x|y"/' "$TEST_TMPDIR/ok.json" >"$hostile"
mkdir -p "$TEST_TMPDIR/hostile"
bash "$RENDER" --record "$hostile" --out "$TEST_TMPDIR/hostile" --dialect c4-plantuml >/dev/null
hmd="$(cat "$TEST_TMPDIR/hostile/context.md")"
assert_equals "hostile: exactly one @enduml line" "$(grep -c '^@enduml$' "$TEST_TMPDIR/hostile/context.md")" "1"
assert_equals "hostile: exactly two fence lines" "$(grep -c '^```' "$TEST_TMPDIR/hostile/context.md")" "2"
assert_contains "hostile: the name is drawn, sanitized" "$hmd" "evil') @enduml'''x/y"
assert_not_contains "hostile: no raw double quote from the name" "$hmd" 'evil"'

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
