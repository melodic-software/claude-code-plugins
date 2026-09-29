#!/usr/bin/env bash
# Tests for collect-containers.sh and render-containers.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-containers.sh"
RENDER="$SCRIPT_DIR/render-containers.sh"
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

commit_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" add -A
  git -C "$dir" commit -q -m fixture
}

node_line() {
  awk -v id="$2" 'index($0, "\"" id "\"") && $0 ~ /\{"id":/ { print; exit }' "$1"
}

field() {
  awk -v key="$2" '
  {
    needle = "\"" key "\""
    pos = index($0, needle)
    if (pos == 0) exit 0
    i = pos + length(needle)
    n = length($0)
    while (i <= n && substr($0, i, 1) != ":") i++
    i++
    while (i <= n && substr($0, i, 1) == " ") i++
    if (substr($0, i, 1) != "\"") exit 0
    i++
    out = ""
    while (i <= n) {
      c = substr($0, i, 1)
      if (c == "\\") { i++; out = out substr($0, i, 1); i++; continue }
      if (c == "\"") { printf "%s", out; exit }
      out = out c
      i++
    }
  }
  ' <<<"$1"
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: names schema_version" "$help_out" "schema_version"

REPO="$TEST_TMPDIR/roles"
mkdir -p "$REPO/src/Worker" "$REPO/src/Api" "$REPO/src/Web" "$REPO/src/Services" "$REPO/src/WebJobs" "$REPO/deploy/Worker" "$REPO/src/HostExe"
cat >"$REPO/src/Worker/WebHost.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/Api/JobWorker.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/Web/Tool.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/Services/Library.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/WebJobs/Jobs.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <AzureFunctionsVersion>v4</AzureFunctionsVersion>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/HostExe/HostExe.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat >"$REPO/src/HostExe/Program.cs" <<'EOF'
var builder = WebApplication.CreateBuilder(args);
builder.MapGet("/health", () => "ok");
EOF
cat >"$REPO/deploy/Worker/Dockerfile" <<'EOF'
FROM mcr.microsoft.com/dotnet/aspnet:8.0
COPY app /app
EOF
printf 'COPY app /app\n' >"$REPO/deploy/tick.Dockerfile"
commit_repo "$REPO"
OUT="$TEST_TMPDIR/roles-out"
mkdir -p "$OUT"
bash "$COLLECT" --repo "$REPO" --out "$OUT/containers.json" --generated-on 2026-09-28 >"$OUT/collect.out"
assert_equals "roles: collect exits 0" "$?" "0"
REC="$OUT/containers.json"
web_line="$(node_line "$REC" 'src/Worker/WebHost.csproj')"
assert_equals "web sdk in a Worker directory is kind web" "$(field "$web_line" kind)" "web"
assert_equals "web sdk name is the project file" "$(field "$web_line" name)" "WebHost"
assert_contains "web sdk technology cites the framework" "$(field "$web_line" technology)" "net8.0"
worker_line="$(node_line "$REC" 'src/Api/JobWorker.csproj')"
assert_equals "worker sdk in an Api directory is kind worker" "$(field "$worker_line" kind)" "worker"
cli_line="$(node_line "$REC" 'src/Web/Tool.csproj')"
assert_equals "exe in a Web directory is kind cli" "$(field "$cli_line" kind)" "cli"
fn_line="$(node_line "$REC" 'src/WebJobs/Jobs.csproj')"
assert_equals "AzureFunctionsVersion is kind function" "$(field "$fn_line" kind)" "function"
host_line="$(node_line "$REC" 'src/HostExe/HostExe.csproj')"
assert_equals "host builder on an exe is kind api" "$(field "$host_line" kind)" "api"
assert_contains "host builder is cited" "$(field "$host_line" evidence)" "WebApplication.CreateBuilder"
lib_hit="$(node_line "$REC" 'src/Services/Library.csproj' || true)"
assert_equals "library in a Services directory is not a container" "$lib_hit" ""
docker_line="$(node_line "$REC" 'deploy/Worker/Dockerfile')"
assert_equals "aspnet image in a Worker directory is api" "$(field "$docker_line" kind)" "api"
tick_line="$(node_line "$REC" 'deploy/tick.Dockerfile')"
assert_equals "dockerfile with no FROM is technology unknown" "$(field "$tick_line" technology)" "unknown"
roles_shared="$(grep -c 'shared-infrastructure' "$REC" || true)"
assert_equals "same repository is not an edge" "$roles_shared" "0"

MONO="$TEST_TMPDIR/mono"
mkdir -p "$MONO/src/Host" "$MONO/src/Billing" "$MONO/src/Domain"
cat >"$MONO/src/Host/Host.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\Billing\Billing.csproj" />
  </ItemGroup>
</Project>
EOF
cat >"$MONO/src/Billing/Billing.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\Domain\Domain.csproj" />
  </ItemGroup>
</Project>
EOF
cat >"$MONO/src/Domain/Domain.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
cat >"$MONO/src/Billing/Program.cs" <<'EOF'
var builder = WebApplication.CreateBuilder(args);
var leak = "SOURCE_ONLY_SECRET";
EOF
commit_repo "$MONO"
MOUT="$TEST_TMPDIR/mono-out"
mkdir -p "$MOUT"
bash "$COLLECT" --repo "$MONO" --out "$MOUT/containers.json" --generated-on 2026-09-28 >"$MOUT/collect.out"
assert_equals "mono: collect exits 0" "$?" "0"
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect c4-plantuml >"$MOUT/render.out"
assert_equals "mono: c4-plantuml render exits 0" "$?" "0"
mono_text="$(cat "$MOUT/containers.json" "$MOUT/containers.md" "$MOUT/collect.out" "$MOUT/render.out")"
deployables="$(grep -c '"kind":"web"' "$MOUT/containers.json" || true)"
assert_equals "monolith is one web deployable" "$deployables" "1"
assert_contains "billing is a contained module" "$mono_text" '"path":"src/Billing/Billing.csproj"'
assert_contains "domain is contained transitively" "$mono_text" '"path":"src/Domain/Domain.csproj"'
assert_not_contains "source secret is not cited" "$mono_text" "SOURCE_ONLY_SECRET"
assert_not_contains "library host-builder text is not a second deployable" "$mono_text" '"id":"src/Billing/Billing.csproj"'
assert_contains "diagram names contained modules" "$mono_text" "Contains: Billing, Domain"
container_elems="$(grep -c 'Container(' "$MOUT/containers.md" || true)"
assert_equals "diagram draws one container" "$container_elems" "1"
assert_contains "summary counts modules" "$(cat "$MOUT/render.out")" "modules=2"
assert_contains "c4-plantuml includes the container library" "$mono_text" "!include <C4/C4_Container>"
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect likec4 >"$MOUT/struct.out"
assert_equals "mono: likec4 render exits 0" "$?" "0"
assert_contains "likec4 is a container view" "$(cat "$MOUT/containers.md")" "view containers of e_sys"
assert_contains "module evidence cites the whole reference tag" "$mono_text" 'Include=\"..\\Billing\\Billing.csproj\" />'

# The no-graph path reads references with the shared reader: a tag that spans
# lines with a single-quoted Include is a module, and a commented-out one is not.
SHARED="$TEST_TMPDIR/shared-reader"
mkdir -p "$SHARED/src/Host" "$SHARED/src/Lib" "$SHARED/src/Ghost"
cat >"$SHARED/src/Host/Host.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <ProjectReference
        Include='..\Lib\Lib.csproj' />
    <!-- <ProjectReference Include="..\Ghost\Ghost.csproj" /> -->
  </ItemGroup>
</Project>
EOF
cat >"$SHARED/src/Lib/Lib.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
cat >"$SHARED/src/Ghost/Ghost.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
commit_repo "$SHARED"
bash "$COLLECT" --repo "$SHARED" --out "$TEST_TMPDIR/shared-reader.json" --generated-on 2026-09-28 >/dev/null
assert_equals "shared reader: collect exits 0" "$?" "0"
shared_text="$(cat "$TEST_TMPDIR/shared-reader.json")"
assert_contains "shared reader: a multi-line single-quoted reference is a module" "$shared_text" '"path":"src/Lib/Lib.csproj"'
assert_contains "shared reader: the citation runs through the closing bracket" "$shared_text" "Include='..\\\\Lib\\\\Lib.csproj' />"
assert_not_contains "shared reader: a commented-out reference is not a module" "$shared_text" 'src/Ghost/Ghost.csproj'

BUS="$TEST_TMPDIR/bus"
mkdir -p "$BUS/src/Api" "$BUS/src/Worker"
cat >"$BUS/src/Api/Api.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
cat >"$BUS/src/Worker/Worker.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
# Fixture credentials expand from variables so no committed line reads as a live credential to a secret scanner.
leak_sql="super-secret-password"
leak_blob="abcDEF123secretkey"
leak_bearer="sk-live-abc123secret"
cat >"$BUS/src/Api/appsettings.json" <<EOF
{
  "Messaging": { "Broker": "sb://orders.servicebus.windows.net/" },
  "ConnectionStrings": {
    "Orders": "Server=tcp:orders.database.windows.net,1433;User ID=sa;Password=${leak_sql};AccountKey=${leak_blob};"
  },
  "Auth": { "ApiKey": "${leak_bearer}" }
}
EOF
cat >"$BUS/src/Worker/appsettings.json" <<'EOF'
{
  "Messaging": { "Broker": "sb://orders.servicebus.windows.net/" },
  "Endpoint": "https://user:url-password-zzz@db.example/path"
}
EOF
commit_repo "$BUS"
printf '%s\n' '{ "Messaging": { "Broker": "sb://UNTRACKED_SECRET_VALUE.servicebus.windows.net/" } }' >"$BUS/src/Api/appsettings.Local.json"
BOUT="$TEST_TMPDIR/bus-out"
mkdir -p "$BOUT"
bash "$COLLECT" --repo "$BUS" --out "$BOUT/containers.json" --generated-on 2026-09-28 >"$BOUT/collect.out" 2>"$BOUT/collect.err"
assert_equals "bus: collect exits 0" "$?" "0"
bash "$RENDER" --record "$BOUT/containers.json" --out "$BOUT" --dialect c4-plantuml >"$BOUT/render.out" 2>"$BOUT/render.err"
assert_equals "bus: render exits 0" "$?" "0"
bus_text="$(cat "$BOUT/containers.json" "$BOUT/containers.md" "$BOUT/collect.out" "$BOUT/collect.err" "$BOUT/render.out" "$BOUT/render.err")"
assert_contains "shared-infrastructure edge exists" "$bus_text" '"kind":"shared-infrastructure"'
assert_contains "edge cites the api config" "$bus_text" "src/Api/appsettings.json: Messaging.Broker"
assert_contains "edge cites the worker config" "$bus_text" "src/Worker/appsettings.json: Messaging.Broker"
assert_not_contains "password is redacted" "$bus_text" "$leak_sql"
assert_not_contains "account key is redacted" "$bus_text" "$leak_blob"
assert_not_contains "api token is redacted" "$bus_text" "$leak_bearer"
assert_not_contains "url password is redacted" "$bus_text" "url-password-zzz"
assert_not_contains "untracked secret is not cited" "$bus_text" "UNTRACKED_SECRET_VALUE"
assert_contains "database host remains citable" "$bus_text" "orders.database.windows.net"
missing_tech="$(awk '/\{"id":/ && $0 !~ /"technology":/ { c++ } END { print c+0 }' "$BOUT/containers.json")"
assert_equals "every node has a technology field" "$missing_tech" "0"

cat >"$TEST_TMPDIR/bad-record.json" <<'EOF'
{
  "schema_version": 1,
  "subject": "x",
  "generated_on": "2026-09-28",
  "focal": "x",
  "containment": "project-references",
  "containers": [
    {
      "id": "a",
      "name": "a",
      "kind": "web",
      "technology": "unknown",
      "store_kind": "",
      "summary": "",
      "evidence": "a"
    }
  ],
  "modules": [],
  "edges": []
}
EOF
mkdir -p "$TEST_TMPDIR/bad-render"
set +e
bash "$RENDER" --record "$TEST_TMPDIR/bad-record.json" --out "$TEST_TMPDIR/bad-render" >"$TEST_TMPDIR/bad-render.out" 2>"$TEST_TMPDIR/bad-render.err"
rend_rc=$?
set +e
assert_equals "renderer rejects a reformatted record" "$rend_rc" "1"
if [[ -e "$TEST_TMPDIR/bad-render/containers.md" ]]; then
  fail "renderer writes nothing on a bad record" "containers.md exists"
else
  pass "renderer writes nothing on a bad record"
fi

set +e
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect mermaid >"$MOUT/like.out" 2>"$MOUT/like.err"
like_rc=$?
assert_equals "mermaid is refused" "$like_rc" "2"
assert_contains "refusal names diagram_dialect.system" "$(cat "$MOUT/like.err")" "diagram_dialect.system"
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect structurizr >/dev/null 2>&1
assert_equals "structurizr is refused" "$?" "2"
mkdir -p "$TEST_TMPDIR/none-render"
none_out="$(bash "$RENDER" --record "$MOUT/containers.json" --out "$TEST_TMPDIR/none-render")"
assert_contains "unset dialect reports none" "$none_out" "dialect=none"
assert_contains "unset dialect says no view" "$(cat "$TEST_TMPDIR/none-render/containers.md")" "unset (no C4 view emitted)"
assert_equals "unset dialect draws no fence" "$(grep -c '^```' "$TEST_TMPDIR/none-render/containers.md")" "0"
sed 's/"name":"[^"]*"/"name":"evil\\")\\n@enduml```x"/' "$MOUT/containers.json" >"$TEST_TMPDIR/hostile.json"
mkdir -p "$TEST_TMPDIR/hostile-render"
bash "$RENDER" --record "$TEST_TMPDIR/hostile.json" --out "$TEST_TMPDIR/hostile-render" --dialect c4-plantuml >/dev/null
assert_equals "hostile: one @enduml line" "$(grep -c '^@enduml$' "$TEST_TMPDIR/hostile-render/containers.md")" "1"
assert_equals "hostile: two fence lines" "$(grep -c '^```' "$TEST_TMPDIR/hostile-render/containers.md")" "2"
assert_contains "hostile: the name is drawn, sanitized" "$(cat "$TEST_TMPDIR/hostile-render/containers.md")" "evil') @enduml'''x"

GRAPH="$TEST_TMPDIR/graph-repo"
mkdir -p "$GRAPH/src/Host" "$GRAPH/src/OnlyGraph" "$GRAPH/src/FromFile" "$GRAPH/src/Phantom"
cat >"$GRAPH/src/Phantom/Phantom.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
cat >"$GRAPH/src/Host/Host.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\FromFile\FromFile.csproj" />
  </ItemGroup>
</Project>
EOF
cat >"$GRAPH/src/OnlyGraph/OnlyGraph.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
cat >"$GRAPH/src/FromFile/FromFile.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
commit_repo "$GRAPH"
cat >"$TEST_TMPDIR/graph.json" <<'EOF'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "nodes": [
    {"id":"src/Host/Host.csproj","name":"Host","path":"src/Host/Host.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/Host/Host.csproj","to":"src/OnlyGraph/OnlyGraph.csproj","kind":"project","status":"resolved","evidence":"graph: Host to OnlyGraph"},
    {"from":"src/Host/Host.csproj","to":"src/Phantom/Phantom.csproj","kind":"project","status":"unresolved","evidence":"graph: Host to a missing Phantom"}
  ]
}
EOF
GOUT="$TEST_TMPDIR/graph-out"
mkdir -p "$GOUT"
bash "$COLLECT" --repo "$GRAPH" --graph "$TEST_TMPDIR/graph.json" --out "$GOUT/containers.json" --generated-on 2026-09-28 >"$GOUT/collect.out"
assert_equals "graph: collect exits 0" "$?" "0"
gtext="$(cat "$GOUT/containers.json")"
assert_contains "graph supplies the contained module" "$gtext" '"path":"src/OnlyGraph/OnlyGraph.csproj"'
assert_not_contains "file reference is not used when the graph is present" "$gtext" "src/FromFile/FromFile.csproj"
assert_contains "containment source is the graph" "$gtext" '"containment": "dependency-graph.json"'
assert_not_contains "an unresolved graph edge is not a module even when its text is a project path" "$gtext" "src/Phantom/Phantom.csproj"

