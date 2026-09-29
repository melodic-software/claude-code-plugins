#!/usr/bin/env bash
# Renderer tests. Hand-built records use the shape dependency-graph.sh writes;
# the last block renders records that script wrote from fixture repositories.
# Collection itself is covered by dependency-graph.test.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render-components.sh"
COLLECT="$SCRIPT_DIR/../../map-dependencies/scripts/dependency-graph.sh"
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

render() {
  local dir="$TEST_TMPDIR/$1"
  local out="$TEST_TMPDIR/$1.out"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  bash "$SCRIPT" --out "$dir" --dialect c4-plantuml "$@" >"$out"
}

cat >"$TEST_TMPDIR/layers.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"src/host/Host/Host.csproj","name":"Host","path":"src/host/Host/Host.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Host"},
    {"id":"src/application/Application/Application.csproj","name":"Application","path":"src/application/Application/Application.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Application"},
    {"id":"src/domain/Domain/Domain.csproj","name":"Domain","path":"src/domain/Domain/Domain.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Domain"},
    {"id":"pkg:Newtonsoft.Json","name":"Newtonsoft.Json","path":"","ecosystem":"dotnet","kind":"package"}
  ],
  "edges": [
    {"from":"src/host/Host/Host.csproj","to":"src/application/Application/Application.csproj","kind":"project","status":"resolved","evidence":"src/host/Host/Host.csproj: <ProjectReference Include=\"..\\Application\\Application.csproj\" />"},
    {"from":"src/application/Application/Application.csproj","to":"src/domain/Domain/Domain.csproj","kind":"project","status":"resolved","evidence":"src/application/Application/Application.csproj: <ProjectReference Include=\"..\\Domain\\Domain.csproj\" />"},
    {"from":"src/domain/Domain/Domain.csproj","to":"src/application/Application/Application.csproj","kind":"project","status":"resolved","evidence":"src/domain/Domain/Domain.csproj: <ProjectReference Include=\"..\\Application\\Application.csproj\" />"},
    {"from":"src/host/Host/Host.csproj","to":"pkg:Newtonsoft.Json","kind":"package","status":"resolved","evidence":"src/host/Host/Host.csproj: <PackageReference Include=\"Newtonsoft.Json\" />"},
    {"from":"src/host/Host/Host.csproj","to":"..\\Missing.csproj","kind":"project","status":"unresolved","evidence":"src/host/Host/Host.csproj: <ProjectReference Include=\"..\\Missing.csproj\" />"}
  ]
}
JSON

render layered --graph "$TEST_TMPDIR/layers.json" --group-by layer --layers host,application,domain
assert_equals "layer: exits 0 with a violation" "$?" "0"
md="$(cat "$TEST_TMPDIR/layered/components.md")"
assert_contains "layer: C4-PlantUML component library" "$md" '!include <C4/C4_Component>'
assert_contains "layer: host then the others are boundaries" "$md" 'Boundary(grp_0, "host", "layer")'
assert_contains "layer: application boundary" "$md" 'Boundary(grp_1, "application", "layer")'
assert_contains "layer: domain boundary" "$md" 'Boundary(grp_2, "domain", "layer")'
assert_contains "layer: three directed project arrows" "$md" 'Rel('
rels="$(grep -c 'Rel(' "$TEST_TMPDIR/layered/components.md")"
assert_equals "layer: exactly three Rel lines" "$rels" "3"
assert_contains "layer: the upward edge is visibly a violation" "$md" 'ProjectReference, layer violation'
# shellcheck disable=SC2016
assert_contains "layer: the violation tag is defined once" "$md" 'AddRelTag("layer-violation", $textColor="#b00020", $lineColor="#b00020")'
assert_equals "layer: only the violating Rel carries the tag" "$(grep -c 'layer-violation")' "$TEST_TMPDIR/layered/components.md")" "1"
assert_not_contains "layer: no per-relationship UpdateRelStyle" "$md" 'UpdateRelStyle'
assert_contains "layer: the violation table names Domain to Application" "$md" '| Domain | Application |'
assert_contains "layer: informational, and the run does not fail" "$md" 'does not fail'
assert_contains "layer: the package is not a component" "$md" 'External packages collapsed: 1'
diagram="$(awk '/^```plantuml$/,/^```$/' "$TEST_TMPDIR/layered/components.md")"
assert_not_contains "layer: Newtonsoft is not drawn" "$diagram" 'Newtonsoft'
assert_contains "layer: the unresolved reference is listed" "$md" 'Missing.csproj'
assert_contains "layer: summary violations=1" "$(cat "$TEST_TMPDIR/layered.out")" 'violations=1'

