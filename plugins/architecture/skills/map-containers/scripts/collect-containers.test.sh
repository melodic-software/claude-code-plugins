#!/usr/bin/env bash
# Tests for collect-containers.sh and render-containers.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-containers.sh"
RENDER="$SCRIPT_DIR/render-containers.sh"
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
assert_likec4_golden "containers.c4" "$MOUT/containers.md"
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

web_project() {
  mkdir -p "$1"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' >"$1/$2.csproj"
}
config_json() {
  printf '{ "%s": { "%s": "%s" } }\n' "$2" "$3" "$4" >"$1/appsettings.json"
}
collect_render() {
  mkdir -p "$2"
  bash "$COLLECT" --repo "$1" --out "$2/containers.json" --generated-on 2026-09-28 >"$2/collect.out" 2>"$2/collect.err"
  bash "$RENDER" --record "$2/containers.json" --out "$2" --dialect c4-plantuml >"$2/render.out" 2>"$2/render.err"
}

# FROM: a digest, options, a variable, and stages do not become the image name.
DOCK="$TEST_TMPDIR/docker-repo"
web_project "$DOCK/src/Api" Api
digest="sha256:$(printf 'a%.0s' {1..64})"
printf 'FROM mcr.microsoft.com/dotnet/aspnet:8.0@%s\nCOPY app /app\n' "$digest" >"$DOCK/src/Api/Dockerfile"
mkdir -p "$DOCK/images/digest" "$DOCK/images/platform" "$DOCK/images/arg" "$DOCK/images/brace" "$DOCK/images/alias" "$DOCK/images/stage" "$DOCK/images/argstage"
printf 'FROM mcr.microsoft.com/dotnet/aspnet:8.0@%s\n' "$digest" >"$DOCK/images/digest/Dockerfile"
cat >"$DOCK/images/platform/Dockerfile" <<'EOF'
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0 AS build
EOF
cat >"$DOCK/images/arg/Dockerfile" <<'EOF'
ARG BASE=alpine
FROM $BASE
EOF
cat >"$DOCK/images/brace/Dockerfile" <<'EOF'
FROM ${REGISTRY}/app:1
EOF
cat >"$DOCK/images/alias/Dockerfile" <<'EOF'
FROM alpine:3.20 AS runtime
COPY app /app
EOF
cat >"$DOCK/images/stage/Dockerfile" <<'EOF'
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
FROM base AS final
EOF
cat >"$DOCK/images/argstage/Dockerfile" <<'EOF'
ARG BASE=alpine
FROM $BASE AS base
FROM base AS final
EOF
commit_repo "$DOCK"
collect_render "$DOCK" "$TEST_TMPDIR/docker-out"
DREC="$TEST_TMPDIR/docker-out/containers.json"
dtext="$(cat "$DREC")"
digest_line="$(node_line "$DREC" 'images/digest/Dockerfile')"
assert_equals "FROM digest: technology is the image without the digest" "$(field "$digest_line" technology)" "mcr.microsoft.com/dotnet/aspnet:8.0"
assert_equals "FROM digest: the aspnet image is still kind api" "$(field "$digest_line" kind)" "api"
assert_not_contains "FROM digest: the hash is not cited anywhere" "$dtext" "sha256:"
assert_contains "FROM digest: an attached Dockerfile cites the image" "$(field "$(node_line "$DREC" 'src/Api/Api.csproj')" evidence)" "Dockerfile FROM mcr.microsoft.com/dotnet/aspnet:8.0"
assert_equals "FROM --platform: the option is not the image" "$(field "$(node_line "$DREC" 'images/platform/Dockerfile')" technology)" "mcr.microsoft.com/dotnet/sdk:8.0"
assert_equals "FROM as: the stage name is not the image" "$(field "$(node_line "$DREC" 'images/alias/Dockerfile')" technology)" "alpine:3.20"
assert_equals "FROM \$ARG: a variable stores unknown" "$(field "$(node_line "$DREC" 'images/arg/Dockerfile')" technology)" "unknown"
assert_equals "FROM \${VAR}: a braced variable stores unknown" "$(field "$(node_line "$DREC" 'images/brace/Dockerfile')" technology)" "unknown"
assert_not_contains "FROM variable: the variable text is not stored" "$dtext" 'BUILDPLATFORM'
stage_line="$(node_line "$DREC" 'images/stage/Dockerfile')"
assert_equals "FROM stage: a last stage that names an earlier stage resolves to its image" "$(field "$stage_line" technology)" "mcr.microsoft.com/dotnet/aspnet:8.0"
assert_equals "FROM stage: the resolved aspnet image is kind api" "$(field "$stage_line" kind)" "api"
assert_equals "FROM stage: a stage built on a variable stays unknown" "$(field "$(node_line "$DREC" 'images/argstage/Dockerfile')" technology)" "unknown"