LINK="$TEST_TMPDIR/link-repo"
mkdir -p "$LINK/src/Api"
printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' >"$LINK/src/Api/Api.csproj"
printf 'outside.json\n' >"$LINK/.gitignore"
printf '{ "ConnectionStrings": { "Orders": "Server=leak.db.example;Database=o" } }\n' >"$LINK/outside.json"
ln -s ../../outside.json "$LINK/src/Api/appsettings.json"
commit_repo "$LINK"
bash "$COLLECT" --repo "$LINK" --out "$TEST_TMPDIR/link.json" --generated-on 2026-09-28 >/dev/null 2>&1
assert_not_contains "symlink: a tracked link to an untracked file is not a source" "$(cat "$TEST_TMPDIR/link.json")" "leak.db.example"

REC="$TEST_TMPDIR/records-repo"
mkdir -p "$REC/src/Api" "$REC/docs/architecture"
printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' >"$REC/src/Api/Api.csproj"
printf '{ "ConnectionStrings": { "Orders": "Server=real.db.example;Database=o" } }\n' >"$REC/src/Api/appsettings.json"
for rec in deployment containers events; do
  printf '{ "ConnectionStrings": { "Orders": "Server=%s.record.example;Database=o" } }\n' "$rec" >"$REC/docs/architecture/$rec.json"
done
commit_repo "$REC"
bash "$COLLECT" --repo "$REC" --out "$TEST_TMPDIR/records.json" --generated-on 2026-09-28 >/dev/null 2>&1
rec_text="$(cat "$TEST_TMPDIR/records.json")"
assert_contains "family records: a real config file still yields a row" "$rec_text" "real.db.example"
assert_not_contains "family records: tracked deployment, containers and events records are not sources" "$rec_text" "record.example"

printf 'cases=%s failed=%s\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
