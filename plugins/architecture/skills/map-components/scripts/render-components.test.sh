#!/usr/bin/env bash
# Renderer tests against a fixed dependency-graph.json. Collection is covered
# by component-graph.test.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render-components.sh"
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

render() {
  local dir="$TEST_TMPDIR/$1"
  local out="$TEST_TMPDIR/$1.out"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  bash "$SCRIPT" --out "$dir" "$@" >"$out"
}

cat >"$TEST_TMPDIR/layers.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "dotnet",
  "node_threshold": 24,
  "nodes": [
    {"id":"src/host/Host/Host.csproj","name":"Host","path":"src/host/Host/Host.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Host"},
    {"id":"src/application/Application/Application.csproj","name":"Application","path":"src/application/Application/Application.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Application"},
    {"id":"src/domain/Domain/Domain.csproj","name":"Domain","path":"src/domain/Domain/Domain.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Domain"},
    {"id":"nuget:Newtonsoft.Json","name":"Newtonsoft.Json","path":"","ecosystem":"nuget","kind":"package"}
  ],
  "edges": [
    {"from":"src/host/Host/Host.csproj","to":"src/application/Application/Application.csproj","kind":"project","evidence":"src/host/Host/Host.csproj: <ProjectReference Include=\"..\\Application\\Application.csproj\" />"},
    {"from":"src/application/Application/Application.csproj","to":"src/domain/Domain/Domain.csproj","kind":"project","evidence":"src/application/Application/Application.csproj: <ProjectReference Include=\"..\\Domain\\Domain.csproj\" />"},
    {"from":"src/domain/Domain/Domain.csproj","to":"src/application/Application/Application.csproj","kind":"project","evidence":"src/domain/Domain/Domain.csproj: <ProjectReference Include=\"..\\Application\\Application.csproj\" />"},
    {"from":"src/host/Host/Host.csproj","to":"nuget:Newtonsoft.Json","kind":"package","evidence":"src/host/Host/Host.csproj: <PackageReference Include=\"Newtonsoft.Json\" />"},
    {"from":"src/host/Host/Host.csproj","to":"..\\Missing.csproj","kind":"unresolved","evidence":"src/host/Host/Host.csproj: <ProjectReference Include=\"..\\Missing.csproj\" />"}
  ]
}
JSON

render layered --graph "$TEST_TMPDIR/layers.json" --group-by layer --layers host,application,domain
assert_equals "layer: exits 0 with a violation" "$?" "0"
md="$(cat "$TEST_TMPDIR/layered/components.md")"
assert_contains "layer: C4Component" "$md" 'C4Component'
assert_contains "layer: host then the others are boundaries" "$md" 'Boundary(grp_0, "host", "layer")'
assert_contains "layer: application boundary" "$md" 'Boundary(grp_1, "application", "layer")'
assert_contains "layer: domain boundary" "$md" 'Boundary(grp_2, "domain", "layer")'
assert_contains "layer: three directed project arrows" "$md" 'Rel('
rels="$(grep -c 'Rel(' "$TEST_TMPDIR/layered/components.md")"
assert_equals "layer: exactly three Rel lines" "$rels" "3"
assert_contains "layer: the upward edge is visibly a violation" "$md" 'ProjectReference, layer violation'
assert_contains "layer: the violation table names Domain to Application" "$md" '| Domain | Application |'
assert_contains "layer: informational, and the run does not fail" "$md" 'does not fail'
assert_contains "layer: the package is not a component" "$md" 'External packages collapsed: 1'
mermaid="$(awk '/^```mermaid$/,/^```$/' "$TEST_TMPDIR/layered/components.md")"
assert_not_contains "layer: Newtonsoft is not drawn" "$mermaid" 'Newtonsoft'
assert_contains "layer: the unresolved reference is listed" "$md" 'Missing.csproj'
assert_contains "layer: summary violations=1" "$(cat "$TEST_TMPDIR/layered.out")" 'violations=1'

render plain --graph "$TEST_TMPDIR/layers.json" --group-by directory
plain="$(cat "$TEST_TMPDIR/plain/components.md")"
assert_not_contains "no layers: no violation mark" "$plain" 'layer violation'
assert_contains "no layers: says no convention was declared" "$plain" 'No layering convention was declared'
assert_contains "directory: a directory boundary" "$plain" 'src/domain/Domain'

render ns --graph "$TEST_TMPDIR/layers.json" --group-by namespace
assert_contains "namespace: uses the namespace field" "$(cat "$TEST_TMPDIR/ns/components.md")" \
  'Boundary(grp_0, "Billing.Application", "namespace")'