# Test projects are not deployables, even when the output type is Exe.
TESTS="$TEST_TMPDIR/tests-repo"
web_project "$TESTS/src/Api" Api
mkdir -p "$TESTS/tests/Api.Tests" "$TESTS/tests/Api.Bench" "$TESTS/tests/Api.Perf" "$TESTS/tests/Lib.Tests" "$TESTS/tools/Tool"
cat >"$TESTS/tests/Api.Tests/Api.Tests.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="xunit.v3" Version="1.0.0" /></ItemGroup>
</Project>
EOF
cat >"$TESTS/tests/Api.Bench/Api.Bench.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.0.0" /></ItemGroup>
</Project>
EOF
cat >"$TESTS/tests/Api.Perf/Api.Perf.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup>
</Project>
EOF
cat >"$TESTS/tests/Lib.Tests/Lib.Tests.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.0.0" /></ItemGroup>
</Project>
EOF
cat >"$TESTS/tools/Tool/Tool.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
EOF
commit_repo "$TESTS"
collect_render "$TESTS" "$TEST_TMPDIR/tests-out"
TREC="$TEST_TMPDIR/tests-out/containers.json"
ttext="$(cat "$TREC")"
assert_equals "tests: an Exe test project on the xunit package is not a deployable" "$(node_line "$TREC" 'tests/Api.Tests/Api.Tests.csproj' || true)" ""
assert_equals "tests: an Exe project on the test SDK is not a deployable" "$(node_line "$TREC" 'tests/Api.Bench/Api.Bench.csproj' || true)" ""
assert_equals "tests: IsTestProject=true is not a deployable" "$(node_line "$TREC" 'tests/Api.Perf/Api.Perf.csproj' || true)" ""
assert_equals "tests: a plain Exe is still a cli" "$(field "$(node_line "$TREC" 'tools/Tool/Tool.csproj')" kind)" "cli"
assert_equals "tests: the host is still a deployable" "$(field "$(node_line "$TREC" 'src/Api/Api.csproj')" kind)" "web"
assert_contains "tests: the excluded count is a finding" "$ttext" '"kind":"excluded-test-projects","count":3,'
assert_contains "tests: the finding names an excluded project" "$ttext" "tests/Api.Bench/Api.Bench.csproj"
assert_not_contains "tests: a library test project that was never a candidate is not counted" "$ttext" "Lib.Tests"
assert_contains "tests: the report line carries the excluded count" "$(cat "$TEST_TMPDIR/tests-out/render.out")" "excluded_tests=3"
assert_equals "tests: the diagram draws the host and the tool only" "$(grep -c 'Container(' "$TEST_TMPDIR/tests-out/containers.md" || true)" "2"

# SQL identity is host, port, and database.
DBS="$TEST_TMPDIR/dbs-repo"
for svc in Orders Billing Reports Legacy1 Legacy2; do
  web_project "$DBS/src/$svc" "$svc"
