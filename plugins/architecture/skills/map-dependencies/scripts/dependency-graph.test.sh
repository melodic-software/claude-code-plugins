#!/usr/bin/env bash
# Self-contained tests for dependency-graph.sh and render-dependencies.sh
# (skill-script shape, per docs/conventions/shell-test-helpers/README.md:
# per-plugin assertion primitives are duplicated on purpose, never shared
# across plugins).
#
# Every fixture is built in a mktemp directory and torn down on exit; nothing
# here reads or writes a real repository.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPH="$SCRIPT_DIR/dependency-graph.sh"
RENDER="$SCRIPT_DIR/render-dependencies.sh"
LIB="$SCRIPT_DIR/../../../lib/dotnet-references.sh"
PORTFOLIO="$SCRIPT_DIR/../../map-landscape/scripts/portfolio-facts.sh"
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

# shellcheck source=../../../lib/dotnet-references.sh
source "$LIB"

# The historical portfolio span, kept here as the oracle the shared reader
# must not drift from.
oracle_includes() {
  grep -oE '<(Package|Project)Reference[^>]*Include="[^"]*"' "$1" 2>/dev/null |
    sed 's/.*Include="//; s/"$//'
}

parity_file="$TEST_TMPDIR/parity.csproj"
cat >"$parity_file" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Serilog" Version="4.0.0" />
    <ProjectReference Condition="'$(Configuration)'=='Debug'" Include="..\Lib\Lib.csproj" />
    <PackageReference Update="Skipped" Version="1.0.0" />
    <PackageReference Include='SingleQuoted' />
    <ProjectReference
        Include="multiline.csproj" />
    <PackageReference Include="MediatR" Version="12.0.0" /><ProjectReference Include="Helper.csproj" />
  </ItemGroup>
</Project>
CSPROJ
oracle="$(oracle_includes "$parity_file")"
shared="$(dotnet_reference_includes "$parity_file")"
assert_equals "shared reader matches the historical Include span" "$shared" "$oracle"
assert_contains "shared reader keeps Serilog" "$shared" "Serilog"
assert_contains "shared reader keeps the relative ProjectReference" "$shared" '..\Lib\Lib.csproj'
assert_not_contains "shared reader ignores Update=" "$shared" "Skipped"
assert_not_contains "shared reader ignores single quotes" "$shared" "SingleQuoted"
assert_not_contains "shared reader ignores an Include on the next line" "$shared" "multiline.csproj"
assert_contains "shared reader keeps two tags on one line" "$shared" "Helper.csproj"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

make_tree() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

basic="$(make_tree basic)"
mkdir -p "$basic/src/App" "$basic/src/Lib" "$basic/src/Outside" "$basic/src/Sibling" "$basic/src/Fs" "$TEST_TMPDIR/Outside"
cat >"$basic/src/App/App.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\Lib\Lib.csproj" />
    <ProjectReference Include="..\Missing\Missing.csproj" />
    <ProjectReference Include="..\..\..\Outside\Outside.csproj" />
    <ProjectReference Include="Helper.csproj" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    <PackageReference Include="MediatR">
      <Version>12.0.0</Version>
    </PackageReference>
  </ItemGroup>
</Project>
CSPROJ
cat >"$basic/src/App/Helper.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
</Project>
CSPROJ
cat >"$basic/src/Lib/Lib.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
</Project>
CSPROJ
cat >"$basic/src/Outside/Outside.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
</Project>
CSPROJ
cat >"$basic/src/Sibling/Sibling.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
</Project>
CSPROJ
cat >"$basic/src/Fs/App.fsproj" <<'FSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\Lib\Lib.csproj" />
  </ItemGroup>
</Project>
FSPROJ
cat >"$basic/src/App/Program.cs" <<'CS'
using Lib;
class Program { static void Main() {} }
CS
printf '%s\n' '{ "dependencies": { "left-pad": "1.0.0" } }' >"$basic/package.json"
sibling_sln_path='..\Sibling\Sibling.csproj' # portability-ok: Windows path fixture; \S is the Sibling segment, not a GNU grep class
cat >"$basic/App.sln" <<SLN
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "App", "src\App\App.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "Sibling", "$sibling_sln_path", "{22222222-2222-2222-2222-222222222222}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{33333333-3333-3333-3333-333333333333}"
EndProject
SLN
mkdir -p "$basic/nest"
lib_slnx_path='..\src\Lib\Lib.csproj' # portability-ok: Windows path fixture; \s is the src segment, not a GNU grep class
cat >"$basic/nest/App.slnx" <<SLNX
<Solution>
  <Project Path="$lib_slnx_path" />
  <Project Path="..\..\nope\Nope.csproj" />