render plain --graph "$TEST_TMPDIR/layers.json" --group-by directory
plain="$(cat "$TEST_TMPDIR/plain/components.md")"
assert_not_contains "no layers: no violation mark" "$plain" 'layer violation'
assert_contains "no layers: says no convention was declared" "$plain" 'No layering convention was declared'
assert_contains "directory: the project's parent directory is the boundary" "$plain" 'Boundary(grp_1, "src/domain", "directory")'

render ns --graph "$TEST_TMPDIR/layers.json" --group-by namespace
assert_contains "namespace: groups by the containing namespace" "$(cat "$TEST_TMPDIR/ns/components.md")" \
  'Boundary(grp_0, "Billing", "namespace")'

render lc4 --graph "$TEST_TMPDIR/layers.json" --dialect likec4 --group-by layer --layers host,application,domain
assert_equals "likec4: exits 0" "$?" "0"
lc4="$(cat "$TEST_TMPDIR/lc4/components.md")"
assert_contains "likec4: fence tag" "$lc4" '```likec4'
assert_contains "likec4: a component view of the container" "$lc4" 'view components of c4system.c4container {'
assert_contains "likec4: a layer is a nested boundary" "$lc4" 'grp_0 = boundary "host" {'
assert_contains "likec4: relations use full names" "$lc4" 'c4system.c4container.grp_2.'
assert_contains "likec4: the violation is styled" "$lc4" 'color red'
assert_contains "likec4: the violation is labeled" "$lc4" 'ProjectReference, layer violation'
assert_not_contains "likec4: no plantuml block" "$lc4" '@startuml'
assert_contains "likec4: summary names the dialect" "$(cat "$TEST_TMPDIR/lc4.out")" 'dialect=likec4'
assert_likec4_golden "components.c4" "$TEST_TMPDIR/lc4/components.md"
if [[ -f "$TEST_TMPDIR/lc4/components.dsl" ]]; then
  fail "likec4: no dsl file" "components.dsl exists"
else
  pass "likec4: no dsl file"
fi

rm -rf "$TEST_TMPDIR/none"
mkdir -p "$TEST_TMPDIR/none"
none_out="$(bash "$SCRIPT" --out "$TEST_TMPDIR/none" --graph "$TEST_TMPDIR/layers.json")"
assert_equals "none: exits 0" "$?" "0"
assert_contains "none: summary names the dialect" "$none_out" 'dialect=none'
assert_contains "none: the prose says no view was emitted" "$(cat "$TEST_TMPDIR/none/components.md")" 'unset (no C4 view emitted)'
assert_contains "none: the edge table is still written" "$(cat "$TEST_TMPDIR/none/components.md")" '| Domain | Application |'
assert_equals "none: no diagram fence" "$(grep -c '^```' "$TEST_TMPDIR/none/components.md")" "0"
for refused in mermaid structurizr; do
  bash "$SCRIPT" --out "$TEST_TMPDIR/none" --graph "$TEST_TMPDIR/layers.json" --dialect "$refused" >/dev/null 2>&1
  assert_equals "$refused is a usage error" "$?" "2"
done