done
config_json "$DBS/src/Orders" ConnectionStrings Main "Server=tcp:sql.example.com,1433;Initial Catalog=Orders;User ID=sa;Password=${leak_sql}"
config_json "$DBS/src/Billing" ConnectionStrings Main "Server=tcp:sql.example.com,1433;Database=Billing;User ID=sa;Password=${leak_sql}"
config_json "$DBS/src/Reports" ConnectionStrings Main "Server=tcp:sql.example.com,1433;Database=orders;User ID=sa;Password=${leak_sql}"
config_json "$DBS/src/Legacy1" ConnectionStrings Main "Server=legacy.example.com;User ID=sa;Password=${leak_sql}"
config_json "$DBS/src/Legacy2" ConnectionStrings Main "Server=legacy.example.com;User ID=sa;Password=${leak_sql}"
commit_repo "$DBS"
collect_render "$DBS" "$TEST_TMPDIR/dbs-out"
SREC="$TEST_TMPDIR/dbs-out/containers.json"
stext="$(cat "$SREC")"
mkdir -p "$TEST_TMPDIR/dbs-likec4"
bash "$RENDER" --record "$SREC" --out "$TEST_TMPDIR/dbs-likec4" --dialect likec4 >/dev/null
assert_likec4_golden "containers-stores.c4" "$TEST_TMPDIR/dbs-likec4/containers.md"
assert_equals "database: two databases on one server and one server with none are three stores" "$(grep -c '"kind":"store"' "$SREC" || true)" "3"
assert_contains "database: the store id carries the database" "$stext" '"id":"store:sql:sql.example.com:1433:orders"'
assert_contains "database: the store name carries the database" "$(field "$(node_line "$SREC" 'store:sql:sql.example.com:1433:billing')" name)" "sql.example.com/billing"
assert_contains "database: two owners of one database share it" "$stext" '{"from":"src/Orders/Orders.csproj","to":"src/Reports/Reports.csproj","kind":"shared-infrastructure","via":"store:sql:sql.example.com:1433:orders"'
assert_equals "database: a different database on the same server is not shared" "$(grep 'shared-infrastructure' "$SREC" | grep -c 'Billing' || true)" "0"
assert_equals "database: same database shared, and same unknown-database server shared" "$(grep -c '"kind":"shared-infrastructure"' "$SREC" || true)" "2"
assert_contains "database: no database is named in the store id" "$stext" '"id":"store:sql:legacy.example.com::database unknown"'
unknown_edge="$(grep 'shared-infrastructure' "$SREC" | grep 'Legacy1' || true)"
assert_contains "database: a shared unknown-database edge says so" "$unknown_edge" "same server, database unknown"
assert_not_contains "database: a shared known-database edge does not" "$(grep 'shared-infrastructure' "$SREC" | grep 'Reports' || true)" "database unknown"
assert_not_contains "database: the password is redacted" "$(cat "$SREC" "$TEST_TMPDIR/dbs-out/containers.md")" "$leak_sql"
assert_contains "database: the report line counts both shared rows" "$(cat "$TEST_TMPDIR/dbs-out/render.out")" "shared=2"

# The technology of a sql store is its scheme, never SQL for a host that is not.
TECH="$TEST_TMPDIR/tech-repo"
web_project "$TECH/src/Api" Api
cat >"$TECH/src/Api/appsettings.json" <<EOF
{
  "Stores": {
    "Mongo": "mongodb+srv://svc:${leak_sql}@mongo.example.com/catalog?authSource=admin",
    "Pg": "postgresql://svc:${leak_sql}@pg.example.com:5432/orders",
    "My": "mysql://svc:${leak_sql}@my.example.com:3306/shop",
    "Plain": "Server=plain.example.com;Database=misc;User ID=sa;Password=${leak_sql}",
    "Azure": "Server=tcp:az.database.windows.net,1433;Initial Catalog=x;User ID=sa;Password=${leak_sql}",
    "Search": "https://acct.search.windows.net",
    "Lite": "Data Source=embedded-app.db;Foreign Keys=True"
  }
}
EOF
commit_repo "$TECH"
collect_render "$TECH" "$TEST_TMPDIR/tech-out"
XREC="$TEST_TMPDIR/tech-out/containers.json"
xtext="$(cat "$XREC")"
assert_equals "technology: a mongodb URL is mongodb" "$(field "$(node_line "$XREC" 'store:sql:mongo.example.com::catalog')" technology)" "mongodb"
assert_equals "technology: a postgresql URL is postgres" "$(field "$(node_line "$XREC" 'store:sql:pg.example.com:5432:orders')" technology)" "postgres"
assert_equals "technology: a mysql URL is mysql" "$(field "$(node_line "$XREC" 'store:sql:my.example.com:3306:shop')" technology)" "mysql"
assert_equals "technology: a connection string on a plain host is unknown" "$(field "$(node_line "$XREC" 'store:sql:plain.example.com::misc')" technology)" "unknown"
assert_equals "technology: an Azure SQL host is Azure SQL" "$(field "$(node_line "$XREC" 'store:sql:az.database.windows.net:1433:x')" technology)" "Azure SQL"
assert_equals "technology: every one of those stays kind sql" "$(grep -c '"store_kind":"sql"' "$XREC" || true)" "5"
assert_not_contains "technology: nothing is labeled SQL" "$xtext" '"technology":"SQL"'
assert_equals "technology: an Azure AI Search host is Azure AI Search" "$(field "$(node_line "$XREC" 'store:search:acct.search.windows.net:')" technology)" "Azure AI Search"
assert_not_contains "technology: a SQLite Data Source file is not a store" "$xtext" "embedded-app.db"
assert_not_contains "technology: the password is redacted" "$xtext" "$leak_sql"