</Solution>
SLNX
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk"></Project>' >"$TEST_TMPDIR/Outside/Outside.csproj"

basic_json="$(bash "$GRAPH" "$basic")"
assert_equals "basic: collector exits 0" "$?" "0"
assert_contains "basic: schema_version 1" "$basic_json" '"schema_version": 1'
assert_contains "basic: result ok" "$basic_json" '"result": "ok"'
assert_contains "basic: ecosystem dotnet" "$basic_json" '"ecosystem": "dotnet"'
assert_contains "basic: node threshold is 40" "$basic_json" '"node_threshold": 40'
assert_contains "basic: resolved project edge cites the declaration" "$basic_json" '"from":"src/App/App.csproj","to":"src/Lib/Lib.csproj","kind":"project","status":"resolved"'
assert_contains "basic: evidence names the file and the tag" "$basic_json" 'src/App/App.csproj: <ProjectReference Include=\"..\\Lib\\Lib.csproj\" />'
assert_contains "basic: same-directory ProjectReference resolves" "$basic_json" '"to":"src/App/Helper.csproj"'
assert_contains "basic: fsproj ProjectReference resolves" "$basic_json" '"from":"src/Fs/App.fsproj","to":"src/Lib/Lib.csproj"'
assert_contains "basic: package edge" "$basic_json" '"to":"pkg:Newtonsoft.Json","kind":"package","status":"resolved"'
assert_contains "basic: package evidence keeps the version" "$basic_json" 'PackageReference Include=\"Newtonsoft.Json\" Version=\"13.0.3\"'
assert_contains "basic: element-form PackageReference" "$basic_json" '"to":"pkg:MediatR"'
assert_contains "basic: missing target is unresolved" "$basic_json" '"status":"unresolved"'
assert_contains "basic: missing target keeps the declared path" "$basic_json" '"to":"..\\Missing\\Missing.csproj"'
assert_contains "basic: outside target keeps the declared path" "$basic_json" '"to":"..\\..\\..\\Outside\\Outside.csproj"'
assert_not_contains "basic: outside reference is not the decoy project" "$basic_json" '"to":"src/Outside/Outside.csproj"'
assert_contains "basic: decoy project is still a node because the file exists" "$basic_json" '"id":"src/Outside/Outside.csproj"'
assert_contains "basic: solution membership outside the root is a finding" "$basic_json" '"kind":"unresolved-membership"'
assert_contains "basic: solution finding keeps the declared path" "$basic_json" '..\\Sibling\\Sibling.csproj' # portability-ok: Windows path fixture; \S is the Sibling segment, not a GNU grep class
assert_not_contains "basic: solution path is not resolved onto the decoy sibling" "$basic_json" '"to":"src/Sibling/Sibling.csproj"'
assert_not_contains "basic: a using in Program.cs is not an edge" "$basic_json" 'Program.cs'
assert_contains "basic: unread node manifest is named, not drawn as empty" "$basic_json" 'Not read: node (package.json)'
assert_contains "basic: node_threshold documented in the record" "$basic_json" '"node_threshold": 40'

# One object per line: a node line parses as one JSON object.
node_line="$(printf '%s\n' "$basic_json" | grep '"kind":"project"' | head -1)"
assert_contains "basic: a project node is one line" "$node_line" '"ecosystem":"dotnet"'

out_basic="$TEST_TMPDIR/out-basic"
mkdir -p "$out_basic"
printf '%s\n' "$basic_json" >"$out_basic/dependency-graph.json"
summary="$(bash "$RENDER" --record "$out_basic/dependency-graph.json" --out "$out_basic")"
assert_equals "basic: renderer exits 0" "$?" "0"
assert_contains "basic: summary names the counts" "$summary" "result=ok"
assert_contains "basic: summary is not aggregated" "$summary" "aggregated=no"
md="$(cat "$out_basic/dependency-graph.md")"
assert_contains "basic: cycles section is present" "$md" "## Cycles"
assert_contains "basic: no cycle in this fixture" "$md" "None."
cycles_at="$(printf '%s\n' "$md" | grep -n '^## Cycles' | head -1 | cut -d: -f1)"
diagram_at="$(printf '%s\n' "$md" | grep -n '^## Diagram' | head -1 | cut -d: -f1)"
if [[ -n "$cycles_at" && -n "$diagram_at" && "$cycles_at" -lt "$diagram_at" ]]; then
  pass "basic: cycles section is above the diagram"
else
  fail "basic: cycles section is above the diagram" "cycles=$cycles_at diagram=$diagram_at"