# shellcheck disable=SC2016 # backticks are literal fixture text
sed 's/"name":"Domain"/"name":"evil\\")\\n@enduml```x"/; s/"generated_on": "2026-09-28"/"generated_on": "2026\r## Injected`x`"/' "$TEST_TMPDIR/layers.json" >"$TEST_TMPDIR/hostile.json"
render hostile --graph "$TEST_TMPDIR/hostile.json" --group-by directory
assert_equals "hostile: one @enduml line" "$(grep -c '^@enduml$' "$TEST_TMPDIR/hostile/components.md")" "1"
assert_equals "hostile: generated_on carries no control byte" "$(grep -c $'\r' "$TEST_TMPDIR/hostile/components.md")" "0"
assert_contains "hostile: generated_on is kept as plain text" "$(cat "$TEST_TMPDIR/hostile/components.md")" "Generated on 2026## Injectedx from"
assert_contains "hostile: the name is drawn, sanitized" "$(cat "$TEST_TMPDIR/hostile/components.md")" "evil')n@enduml'''x"

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
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"src/c/E/E.csproj","name":"E","path":"src/c/E/E.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/a/A/A.csproj","name":"A","path":"src/a/A/A.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/a/B/B.csproj","name":"B","path":"src/a/B/B.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/b/C/C.csproj","name":"C","path":"src/b/C/C.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/b/D/D.csproj","name":"D","path":"src/b/D/D.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/c/E/E.csproj","to":"src/a/A/A.csproj","kind":"project","status":"resolved","evidence":"src/c/E/E.csproj: <ProjectReference Include=\"../a/A.csproj\" />"},
    {"from":"src/c/E/E.csproj","to":"src/a/B/B.csproj","kind":"project","status":"resolved","evidence":"src/c/E/E.csproj: <ProjectReference Include=\"../a/B.csproj\" />"},
    {"from":"src/c/E/E.csproj","to":"src/b/C/C.csproj","kind":"project","status":"resolved","evidence":"src/c/E/E.csproj: <ProjectReference Include=\"../b/C.csproj\" />"},
    {"from":"src/c/E/E.csproj","to":"src/b/D/D.csproj","kind":"project","status":"resolved","evidence":"src/c/E/E.csproj: <ProjectReference Include=\"../b/D.csproj\" />"}
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
render wide-lc4 --graph "$TEST_TMPDIR/wide.json" --node-threshold 4 --dialect likec4
assert_likec4_golden "components-aggregated.c4" "$TEST_TMPDIR/wide-lc4/components.md"

# Single module.
cat >"$TEST_TMPDIR/one.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"Only.csproj","name":"Only","path":"Only.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": []
}
JSON
render one --graph "$TEST_TMPDIR/one.json"
one="$(cat "$TEST_TMPDIR/one/components.md")"
assert_contains "thin: yes" "$(cat "$TEST_TMPDIR/one.out")" 'thin=yes'
assert_not_contains "thin: no diagram" "$one" '@startuml'
assert_contains "thin: map-landscape" "$one" '/architecture:map-landscape'
assert_contains "thin: map-containers" "$one" '/architecture:map-containers'
assert_contains "thin: improve" "$one" '/architecture:improve'
assert_contains "thin: says a one-box diagram is not the answer" "$one" 'one-box diagram is not the answer'

# Two deployables.
cat >"$TEST_TMPDIR/two.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"Api.csproj","name":"Api","path":"Api.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Worker.csproj","name":"Worker","path":"Worker.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Core.csproj","name":"Core","path":"Core.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"Worker.csproj","to":"Core.csproj","kind":"project","status":"resolved","evidence":"Worker.csproj: <ProjectReference Include=\"Core.csproj\" />"}
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
  "result": "ok",
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

# A record from an older release has no result key. It exits 1 instead of
# rendering with its unresolved references silently dropped.
cat >"$TEST_TMPDIR/stale.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "subject": "billing",
  "ecosystem": "dotnet",
  "unknown_reason": "",
  "unshipped": "",
  "node_threshold": 24,
  "nodes": [
    {"id":"A.csproj","name":"A","path":"A.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"A.csproj","to":"..\\Missing.csproj","kind":"unresolved","evidence":"A.csproj: <ProjectReference Include=\"..\\Missing.csproj\" />"}
  ]
}
JSON
rm -f "$TEST_TMPDIR/bad/components.md"
bad="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/stale.json" --out "$TEST_TMPDIR/bad" 2>&1)"
assert_equals "stale: a record with no result key exits 1" "$?" "1"
assert_contains "stale: says to regenerate it" "$bad" 'regenerate it with /architecture:map-dependencies'
if [[ -e "$TEST_TMPDIR/bad/components.md" ]]; then
  fail "stale: writes nothing" "components.md exists"
else
  pass "stale: writes nothing"
fi

# A quote in a name cannot close the diagram string. A pipe cannot break the table.
cat >"$TEST_TMPDIR/odd.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"Say.csproj","name":"Say \"hi\"","path":"Say.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"Other.csproj","name":"Other","path":"Other.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"Say.csproj","to":"Other.csproj","kind":"project","status":"resolved","evidence":"Say.csproj: left|right"}
  ]
}
JSON
render odd --graph "$TEST_TMPDIR/odd.json" --container 'Say "hi"'
odd="$(cat "$TEST_TMPDIR/odd/components.md")"
assert_contains "sanitize: a quote becomes an apostrophe" "$odd" "Say 'hi'"
assert_contains "sanitize: a pipe is escaped in the table" "$odd" 'left\|right'

# Records dependency-graph.sh wrote from fixture repositories.
write_proj() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}
collect() {
  bash "$COLLECT" --generated-on 2026-09-28 --out "$2" "$1"
}