# A search endpoint is a search store, and its api key never reaches an output.
leak_search="searchAdminKey0123456789"
SRCH="$TEST_TMPDIR/search-repo"
web_project "$SRCH/src/Api" Api
cat >"$SRCH/src/Api/appsettings.json" <<EOF
{
  "Search": { "Endpoint": "https://acct.search.windows.net", "ApiKey": "${leak_search}" },
  "Indexing": { "ElasticsearchUrl": "https://user:${leak_search}@es.internal.example.com:9200" },
  "Aws": { "Domain": "https://vpc-logs.us-east-1.es.amazonaws.com" }
}
EOF
mkdir -p "$SRCH/deploy"
printf 'services:\n  index:\n    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.0\n' >"$SRCH/deploy/compose.yml"
commit_repo "$SRCH"
collect_render "$SRCH" "$TEST_TMPDIR/search-out"
SREC2="$TEST_TMPDIR/search-out/containers.json"
az_line="$(node_line "$SREC2" 'store:search:acct.search.windows.net:')"
assert_equals "search: an Azure AI Search endpoint is a search store" "$(field "$az_line" store_kind)" "search"
assert_equals "search: its technology is Azure AI Search" "$(field "$az_line" technology)" "Azure AI Search"
assert_contains "search: it cites the file and key" "$(field "$az_line" evidence)" "src/Api/appsettings.json: Search.Endpoint"
assert_equals "search: a key named for elasticsearch is a search store" "$(field "$(node_line "$SREC2" 'store:search:es.internal.example.com:9200')" technology)" "unknown"
assert_equals "search: an es.amazonaws.com host is OpenSearch" "$(field "$(node_line "$SREC2" 'store:search:vpc-logs.us-east-1.es.amazonaws.com:')" technology)" "OpenSearch"
assert_equals "search: a compose elasticsearch image is a search store" "$(field "$(node_line "$SREC2" 'store:image:deploy/compose.yml:index')" store_kind)" "search"
assert_equals "search: three config stores and one image store" "$(grep -c '"store_kind":"search"' "$SREC2" || true)" "4"
assert_not_contains "search: the api key is in no record" "$(cat "$SREC2")" "$leak_search"
assert_not_contains "search: the api key is in no table" "$(cat "$TEST_TMPDIR/search-out/containers.md")" "$leak_search"
assert_not_contains "search: the api key is not on stdout or stderr" "$(cat "$TEST_TMPDIR/search-out"/*.out "$TEST_TMPDIR/search-out"/*.err)" "$leak_search"
assert_contains "search: the diagram draws it as a database" "$(cat "$TEST_TMPDIR/search-out/containers.md")" "ContainerDb"

# A store with three owners is one shared row per owner pair.
THREE="$TEST_TMPDIR/three-repo"
for svc in Api Worker Batch; do
  web_project "$THREE/src/$svc" "$svc"
  config_json "$THREE/src/$svc" Messaging Broker "sb://bus.servicebus.windows.net/"
done
commit_repo "$THREE"
collect_render "$THREE" "$TEST_TMPDIR/three-out"
HREC="$TEST_TMPDIR/three-out/containers.json"
htext="$(cat "$HREC")"
mkdir -p "$TEST_TMPDIR/three-likec4"
bash "$RENDER" --record "$HREC" --out "$TEST_TMPDIR/three-likec4" --dialect likec4 >/dev/null
assert_likec4_golden "containers-broker.c4" "$TEST_TMPDIR/three-likec4/containers.md"
assert_equals "three owners: one shared edge per owner pair" "$(grep -c '"kind":"shared-infrastructure"' "$HREC" || true)" "3"
assert_contains "three owners: api and batch" "$htext" '{"from":"src/Api/Api.csproj","to":"src/Batch/Batch.csproj","kind":"shared-infrastructure"'
assert_contains "three owners: api and worker" "$htext" '{"from":"src/Api/Api.csproj","to":"src/Worker/Worker.csproj","kind":"shared-infrastructure"'
assert_contains "three owners: batch and worker" "$htext" '{"from":"src/Batch/Batch.csproj","to":"src/Worker/Worker.csproj","kind":"shared-infrastructure"'
assert_not_contains "three owners: a pair cites only its own owners" "$(grep '"to":"src/Batch/Batch.csproj","kind":"shared-infrastructure"' "$HREC")" "src/Worker/appsettings.json"
assert_contains "three owners: the report line counts the pairs" "$(cat "$TEST_TMPDIR/three-out/render.out")" "shared=3"
hmd="$(cat "$TEST_TMPDIR/three-out/containers.md")"
assert_contains "three owners: the table names the store" "$hmd" "| from | to | store | evidence |"
assert_contains "three owners: the table lists every pair" "$hmd" "| src/Batch/Batch.csproj | src/Worker/Worker.csproj | store:broker:bus.servicebus.windows.net: |"
assert_contains "three owners: the table lists the first pair" "$hmd" "| src/Api/Api.csproj | src/Batch/Batch.csproj |"