fi
mermaid="$(printf '%s\n' "$md" | awk '/^```mermaid$/,/^```$/')"
assert_contains "basic: mermaid flowchart" "$mermaid" "flowchart LR"
assert_contains "basic: internal edge is drawn" "$mermaid" "src/Lib/Lib.csproj"
assert_not_contains "basic: external package is collapsed" "$mermaid" "Newtonsoft.Json"
assert_not_contains "basic: diagram is not a C4 type" "$mermaid" "C4Component"
assert_contains "basic: collapsed count is stated" "$md" "External packages collapsed:"
assert_not_contains "basic: below the threshold, no directory aggregation" "$md" "Aggregated to directory level"

mkdir -p "$TEST_TMPDIR/out-ext"
summary_ext="$(bash "$RENDER" --record "$out_basic/dependency-graph.json" --out "$TEST_TMPDIR/out-ext" --include-external)"
assert_equals "include-external: exits 0" "$?" "0"
assert_contains "include-external: summary stays ok" "$summary_ext" "result=ok"
md_ext="$(cat "$TEST_TMPDIR/out-ext/dependency-graph.md")"
mermaid_ext="$(printf '%s\n' "$md_ext" | awk '/^```mermaid$/,/^```$/')"
assert_contains "include-external: package name is drawn" "$mermaid_ext" "Newtonsoft.Json"
assert_contains "include-external: internal edge remains" "$mermaid_ext" "src/Lib/Lib.csproj"

mkdir -p "$TEST_TMPDIR/out-ext-only"
bash "$RENDER" --record "$out_basic/dependency-graph.json" --out "$TEST_TMPDIR/out-ext-only" --external-only >/dev/null
assert_equals "external-only: exits 0" "$?" "0"
md_only="$(cat "$TEST_TMPDIR/out-ext-only/dependency-graph.md")"
mermaid_only="$(printf '%s\n' "$md_only" | awk '/^```mermaid$/,/^```$/')"
assert_contains "external-only: package name is drawn" "$mermaid_only" "Newtonsoft.Json"
assert_not_contains "external-only: internal project target is not drawn" "$mermaid_only" "src/Lib/Lib.csproj"

both="$(bash "$RENDER" --record "$out_basic/dependency-graph.json" --out "$TEST_TMPDIR/out-ext" --include-external --external-only 2>&1)"
assert_equals "both external flags is usage" "$?" "2"
assert_contains "both external flags names the conflict" "$both" "mutually exclusive"

cycle="$(make_tree cycle)"
mkdir -p "$cycle/a" "$cycle/b" "$cycle/c"
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="..\b\B.csproj" /></ItemGroup></Project>' >"$cycle/a/A.csproj" # portability-ok: Windows path fixture; \b is the b segment, not a GNU grep word boundary
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="..\c\C.csproj" /></ItemGroup></Project>' >"$cycle/b/B.csproj"
printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="..\a\A.csproj" /></ItemGroup></Project>' >"$cycle/c/C.csproj"
cycle_json="$(bash "$GRAPH" "$cycle")"
assert_equals "cycle: collector exits 0" "$?" "0"
assert_contains "cycle: the directed cycle is in the record" "$cycle_json" '"id":"a/A.csproj -> b/B.csproj -> c/C.csproj -> a/A.csproj"'
cycle_hits="$(printf '%s\n' "$cycle_json" | grep -c 'a/A.csproj -> b/B.csproj -> c/C.csproj -> a/A.csproj')"
assert_equals "cycle: reported once" "$cycle_hits" "1"
mkdir -p "$TEST_TMPDIR/out-cycle"
printf '%s\n' "$cycle_json" >"$TEST_TMPDIR/out-cycle/dependency-graph.json"
bash "$RENDER" --record "$TEST_TMPDIR/out-cycle/dependency-graph.json" --out "$TEST_TMPDIR/out-cycle" >/dev/null
cycle_md="$(cat "$TEST_TMPDIR/out-cycle/dependency-graph.md")"
assert_contains "cycle: markdown leads with the cycle" "$cycle_md" "a/A.csproj -> b/B.csproj -> c/C.csproj -> a/A.csproj"
c_at="$(printf '%s\n' "$cycle_md" | grep -n 'a/A.csproj -> b/B.csproj' | head -1 | cut -d: -f1)"
d_at="$(printf '%s\n' "$cycle_md" | grep -n '^## Diagram' | head -1 | cut -d: -f1)"
if [[ -n "$c_at" && -n "$d_at" && "$c_at" -lt "$d_at" ]]; then
  pass "cycle: the cycle line is above the diagram"
else
  fail "cycle: the cycle line is above the diagram" "cycle=$c_at diagram=$d_at"