root="$TEST_TMPDIR/repo"
write_proj "$root/src/host/Billing.Api/Billing.Api.csproj" '<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <ProjectReference Include="..\..\application\Billing.Application\Billing.Application.csproj" />
    <ProjectReference Include="..\..\missing\Nope.csproj" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>'
write_proj "$root/src/application/Billing.Application/Billing.Application.csproj" '<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\domain\Billing.Domain\Billing.Domain.csproj" />
  </ItemGroup>
</Project>'
write_proj "$root/src/domain/Billing.Domain/Billing.Domain.csproj" '<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\application\Billing.Application\Billing.Application.csproj" />
  </ItemGroup>
</Project>'
# The same file name as the missing Include's target, elsewhere on disk.
write_proj "$root/other/Nope/Nope.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
worker_ref='    <ProjectReference Include="..\..\worker\Billing.Worker.Core\Billing.Worker.Core.csproj" />' # portability-ok: Windows path fixture; \w is the worker segment, not a GNU grep class
write_proj "$root/src/host/Billing.Worker/Billing.Worker.csproj" '<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
'"$worker_ref"'
  </ItemGroup>
</Project>'
write_proj "$root/src/worker/Billing.Worker.Core/Billing.Worker.Core.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
collect "$root" "$TEST_TMPDIR/written.json"
assert_equals "written: the collector exits 0" "$?" "0"

render written --graph "$TEST_TMPDIR/written.json" --container Billing.Api \
  --group-by layer --layers host,application,domain
assert_equals "written: exits 0" "$?" "0"
view="$(cat "$TEST_TMPDIR/written/components.md")"
summary="$(cat "$TEST_TMPDIR/written.out")"
assert_contains "written: summary names the container" "$summary" 'container="Billing.Api"'
assert_contains "written: three internal edges" "$summary" 'edges=3'
assert_contains "written: one violation" "$summary" 'violations=1'
assert_contains "written: the package is collapsed" "$summary" 'external_collapsed=1'
assert_contains "written: the missing reference is unresolved" "$summary" 'unresolved=1'
assert_contains "written: host boundary" "$view" 'Boundary(grp_0, "host", "layer")'
assert_contains "written: application boundary" "$view" 'Boundary(grp_1, "application", "layer")'
assert_contains "written: domain boundary" "$view" 'Boundary(grp_2, "domain", "layer")'
assert_contains "written: Domain to Application is the violation" "$view" '| Billing.Domain | Billing.Application |'
assert_contains "written: the violation arrow is labeled" "$view" 'ProjectReference, layer violation'
assert_contains "written: the unresolved reference is listed" "$view" '../../missing/Nope.csproj'
assert_not_contains "written: the missing reference is not matched to other/Nope by name" "$view" 'other/Nope'
assert_not_contains "written: Worker is outside this container" "$view" 'Billing.Worker'
assert_contains "written: outside modules are named as a count" "$view" 'Modules outside this container:'

render written-ns --graph "$TEST_TMPDIR/written.json" --container Billing.Api --group-by namespace
assert_contains "written: a node with no namespace groups by its project name's parent" "$(cat "$TEST_TMPDIR/written-ns/components.md")" \
  'Boundary(grp_0, "Billing", "namespace")'

mkdir -p "$TEST_TMPDIR/written-choice"
choice="$(bash "$SCRIPT" --dialect c4-plantuml --graph "$TEST_TMPDIR/written.json" --out "$TEST_TMPDIR/written-choice" 2>&1)"
assert_equals "written: several deployables exit 3" "$?" "3"
assert_contains "written: the message names the flag" "$choice" 'pass --container'
assert_contains "written: Api is a candidate" "$choice" 'Billing.Api'
assert_contains "written: Worker is a candidate" "$choice" 'Billing.Worker'
if [[ -e "$TEST_TMPDIR/written-choice/components.md" ]]; then
  fail "written: a choice writes nothing" "components.md exists"
else
  pass "written: a choice writes nothing"
fi

# An Include that misses is unresolved even when its text is another project's id.
phantom="$TEST_TMPDIR/phantom-repo"
write_proj "$phantom/a/X.csproj" '<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="b/Y.csproj" />
  </ItemGroup>
</Project>'
write_proj "$phantom/b/Y.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
collect "$phantom" "$TEST_TMPDIR/phantom.json"
assert_contains "phantom: the record marks the edge unresolved and keeps the Include text" "$(cat "$TEST_TMPDIR/phantom.json")" \
  '"to":"b/Y.csproj","kind":"project","status":"unresolved"'