# An endpoint a deployable's config names is an edge only through a cited fact.
leak_ep_pass="EndpointPass456"
leak_ep_tok="EndpointTok789"
leak_semi_tok="semitok321"
leak_semi_num="4815162342"
EP="$TEST_TMPDIR/endpoint-repo"
web_project "$EP/src/Web" Web
web_project "$EP/src/OrdersApi" OrdersApi
cat >"$EP/compose.yml" <<'EOC'
services:
  web:
    build: ./src/Web
  orders-api:
    build:
      context: ./src/OrdersApi
    ports:
      - "8081:8080"
EOC
cat >"$EP/src/Web/appsettings.json" <<'EOC'
{ "Services": { "OrdersApi": { "BaseUrl": "http://orders-api:8080" } } }
EOC
commit_repo "$EP"
collect_render "$EP" "$TEST_TMPDIR/endpoint-out"
EREC="$TEST_TMPDIR/endpoint-out/containers.json"
eedges="$(grep '"kind":"uses"' "$EREC" || true)"
assert_equals "endpoint: a configured base URL draws exactly one uses edge" "$(printf '%s\n' "$eedges" | grep -c . || true)" "1"
assert_contains "endpoint: it runs from the configuring deployable to the target" "$eedges" '{"from":"src/Web/Web.csproj","to":"src/OrdersApi/OrdersApi.csproj","kind":"uses"'
assert_contains "endpoint: it cites the file and config key" "$eedges" "src/Web/appsettings.json: Services.OrdersApi.BaseUrl"
assert_contains "endpoint: it cites the compose service that resolved the host" "$eedges" "compose.yml: service orders-api build src/OrdersApi"
assert_not_contains "endpoint: a resolved endpoint is not a finding" "$(cat "$EREC")" "external-endpoint"
emd="$(cat "$TEST_TMPDIR/endpoint-out/containers.md")"
assert_contains "endpoint: the plantuml diagram draws it" "$emd" 'Rel(e_Web, e_OrdersApi, "Uses"'
assert_contains "endpoint: the uses table lists it with its citation" "$emd" "| src/Web/Web.csproj | src/OrdersApi/OrdersApi.csproj | src/Web/appsettings.json: Services.OrdersApi.BaseUrl"
mkdir -p "$TEST_TMPDIR/endpoint-likec4" "$TEST_TMPDIR/endpoint-none"
bash "$RENDER" --record "$EREC" --out "$TEST_TMPDIR/endpoint-likec4" --dialect likec4 >/dev/null
assert_contains "endpoint: the likec4 diagram draws it" "$(cat "$TEST_TMPDIR/endpoint-likec4/containers.md")" 'e_sys.e_Web -> e_sys.e_OrdersApi "Uses"'
assert_likec4_golden "containers-endpoints.c4" "$TEST_TMPDIR/endpoint-likec4/containers.md"
bash "$RENDER" --record "$EREC" --out "$TEST_TMPDIR/endpoint-none" --dialect none >/dev/null
assert_contains "endpoint: the tables carry it when no diagram is drawn" "$(cat "$TEST_TMPDIR/endpoint-none/containers.md")" "| src/Web/Web.csproj | src/OrdersApi/OrdersApi.csproj |"