fi
mkdir -p "$TEST_TMPDIR/out-cycle-only"
bash "$RENDER" --record "$TEST_TMPDIR/out-cycle/dependency-graph.json" --out "$TEST_TMPDIR/out-cycle-only" --cycles-only >/dev/null
cycle_only_md="$(cat "$TEST_TMPDIR/out-cycle-only/dependency-graph.md")"
assert_contains "cycles-only: still names the cycle" "$cycle_only_md" "a/A.csproj -> b/B.csproj -> c/C.csproj -> a/A.csproj"
assert_contains "cycles-only: flowchart remains" "$cycle_only_md" "flowchart LR"

mkdir -p "$TEST_TMPDIR/out-basic-cycles"
bash "$RENDER" --record "$out_basic/dependency-graph.json" --out "$TEST_TMPDIR/out-basic-cycles" --cycles-only >/dev/null
assert_contains "cycles-only on an acyclic graph draws nothing" "$(cat "$TEST_TMPDIR/out-basic-cycles/dependency-graph.md")" "No cycle edges to draw."

threshold="$(make_tree threshold)"
for i in $(seq -w 1 41); do
  mkdir -p "$threshold/g$i"
  printf '%s\n' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup></Project>' >"$threshold/g$i/App.csproj"
done
cat >"$threshold/g01/App.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup><ProjectReference Include="..\g02\App.csproj" /></ItemGroup>
</Project>
CSPROJ
th_json="$(bash "$GRAPH" "$threshold")"
assert_equals "threshold: collector exits 0" "$?" "0"
assert_contains "threshold: the record stays at project resolution" "$th_json" '"id":"g01/App.csproj"'
mkdir -p "$TEST_TMPDIR/out-threshold"
printf '%s\n' "$th_json" >"$TEST_TMPDIR/out-threshold/dependency-graph.json"
th_summary="$(bash "$RENDER" --record "$TEST_TMPDIR/out-threshold/dependency-graph.json" --out "$TEST_TMPDIR/out-threshold")"
assert_equals "threshold: renderer exits 0" "$?" "0"
assert_contains "threshold: summary says aggregated" "$th_summary" "aggregated=yes"
th_md="$(cat "$TEST_TMPDIR/out-threshold/dependency-graph.md")"
assert_contains "threshold: artifact says directory level" "$th_md" "Aggregated to directory level"
assert_contains "threshold: artifact names the documented threshold" "$th_md" "node threshold of 40"
th_mermaid="$(printf '%s\n' "$th_md" | awk '/^```mermaid$/,/^```$/')"
assert_not_contains "threshold: diagram does not draw project files" "$th_mermaid" "App.csproj"
assert_contains "threshold: diagram draws the directory edge" "$th_mermaid" "g01"

node_only="$(make_tree node-only)"
printf '%s\n' '{ "dependencies": { "left-pad": "1.0.0" } }' >"$node_only/package.json"
node_json="$(bash "$GRAPH" "$node_only")"
assert_equals "node-only: collector exits 0" "$?" "0"
assert_contains "node-only: result unknown" "$node_json" '"result": "unknown"'
assert_contains "node-only: names the manifest" "$node_json" "package.json"
assert_contains "node-only: does not invent an empty graph" "$node_json" "did not invent an empty graph"
assert_contains "node-only: nodes array is empty" "$node_json" '"nodes": []'
mkdir -p "$TEST_TMPDIR/out-node"
printf '%s\n' "$node_json" >"$TEST_TMPDIR/out-node/dependency-graph.json"
node_summary="$(bash "$RENDER" --record "$TEST_TMPDIR/out-node/dependency-graph.json" --out "$TEST_TMPDIR/out-node")"
assert_equals "node-only: renderer exits 0" "$?" "0"
assert_contains "node-only: summary is unknown" "$node_summary" "result=unknown"
node_md="$(cat "$TEST_TMPDIR/out-node/dependency-graph.md")"
assert_contains "node-only: prose says it is not an empty graph" "$node_md" "not an empty graph"
assert_not_contains "node-only: no mermaid flowchart" "$node_md" '```mermaid'

empty="$(make_tree empty)"
empty_json="$(bash "$GRAPH" "$empty")"
assert_contains "empty tree: result unknown" "$empty_json" '"result": "unknown"'
assert_contains "empty tree: does not invent an empty graph" "$empty_json" "did not invent an empty graph"