render phantom --graph "$TEST_TMPDIR/phantom.json" --container X
phantom_summary="$(cat "$TEST_TMPDIR/phantom.out")"
assert_contains "phantom: the target is not drawn as a component" "$phantom_summary" 'components=1'
assert_contains "phantom: the edge is unresolved, not drawn" "$phantom_summary" 'unresolved=1'
assert_contains "phantom: X is a single module" "$phantom_summary" 'thin=yes'

# No manifest a shipped reader handles: the writer's message is the reason and
# nothing is drawn.
mkdir -p "$TEST_TMPDIR/node-only"
printf 'source "https://rubygems.org"\n' >"$TEST_TMPDIR/node-only/Gemfile"
collect "$TEST_TMPDIR/node-only" "$TEST_TMPDIR/node-only.json"
render node-only --graph "$TEST_TMPDIR/node-only.json"
assert_equals "unknown: exits 0" "$?" "0"
unk="$(cat "$TEST_TMPDIR/node-only/components.md")"
# The artifact quotes the word unknown in markdown backticks.
# shellcheck disable=SC2016
assert_contains "unknown: says unknown" "$unk" 'ecosystem `unknown`'
assert_contains "unknown: the writer's message names the manifest" "$unk" 'Gemfile'
assert_not_contains "unknown: no diagram" "$unk" '@startuml'
assert_contains "unknown: summary is thin" "$(cat "$TEST_TMPDIR/node-only.out")" 'thin=yes'

# Any ecosystem name other than unknown renders, including mixed; each node
# names its own ecosystem as the component technology.
cat >"$TEST_TMPDIR/mixed.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "mixed",
  "node_threshold": 40,
  "cycles_truncated": false,
  "nodes": [
    {"id":"svc/Api.csproj","name":"Api","path":"svc/Api.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"svc/Core.csproj","name":"Core","path":"svc/Core.csproj","ecosystem":"node","kind":"project"}
  ],
  "edges": [
    {"from":"svc/Api.csproj","to":"svc/Core.csproj","kind":"project","status":"resolved","evidence":"svc/Api.csproj: <ProjectReference Include=\"Core.csproj\" />"}
  ],
  "cycles": [],
  "findings": [
    {"kind":"unread-manifest","path":"App.sln","evidence":"App.sln: Project(\"{F184B08F}\") = \"Db\", \"db\\Db.vbproj\", \"{1}\""}
  ]
}
JSON
render mixed --graph "$TEST_TMPDIR/mixed.json"
assert_equals "mixed: exits 0" "$?" "0"
assert_contains "mixed: charts the components" "$(cat "$TEST_TMPDIR/mixed.out")" 'components=2'
assert_contains "mixed: a dotnet node is labeled dotnet" "$(cat "$TEST_TMPDIR/mixed/components.md")" '"Api", "dotnet", "svc/Api.csproj")'
assert_contains "mixed: a node-ecosystem component is labeled node" "$(cat "$TEST_TMPDIR/mixed/components.md")" '"Core", "node", "svc/Core.csproj")'
# shellcheck disable=SC2016
assert_not_contains "mixed: is not the unknown result" "$(cat "$TEST_TMPDIR/mixed/components.md")" 'ecosystem `unknown`'

# Stray manifests. A project no edge touches, in an ecosystem no linked or .NET
# project shares, is set aside: a tooling package.json or a requirements file
# beside a chartable tree must not turn it into several deployables. Every
# record here comes from the collector, not from a hand-built graph.
dotnet_pair() {
  write_proj "$1/src/Api/Api.csproj" '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="../Core/Core.csproj" /></ItemGroup></Project>'
  write_proj "$1/src/Core/Core.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
}
tooling_json='{ "name": "tooling", "devDependencies": { "prettier": "3.0.0" } }'