# A launchSettings applicationUrl on the target resolves a loopback endpoint on the same port.
LS="$TEST_TMPDIR/launch-repo"
web_project "$LS/src/Web" Web
web_project "$LS/src/Orders" Orders
mkdir -p "$LS/src/Orders/Properties"
cat >"$LS/src/Orders/Properties/launchSettings.json" <<'EOC'
{ "profiles": { "https": { "applicationUrl": "https://localhost:7001;http://localhost:5001" } } }
EOC
cat >"$LS/src/Web/appsettings.json" <<'EOC'
{ "Orders": { "Url": "http://localhost:5001", "Secure": "https://127.0.0.1:7001" } }
EOC
commit_repo "$LS"
collect_render "$LS" "$TEST_TMPDIR/launch-out"
LREC="$TEST_TMPDIR/launch-out/containers.json"
ledges="$(grep '"kind":"uses"' "$LREC" || true)"
assert_equals "launchSettings: two loopback endpoints on one target are one edge" "$(printf '%s\n' "$ledges" | grep -c . || true)" "1"
assert_contains "launchSettings: it runs from the configuring deployable" "$ledges" '{"from":"src/Web/Web.csproj","to":"src/Orders/Orders.csproj","kind":"uses"'
assert_contains "launchSettings: it cites both config keys" "$ledges" "src/Web/appsettings.json: Orders.Secure; src/Web/appsettings.json: Orders.Url"
assert_contains "launchSettings: it cites the applicationUrl" "$ledges" "src/Orders/Properties/launchSettings.json: profiles.https.applicationUrl"
assert_not_contains "launchSettings: a deployable's own listen address is not an endpoint" "$(cat "$LREC")" "external-endpoint"

# An endpoint that resolves to nothing, to more than one deployable, or only by resemblance draws no edge.
UNK="$TEST_TMPDIR/unknown-endpoint-repo"
web_project "$UNK/src/Web" Web
web_project "$UNK/src/OrdersApi" OrdersApi
web_project "$UNK/src/BillingApi" BillingApi
cat >"$UNK/compose.yml" <<'EOC'
services:
  orders-api:
    build: ./src/OrdersApi
    ports:
      - "8081:8080"
  shared:
    build: ./src/OrdersApi
EOC
cat >"$UNK/docker-compose.yml" <<'EOC'
services:
  shared:
    build: ./src/BillingApi
EOC
cat >"$UNK/src/Web/appsettings.json" <<'EOC'
{
  "Services": {
    "External": { "BaseUrl": "https://api.example.com" },
    "WrongPort": { "BaseUrl": "http://orders-api:9999" },
    "Similar": { "BaseUrl": "http://ordersapi:8080" },
    "Both": { "BaseUrl": "http://shared:8080" }
  }
}
EOC
cat >"$UNK/src/OrdersApi/appsettings.json" <<'EOC'
{ "Self": { "BaseUrl": "http://orders-api:8080" } }
EOC
commit_repo "$UNK"
collect_render "$UNK" "$TEST_TMPDIR/unknown-endpoint-out"
UREC="$TEST_TMPDIR/unknown-endpoint-out/containers.json"
utext="$(cat "$UREC")"
assert_equals "unresolved: no endpoint draws an edge" "$(grep -c '"kind":"uses"' "$UREC" || true)" "0"
assert_equals "unresolved: each unresolved endpoint is one finding, and a self-reference is none" "$(grep -c '"kind":"external-endpoint"' "$UREC" || true)" "4"
assert_contains "unresolved: an unknown host is an external endpoint with its file and key" "$utext" "src/Web/appsettings.json: Services.External.BaseUrl names host api.example.com; resolves to no deployable"
assert_contains "unresolved: a port the service does not declare is not matched" "$utext" "Services.WrongPort.BaseUrl names host orders-api:9999; resolves to no deployable"
assert_contains "unresolved: a name that only resembles a project is not matched" "$utext" "Services.Similar.BaseUrl names host ordersapi:8080; resolves to no deployable"
assert_contains "unresolved: a host naming two deployables is not guessed" "$utext" "Services.Both.BaseUrl names host shared:8080; matches more than one deployable"
assert_contains "unresolved: the findings table lists them" "$(cat "$TEST_TMPDIR/unknown-endpoint-out/containers.md")" "| external-endpoint | 1 |"

# Only an http or https URL is an endpoint, and an omitted port is the scheme's own default.
SCH="$TEST_TMPDIR/scheme-endpoint-repo"
web_project "$SCH/src/Web" Web
web_project "$SCH/src/PlainApi" PlainApi
web_project "$SCH/src/SecureApi" SecureApi
cat >"$SCH/compose.yml" <<'EOC'
services:
  plain-api:
    build: ./src/PlainApi
    ports:
      - "8080:80"
  secure-api:
    build: ./src/SecureApi
    ports:
      - "8443:443"