render dsl --graph "$TEST_TMPDIR/layers.json" --dialect structurizr --group-by layer --layers host,application,domain
assert_equals "structurizr: exits 0" "$?" "0"
if [[ -f "$TEST_TMPDIR/dsl/components.dsl" && -f "$TEST_TMPDIR/dsl/components.md" ]]; then
  pass "structurizr: writes components.dsl and components.md"
else
  fail "structurizr: writes components.dsl and components.md" "$(ls "$TEST_TMPDIR/dsl")"
fi
dsl="$(cat "$TEST_TMPDIR/dsl/components.dsl")"
assert_contains "structurizr: a component view" "$dsl" 'component c4container "Components"'
assert_contains "structurizr: the violation is tagged" "$dsl" 'tags "LayerViolation"'
assert_contains "structurizr: the tag has a style" "$dsl" 'relationship "LayerViolation"'
assert_not_contains "structurizr: the markdown is not a second mermaid diagram" \
  "$(cat "$TEST_TMPDIR/dsl/components.md")" '```mermaid'

render layered2 --graph "$TEST_TMPDIR/layers.json" --group-by layer --layers host,application,domain
if diff -q "$TEST_TMPDIR/layered/components.md" "$TEST_TMPDIR/layered2/components.md" >/dev/null; then
  pass "determinism: the same graph renders byte-identical markdown"
else
  fail "determinism: the same graph renders byte-identical markdown" \
    "$(diff "$TEST_TMPDIR/layered/components.md" "$TEST_TMPDIR/layered2/components.md")"
fi

# Aggregation. Five components, threshold 4, three directory groups.
cat >"$TEST_TMPDIR/wide.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "dotnet",
  "nodes": [
    {"id":"src/c/E.csproj","name":"E","path":"src/c/E.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/a/A.csproj","name":"A","path":"src/a/A.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/a/B.csproj","name":"B","path":"src/a/B.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/b/C.csproj","name":"C","path":"src/b/C.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/b/D.csproj","name":"D","path":"src/b/D.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/c/E.csproj","to":"src/a/A.csproj","kind":"project","evidence":"src/c/E.csproj: <ProjectReference Include=\"../a/A.csproj\" />"},
    {"from":"src/c/E.csproj","to":"src/a/B.csproj","kind":"project","evidence":"src/c/E.csproj: <ProjectReference Include=\"../a/B.csproj\" />"},
    {"from":"src/c/E.csproj","to":"src/b/C.csproj","kind":"project","evidence":"src/c/E.csproj: <ProjectReference Include=\"../b/C.csproj\" />"},
    {"from":"src/c/E.csproj","to":"src/b/D.csproj","kind":"project","evidence":"src/c/E.csproj: <ProjectReference Include=\"../b/D.csproj\" />"}
  ]
}
JSON
render wide --graph "$TEST_TMPDIR/wide.json" --node-threshold 4
assert_equals "aggregate: exits 0" "$?" "0"
wide="$(cat "$TEST_TMPDIR/wide/components.md")"
assert_contains "aggregate: says so" "$wide" 'Aggregated: yes'
assert_contains "aggregate: names the threshold" "$wide" 'node threshold of 4'
assert_contains "aggregate: nothing was dropped" "$wide" 'No component was dropped'
assert_contains "aggregate: summary aggregated=yes" "$(cat "$TEST_TMPDIR/wide.out")" 'aggregated=yes'
rows="$(grep -c 'Include=' "$TEST_TMPDIR/wide/components.md")"
assert_equals "aggregate: all four declarations stay in the artifact" "$rows" "4"
comps="$(grep -c 'Component(' "$TEST_TMPDIR/wide/components.md")"
assert_equals "aggregate: draws three group nodes, not five" "$comps" "3"