stray_a="$TEST_TMPDIR/stray-a-repo"
dotnet_pair "$stray_a"
write_proj "$stray_a/package.json" "$tooling_json"
write_proj "$stray_a/.github/requirements-ci.txt" 'pyyaml'
collect "$stray_a" "$TEST_TMPDIR/stray-a.json"
assert_contains "stray: the collector reads the tooling package.json as a node" "$(cat "$TEST_TMPDIR/stray-a.json")" '"id":"package.json","name":"tooling"'
assert_contains "stray: the collector reads the requirements file as a node" "$(cat "$TEST_TMPDIR/stray-a.json")" '"id":".github/requirements-ci.txt"'
render stray-a --graph "$TEST_TMPDIR/stray-a.json"
assert_equals "stray: a tooling package.json and a requirements file do not stop the render" "$?" "0"
assert_contains "stray: the .NET host is the container" "$(cat "$TEST_TMPDIR/stray-a.out")" 'container="Api" components=2'
assert_contains "stray: the report says two manifests were set aside" "$(cat "$TEST_TMPDIR/stray-a/components.md")" 'Set aside as not deployables: 2.'
assert_not_contains "stray: they are not called modules of another deployable" "$(cat "$TEST_TMPDIR/stray-a/components.md")" 'Modules outside this container'
render stray-a-explicit --graph "$TEST_TMPDIR/stray-a.json" --container tooling
assert_equals "stray: --container still charts a set-aside manifest" "$?" "0"
assert_contains "stray: the chosen manifest is the container" "$(cat "$TEST_TMPDIR/stray-a-explicit.out")" 'container="tooling"'
assert_contains "stray: the chosen manifest is not counted as set aside" "$(cat "$TEST_TMPDIR/stray-a-explicit/components.md")" 'Set aside as not deployables: 1.'

stray_b="$TEST_TMPDIR/stray-b-repo"
write_proj "$stray_b/Api/Api.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
write_proj "$stray_b/package.json" "$tooling_json"
collect "$stray_b" "$TEST_TMPDIR/stray-b.json"
render stray-b --graph "$TEST_TMPDIR/stray-b.json"
assert_equals "stray: a lone .NET project beside a tooling package.json renders" "$?" "0"
assert_contains "stray: the lone .NET project is the container" "$(cat "$TEST_TMPDIR/stray-b.out")" 'container="Api"'

# Two .NET deployables stay a choice, and the stray manifest is not on the list.
stray_c="$TEST_TMPDIR/stray-c-repo"
dotnet_pair "$stray_c"
write_proj "$stray_c/src/Tool/Tool.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
write_proj "$stray_c/package.json" "$tooling_json"
collect "$stray_c" "$TEST_TMPDIR/stray-c.json"
mkdir -p "$TEST_TMPDIR/stray-c"
choice="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/stray-c.json" --out "$TEST_TMPDIR/stray-c" 2>&1)"
assert_equals "stray: two .NET deployables still exit 3" "$?" "3"
assert_contains "stray: the list names Api" "$choice" 'Api'
assert_contains "stray: the list names Tool" "$choice" 'Tool'
assert_not_contains "stray: the list omits the stray manifest" "$choice" 'package.json'

# A tree with no .NET project keeps its one linked ecosystem's deployable.
stray_d="$TEST_TMPDIR/stray-d-repo"
write_proj "$stray_d/go.work" 'go 1.22
use ./app
use ./lib'
write_proj "$stray_d/app/go.mod" 'module example.com/acme/app

replace example.com/acme/lib => ../lib'
write_proj "$stray_d/lib/go.mod" 'module example.com/acme/lib'
write_proj "$stray_d/package.json" "$tooling_json"
collect "$stray_d" "$TEST_TMPDIR/stray-d.json"
render stray-d --graph "$TEST_TMPDIR/stray-d.json"
assert_equals "stray: a Go tree beside a tooling package.json renders" "$?" "0"
assert_contains "stray: the Go module is the container" "$(cat "$TEST_TMPDIR/stray-d.out")" 'container="example.com/acme/app"'

# Alone, a manifest is the deployable.
stray_e="$TEST_TMPDIR/stray-e-repo"
write_proj "$stray_e/package.json" "$tooling_json"
collect "$stray_e" "$TEST_TMPDIR/stray-e.json"
render stray-e --graph "$TEST_TMPDIR/stray-e.json"
assert_equals "stray: a Node-only tree still renders" "$?" "0"
assert_contains "stray: the lone package.json is the container" "$(cat "$TEST_TMPDIR/stray-e.out")" 'container="tooling"'
assert_not_contains "stray: nothing is set aside" "$(cat "$TEST_TMPDIR/stray-e/components.md")" 'Set aside'