EOC
cat >"$SCH/src/Web/appsettings.json" <<'EOC'
{
  "Services": {
    "Plain": { "BaseUrl": "http://plain-api" },
    "Secure": { "BaseUrl": "https://secure-api" },
    "PlainOverTls": { "BaseUrl": "https://plain-api" },
    "SecureOverHttp": { "BaseUrl": "http://secure-api" },
    "Files": { "BaseUrl": "ftp://files.example.com" },
    "Share": { "BaseUrl": "file://localhost/share" }
  }
}
EOC
commit_repo "$SCH"
collect_render "$SCH" "$TEST_TMPDIR/scheme-endpoint-out"
SREC="$TEST_TMPDIR/scheme-endpoint-out/containers.json"
stext="$(cat "$SREC")"
assert_equals "scheme: only the two scheme-matched endpoints draw an edge" "$(grep -c '"kind":"uses"' "$SREC" || true)" "2"
assert_contains "scheme: http with no port reaches the service declaring 80" "$stext" '"to":"src/PlainApi/PlainApi.csproj","kind":"uses"'
assert_contains "scheme: https with no port reaches the service declaring 443" "$stext" '"to":"src/SecureApi/SecureApi.csproj","kind":"uses"'
assert_contains "scheme: https does not reach a service declaring only 80" "$stext" "Services.PlainOverTls.BaseUrl names host plain-api; resolves to no deployable"
assert_contains "scheme: http does not reach a service declaring only 443" "$stext" "Services.SecureOverHttp.BaseUrl names host secure-api; resolves to no deployable"
assert_equals "scheme: a non-http URL is neither an edge nor a finding" "$(grep -c '"kind":"external-endpoint"' "$SREC" || true)" "2"
assert_not_contains "scheme: an ftp URL is not recorded" "$stext" "files.example.com"

# Userinfo and a query token do not stop the edge from resolving, and neither reaches an output.
LEAK="$TEST_TMPDIR/leak-endpoint-repo"
web_project "$LEAK/src/Web" Web
web_project "$LEAK/src/OrdersApi" OrdersApi
cat >"$LEAK/compose.yml" <<'EOC'
services:
  orders-api:
    build: ./src/OrdersApi
EOC
cat >"$LEAK/src/Web/appsettings.json" <<EOC
{ "Services": { "Orders": { "BaseUrl": "https://user:${leak_ep_pass}@orders-api/?token=${leak_ep_tok}" } } }
EOC
commit_repo "$LEAK"
collect_render "$LEAK" "$TEST_TMPDIR/leak-endpoint-out"
mkdir -p "$TEST_TMPDIR/leak-endpoint-likec4"
bash "$RENDER" --record "$TEST_TMPDIR/leak-endpoint-out/containers.json" --out "$TEST_TMPDIR/leak-endpoint-likec4" --dialect likec4 >"$TEST_TMPDIR/leak-endpoint-likec4/render.out" 2>&1
leak_ep_text="$(cat "$TEST_TMPDIR/leak-endpoint-out"/* "$TEST_TMPDIR/leak-endpoint-likec4"/*)"
assert_contains "leak: the edge still resolves" "$leak_ep_text" '{"from":"src/Web/Web.csproj","to":"src/OrdersApi/OrdersApi.csproj","kind":"uses"'
assert_not_contains "leak: the password is in no output" "$leak_ep_text" "$leak_ep_pass"
assert_not_contains "leak: the query token is in no output" "$leak_ep_text" "$leak_ep_tok"
assert_not_contains "leak: the userinfo is in no output" "$leak_ep_text" "user:"

# A ; inside userinfo is credential text: it is never the host of an edge or a finding.
SEMI="$TEST_TMPDIR/semi-userinfo-repo"
web_project "$SEMI/src/Web" Web
web_project "$SEMI/src/OrdersApi" OrdersApi
cat >"$SEMI/compose.yml" <<'EOC'
services:
  orders-api:
    build: ./src/OrdersApi