# Single module.
cat >"$TEST_TMPDIR/one.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "dotnet",
  "nodes": [
    {"id":"Only.csproj","name":"Only","path":"Only.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": []
}
JSON
render one --graph "$TEST_TMPDIR/one.json"
one="$(cat "$TEST_TMPDIR/one/components.md")"
assert_contains "thin: yes" "$(cat "$TEST_TMPDIR/one.out")" 'thin=yes'
assert_not_contains "thin: no C4Component" "$one" 'C4Component'
assert_contains "thin: map-landscape" "$one" '/architecture:map-landscape'
assert_contains "thin: map-containers" "$one" '/architecture:map-containers'
assert_contains "thin: improve" "$one" '/architecture:improve'

# Two deployables.
cat >"$TEST_TMPDIR/two.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "dotnet",
  "nodes": [
    {"id":"Api.csproj","name":"Api","path":"Api.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Worker.csproj","name":"Worker","path":"Worker.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Core.csproj","name":"Core","path":"Core.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"Worker.csproj","to":"Core.csproj","kind":"project","evidence":"Worker.csproj: <ProjectReference Include=\"Core.csproj\" />"}
  ]
}
JSON
mkdir -p "$TEST_TMPDIR/two"
choice="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/two.json" --out "$TEST_TMPDIR/two" 2>&1)" || choice_rc=$?
choice_rc="${choice_rc:-0}"
assert_equals "choice: exit 3" "$choice_rc" "3"
assert_contains "choice: lists Api" "$choice" 'Api'
assert_contains "choice: lists Worker" "$choice" 'Worker'
if [[ -e "$TEST_TMPDIR/two/components.md" ]]; then
  fail "choice: writes nothing" "components.md exists"
else
  pass "choice: writes nothing"
fi
render worker --graph "$TEST_TMPDIR/two.json" --container Worker
worker="$(cat "$TEST_TMPDIR/worker/components.md")"
assert_contains "scope: Worker draws Core" "$worker" 'Component('
assert_contains "scope: Core is present" "$worker" '"Core"'
assert_not_contains "scope: Api is not in Worker's closure" "$worker" '"Api"'

# Layout and schema.
mkdir -p "$TEST_TMPDIR/bad"
cat >"$TEST_TMPDIR/pretty.json" <<'JSON'
{
  "schema_version": 1,
  "nodes": [
    {
      "id": "a"
    }
  ],
  "edges": []
}
JSON
bad="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/pretty.json" --out "$TEST_TMPDIR/bad" 2>&1)"
assert_equals "layout: a key-per-line record exits 1" "$?" "1"
assert_contains "layout: names the problem" "$bad" 'one-object-per-line'
if [[ -e "$TEST_TMPDIR/bad/components.md" ]]; then
  fail "layout: writes nothing" "components.md exists"
else
  pass "layout: writes nothing"
fi

printf '{"schema_version": 2, "nodes": [], "edges": []}\n' >"$TEST_TMPDIR/v2.json"
bad="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/v2.json" --out "$TEST_TMPDIR/bad" 2>&1)"
assert_equals "schema: version 2 exits 1" "$?" "1"
assert_contains "schema: names version 1" "$bad" 'schema_version 1'

cat >"$TEST_TMPDIR/unknown.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "unknown",
  "unknown_reason": "found package.json; the shipped adapter reads only .NET ProjectReference and PackageReference, so this ecosystem is unknown",
  "nodes": [],
  "edges": []
}
JSON
render unknown --graph "$TEST_TMPDIR/unknown.json"
assert_equals "unknown: exits 0" "$?" "0"
assert_contains "unknown: the reason is on the artifact" "$(cat "$TEST_TMPDIR/unknown/components.md")" 'package.json'
assert_not_contains "unknown: no diagram" "$(cat "$TEST_TMPDIR/unknown/components.md")" 'C4Component'

# A quote in a name cannot close the diagram string. A pipe cannot break the table.
cat >"$TEST_TMPDIR/odd.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "ecosystem": "dotnet",
  "nodes": [
    {"id":"Say.csproj","name":"Say \"hi\"","path":"Say.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Other.csproj","name":"Other","path":"Other.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"Say.csproj","to":"Other.csproj","kind":"project","evidence":"Say.csproj: left|right"}
  ]
}
JSON
render odd --graph "$TEST_TMPDIR/odd.json" --container 'Say "hi"'
odd="$(cat "$TEST_TMPDIR/odd/components.md")"
assert_contains "sanitize: a quote becomes an apostrophe" "$odd" "Say 'hi'"
assert_contains "sanitize: a pipe is escaped in the table" "$odd" 'left\|right'

printf 'ANNOTATION\n' >"$TEST_TMPDIR/notes.md"
render notes --graph "$TEST_TMPDIR/one.json" --notes "$TEST_TMPDIR/notes.md"
assert_contains "notes: appended" "$(cat "$TEST_TMPDIR/notes/components.md")" 'ANNOTATION'

bad="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/layers.json" --out "$TEST_TMPDIR/bad" --group-by layer 2>&1)"
assert_equals "usage: layer without --layers exits 2" "$?" "2"
assert_contains "usage: says a convention is required" "$bad" 'declared layering'

help_out="$(bash "$SCRIPT" --help 2>&1)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: states the determinism contract" "$help_out" 'byte-identical'

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