sdk_only="$(make_tree sdk-only)"
printf '%s\n' '{ "sdk": { "version": "9.0.0" } }' >"$sdk_only/global.json"
sdk_json="$(bash "$GRAPH" "$sdk_only")"
assert_contains "global.json alone: result unknown" "$sdk_json" '"result": "unknown"'
assert_contains "global.json alone: names the file" "$sdk_json" "global.json"
assert_contains "global.json alone: does not invent an empty graph" "$sdk_json" "did not invent an empty graph"

mkdir -p "$TEST_TMPDIR/out-bad"
cat >"$TEST_TMPDIR/pretty.json" <<'EOF'
{
  "schema_version": 1,
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "cycles_truncated": false,
  "nodes": [
    {
      "id": "a",
      "name": "a",
      "path": "a",
      "ecosystem": "dotnet",
      "kind": "project"
    }
  ],
  "edges": [],
  "cycles": [],
  "findings": []
}
EOF
bad="$(bash "$RENDER" --record "$TEST_TMPDIR/pretty.json" --out "$TEST_TMPDIR/out-bad" 2>&1)"
assert_equals "pretty JSON exits 1" "$?" "1"
assert_contains "pretty JSON names the layout" "$bad" "one-object-per-line layout"
assert_equals "pretty JSON writes nothing" "$(ls -A "$TEST_TMPDIR/out-bad")" ""

printf '%s\n' '{"schema_version": 1, "result": "ok", "message": "", "ecosystem": "dotnet", "node_threshold": 40, "cycles_truncated": false, "nodes": [{"id":"a","name":"a","path":"a","ecosystem":"dotnet","kind":"project"}], "edges": [], "cycles": [], "findings": []}' >"$TEST_TMPDIR/compact.json"
bad="$(bash "$RENDER" --record "$TEST_TMPDIR/compact.json" --out "$TEST_TMPDIR/out-bad" 2>&1)"
assert_equals "compact JSON exits 1" "$?" "1"
assert_contains "compact JSON names the layout" "$bad" "one-object-per-line layout"
assert_equals "compact JSON writes nothing" "$(ls -A "$TEST_TMPDIR/out-bad")" ""

printf '%s\n' '{"schema_version": 2, "result": "ok", "nodes": [], "edges": [], "cycles": [], "findings": []}' >"$TEST_TMPDIR/v2.json"
bad="$(bash "$RENDER" --record "$TEST_TMPDIR/v2.json" --out "$TEST_TMPDIR/out-bad" 2>&1)"
assert_equals "schema 2 exits 1" "$?" "1"
assert_contains "schema 2 names the version" "$bad" "schema_version 1"

help_out="$(bash "$GRAPH" --help)"
assert_equals "collector help exits 0" "$?" "0"
assert_contains "collector help documents the layout" "$help_out" "one-object-per-line"
assert_contains "collector help documents the threshold" "$help_out" "node_threshold"
bash "$GRAPH" >/dev/null 2>&1
assert_equals "collector without a path exits 2" "$?" "2"
bash "$GRAPH" "$TEST_TMPDIR/no-such-dir" >/dev/null 2>&1
assert_equals "collector missing path exits 1" "$?" "1"

# The portfolio collector still sees the same Include names after the move.
port_repo="$(make_tree port)"
mkdir -p "$port_repo/src"
cat >"$port_repo/src/Billing.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog" Version="4.0.0" />
    <PackageReference Include="MediatR" Version="12.4.0" />
  </ItemGroup>
</Project>
CSPROJ
git -C "$port_repo" init --quiet
git -C "$port_repo" config user.email "fixture@example.invalid"
git -C "$port_repo" config user.name "Fixture"
git -C "$port_repo" config commit.gpgsign false
git -C "$port_repo" add -A
git -C "$port_repo" commit --quiet --no-verify -m fixture
port_out="$(bash "$PORTFOLIO" "$port_repo")"
assert_equals "portfolio still exits 0" "$?" "0"
assert_contains "portfolio still collects Serilog" "$port_out" '"Serilog"'
assert_contains "portfolio still collects MediatR" "$port_out" '"MediatR"'

# A scan root whose name is a sed program must stay data. GNU sed's e flag would
# run the command if the root were interpolated into a substitution.
hostile_root="$TEST_TMPDIR/p|touch $TEST_TMPDIR/pwned;:|e;#"
mkdir -p "$hostile_root/src"
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' >"$hostile_root/src/App.csproj"
hostile_out="$(bash "$GRAPH" "$hostile_root" 2>&1)"
if [[ -e "$TEST_TMPDIR/pwned" ]]; then
  fail "a hostile root name runs no command" "pwned exists"
else
  pass "a hostile root name runs no command"
fi
assert_contains "a hostile root still yields a repo-relative path" "$hostile_out" '"src/App.csproj"'

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