EOC
cat >"$SEMI/src/Web/appsettings.json" <<EOC
{
  "Services": {
    "External": { "BaseUrl": "https://${leak_semi_tok};x@api.example.com" },
    "Numeric": { "BaseUrl": "https://svc:${leak_semi_num};x@api.example.com" },
    "Orders": { "BaseUrl": "https://${leak_semi_tok};y@orders-api/" }
  }
}
EOC
commit_repo "$SEMI"
collect_render "$SEMI" "$TEST_TMPDIR/semi-userinfo-out"
mkdir -p "$TEST_TMPDIR/semi-userinfo-likec4"
bash "$RENDER" --record "$TEST_TMPDIR/semi-userinfo-out/containers.json" --out "$TEST_TMPDIR/semi-userinfo-likec4" --dialect likec4 >"$TEST_TMPDIR/semi-userinfo-likec4/render.out" 2>&1
semi_text="$(cat "$TEST_TMPDIR/semi-userinfo-out"/* "$TEST_TMPDIR/semi-userinfo-likec4"/*)"
assert_contains "semicolon userinfo: the edge still resolves" "$semi_text" '{"from":"src/Web/Web.csproj","to":"src/OrdersApi/OrdersApi.csproj","kind":"uses"'
assert_contains "semicolon userinfo: a word before the ; is not the host" "$semi_text" "Services.External.BaseUrl names host api.example.com; resolves to no deployable"
assert_contains "semicolon userinfo: a number before the ; is not the port" "$semi_text" "Services.Numeric.BaseUrl names host api.example.com; resolves to no deployable"
assert_not_contains "semicolon userinfo: the word is in no output" "$semi_text" "$leak_semi_tok"
assert_not_contains "semicolon userinfo: the number is in no output" "$semi_text" "$leak_semi_num"

# Files are read from the working tree, and a dirty tracked file is a finding.
DIRTY="$TEST_TMPDIR/dirty-repo"
web_project "$DIRTY/src/Api" Api
config_json "$DIRTY/src/Api" ConnectionStrings Main "Server=committed.example.com;Database=o"
commit_repo "$DIRTY"
collect_render "$DIRTY" "$TEST_TMPDIR/clean-out"
assert_not_contains "clean tree: no dirty finding" "$(cat "$TEST_TMPDIR/clean-out/containers.json")" "dirty-tracked-files"
assert_contains "clean tree: the report line says zero" "$(cat "$TEST_TMPDIR/clean-out/render.out")" "dirty_tracked_files=0"
printf 'notes\n' >"$DIRTY/notes2.txt"
config_json "$DIRTY/src/Api" ConnectionStrings Main "Server=edited.example.com;Database=o"
collect_render "$DIRTY" "$TEST_TMPDIR/dirty-out"
dirtext="$(cat "$TEST_TMPDIR/dirty-out/containers.json")"
assert_contains "dirty tree: one edited tracked file is one finding" "$dirtext" '"kind":"dirty-tracked-files","count":1,'
assert_contains "dirty tree: the working-tree content is what is charted" "$dirtext" "edited.example.com"
assert_not_contains "dirty tree: the committed content is not" "$dirtext" "committed.example.com"
assert_contains "dirty tree: the collector says so on stderr" "$(cat "$TEST_TMPDIR/dirty-out/collect.err")" "1 tracked file(s) differ from HEAD"
assert_contains "dirty tree: the report line carries the count" "$(cat "$TEST_TMPDIR/dirty-out/render.out")" "dirty_tracked_files=1"
assert_contains "dirty tree: the tables carry the finding" "$(cat "$TEST_TMPDIR/dirty-out/containers.md")" "| dirty-tracked-files | 1 |"
assert_not_contains "bus: untracked files are not dirty tracked files" "$bus_text" "dirty-tracked-files"

# The findings array is optional, and one that is not one object per line is refused.
cat >"$TEST_TMPDIR/old-record.json" <<'EOF'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "subject": "x",
  "focal": "x",
  "containment": "project-references",
  "containers": [
    {"id":"a","name":"a","kind":"web","technology":"unknown","store_kind":"","summary":"","evidence":"a"}
  ],
  "modules": [],
  "edges": []
}
EOF
mkdir -p "$TEST_TMPDIR/old-render"
old_out="$(bash "$RENDER" --record "$TEST_TMPDIR/old-record.json" --out "$TEST_TMPDIR/old-render" --dialect none)"
assert_equals "findings: a record without the array renders" "$?" "0"
assert_contains "findings: its counts are zero" "$old_out" "excluded_tests=0 dirty_tracked_files=0"
sed 's/^  "edges": \[\]$/  "edges": [],\n  "findings": [{"kind":"dirty-tracked-files","count":1,"evidence":"x"}]/' "$TEST_TMPDIR/old-record.json" >"$TEST_TMPDIR/compact-findings.json"
bash "$RENDER" --record "$TEST_TMPDIR/compact-findings.json" --out "$TEST_TMPDIR/old-render" --dialect none >/dev/null 2>"$TEST_TMPDIR/compact-findings.err"
assert_equals "findings: a compacted array is refused" "$?" "1"
assert_contains "findings: the refusal names the array" "$(cat "$TEST_TMPDIR/compact-findings.err")" "findings array"

printf 'cases=%s failed=%s\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