# A Node package that references another is a linked deployable beside the .NET host.
stray_f="$TEST_TMPDIR/stray-f-repo"
dotnet_pair "$stray_f"
write_proj "$stray_f/web/app/package.json" '{ "name": "app", "dependencies": { "@acme/ui": "file:../ui" } }'
write_proj "$stray_f/web/ui/package.json" '{ "name": "@acme/ui" }'
collect "$stray_f" "$TEST_TMPDIR/stray-f.json"
mkdir -p "$TEST_TMPDIR/stray-f"
choice="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/stray-f.json" --out "$TEST_TMPDIR/stray-f" 2>&1)"
assert_equals "stray: a linked Node package beside a .NET host exits 3" "$?" "3"
assert_contains "stray: the list names the .NET host" "$choice" 'Api'
assert_contains "stray: the list names the Node package" "$choice" 'web/app/package.json'

# Test projects are not deployables. The layered fixture is the one the
# grouping cases below use: Api <- Application <- Domain, Domain.Events beside
# Domain, and two test projects that reference the host and the library.
layered_proj() {
  local dir="$1" ns="$2" refs="$3"
  write_proj "$layered/src/$dir/$dir.csproj" "<Project Sdk=\"Microsoft.NET.Sdk\">
  <PropertyGroup><$ns</PropertyGroup>
  <ItemGroup>$refs</ItemGroup>
</Project>"
}
layered="$TEST_TMPDIR/layered-repo"
layered_proj Api 'RootNamespace>Billing.Api</RootNamespace>' '<ProjectReference Include="../Application/Application.csproj" />'
layered_proj Application 'RootNamespace>Billing.Application</RootNamespace>' '<ProjectReference Include="../Domain/Domain.csproj" />'
layered_proj Domain 'RootNamespace>Billing.Domain</RootNamespace>' '<ProjectReference Include="../Domain.Events/Domain.Events.csproj" />'
layered_proj Domain.Events 'AssemblyName>Billing.Domain.Events</AssemblyName>' ''
layered_proj Api.Tests 'RootNamespace>Billing.Api.Tests</RootNamespace>' '<PackageReference Include="xunit" Version="2.9.0" /><ProjectReference Include="../Api/Api.csproj" />'
layered_proj Domain.Tests 'IsTestProject>true</IsTestProject>' '<ProjectReference Include="../Domain/Domain.csproj" />'
collect "$layered" "$TEST_TMPDIR/layered-repo.json"
layered_json="$(cat "$TEST_TMPDIR/layered-repo.json")"
assert_contains "tests: the collector marks an xunit project" "$layered_json" '"id":"src/Api.Tests/Api.Tests.csproj","name":"Api.Tests","path":"src/Api.Tests/Api.Tests.csproj","ecosystem":"dotnet","kind":"project","namespace":"Billing.Api.Tests","test":"yes"'
assert_contains "tests: the collector marks IsTestProject" "$layered_json" '"name":"Domain.Tests","path":"src/Domain.Tests/Domain.Tests.csproj","ecosystem":"dotnet","kind":"project","test":"yes"'
assert_not_contains "tests: a production node is not marked" "$(grep '"id":"src/Api/Api.csproj"' "$TEST_TMPDIR/layered-repo.json")" '"test"'

render tests --graph "$TEST_TMPDIR/layered-repo.json"
assert_equals "tests: the host is chosen with two test projects present" "$?" "0"
tests_out="$(cat "$TEST_TMPDIR/tests.out")"
assert_contains "tests: Api is the container" "$tests_out" 'container="Api"'
assert_contains "tests: the closure is the four production projects" "$tests_out" 'components=4'
assert_not_contains "tests: no test project is charted" "$(cat "$TEST_TMPDIR/tests/components.md")" 'Tests'

# Two hosts beside the test projects: the choice list still names the hosts only.
write_proj "$layered/src/Worker/Worker.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
collect "$layered" "$TEST_TMPDIR/layered-two.json"
mkdir -p "$TEST_TMPDIR/tests-choice"
choice="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/layered-two.json" --out "$TEST_TMPDIR/tests-choice" 2>&1)"
assert_equals "tests: two hosts exit 3" "$?" "3"
assert_contains "tests: the list names Api" "$choice" 'Api'
assert_contains "tests: the list names Worker" "$choice" 'Worker'
assert_not_contains "tests: the list names no test project" "$choice" 'Tests'

# Every project a test project: refused with the reason.
only_tests="$TEST_TMPDIR/only-tests-repo"
write_proj "$only_tests/A.Tests/A.Tests.csproj" '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="NUnit" /></ItemGroup></Project>'
write_proj "$only_tests/B.Tests/B.Tests.csproj" '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup></Project>'
collect "$only_tests" "$TEST_TMPDIR/only-tests.json"
mkdir -p "$TEST_TMPDIR/only-tests"
choice="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/only-tests.json" --out "$TEST_TMPDIR/only-tests" 2>&1)"
assert_equals "tests: all-test roots exit 3" "$?" "3"
assert_contains "tests: the refusal names the reason" "$choice" 'every root is a test project'
assert_contains "tests: the list still offers the projects" "$choice" 'A.Tests'
render only-tests-explicit --graph "$TEST_TMPDIR/only-tests.json" --container A.Tests
assert_equals "tests: --container charts a test project on request" "$?" "0"

# A record with no test or namespace field (an older record) still renders.
render old-record --graph "$TEST_TMPDIR/layers.json" --container Host
assert_equals "old record: renders without the optional fields" "$?" "0"

# Grouping, from the record dependency-graph.sh wrote: three strategies, none
# of them one box per project.
grouping() {
  local name="$1" boxes="$2" md
  shift 2
  render "grouping-$name" --graph "$TEST_TMPDIR/layered-repo.json" --container Api "$@"
  md="$TEST_TMPDIR/grouping-$name/components.md"
  assert_equals "grouping $name: four components" "$(grep -c 'Component(' "$md")" "4"
  assert_equals "grouping $name: $boxes boxes" "$(grep -c 'Boundary(grp_' "$md")" "$boxes"
}
grouping directory 1 --group-by directory
grouping namespace 2 --group-by namespace
grouping layer 3 --group-by layer --layers Api,Application,Domain
assert_contains "grouping directory: siblings under src share a box" "$(cat "$TEST_TMPDIR/grouping-directory/components.md")" 'Boundary(grp_0, "src", "directory")'
assert_contains "grouping namespace: Billing holds three projects" "$(cat "$TEST_TMPDIR/grouping-namespace/components.md")" 'Boundary(grp_0, "Billing", "namespace")'
assert_contains "grouping namespace: the AssemblyName fallback nests one deeper" "$(cat "$TEST_TMPDIR/grouping-namespace/components.md")" 'Boundary(grp_1, "Billing.Domain", "namespace")'

# Staleness: a graph older than HEAD warns and still renders.
stale_repo="$TEST_TMPDIR/stale-repo"
write_proj "$stale_repo/A/A.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
git -C "$stale_repo" init --quiet
git -C "$stale_repo" config user.email "fixture@example.invalid"
git -C "$stale_repo" config user.name "Fixture"
git -C "$stale_repo" config commit.gpgsign false
git -C "$stale_repo" add -A
GIT_COMMITTER_DATE="2026-09-29T12:00:00Z" git -C "$stale_repo" commit --quiet --no-verify -m fixture
mkdir -p "$TEST_TMPDIR/stale-out"
stale_err="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/layers.json" --out "$TEST_TMPDIR/stale-out" --root "$stale_repo" 2>&1 >/dev/null)"
assert_equals "stale graph: still exits 0" "$?" "0"
assert_contains "stale graph: warning names both dates on stderr" "$stale_err" 'dependency-graph.json was generated on 2026-09-28; HEAD commit date is 2026-09-29'
assert_contains "stale graph: the artifact carries the warning" "$(cat "$TEST_TMPDIR/stale-out/components.md")" 'dependency-graph.json was generated on 2026-09-28; HEAD commit date is 2026-09-29'
assert_equals "stale graph: exactly one warning line" "$(grep -c 'HEAD commit date' "$TEST_TMPDIR/stale-out/components.md")" "1"
sed 's/"generated_on": "2026-09-28"/"generated_on": "2026-09-29"/' "$TEST_TMPDIR/layers.json" >"$TEST_TMPDIR/fresh.json"
fresh_err="$(bash "$SCRIPT" --graph "$TEST_TMPDIR/fresh.json" --out "$TEST_TMPDIR/stale-out" --root "$stale_repo" 2>&1 >/dev/null)"
assert_equals "fresh graph: no warning" "$fresh_err" ""
assert_not_contains "fresh graph: the artifact has no warning" "$(cat "$TEST_TMPDIR/stale-out/components.md")" 'HEAD commit date'
bash "$SCRIPT" --graph "$TEST_TMPDIR/layers.json" --out "$TEST_TMPDIR/stale-out" --root "$TEST_TMPDIR" >/dev/null 2>&1
assert_not_contains "no checkout: nothing to compare, no warning" "$(cat "$TEST_TMPDIR/stale-out/components.md")" 'HEAD commit date'

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
