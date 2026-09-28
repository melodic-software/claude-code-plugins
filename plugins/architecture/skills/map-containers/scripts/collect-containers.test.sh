#!/usr/bin/env bash
# Tests for collect-containers.sh and render-containers.sh.
set -uo pipefail

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
  git -C "$dir" add -A
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
    git -C "$dir" commit -q -m fixture
}

node_line() {
  awk -v id="$2" 'index($0, id) && $0 ~ /\{"id":/ { print; exit }' "$1"
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

# --- output kind comes from the project file, not the directory ------------

REPO="$TEST_TMPDIR/roles"
mkdir -p "$REPO/src/Worker" "$REPO/src/Api" "$REPO/src/Web" "$REPO/src/Services" "$REPO/src/WebJobs" "$REPO/deploy/Worker"
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
cat >"$REPO/deploy/Worker/Dockerfile" <<'EOF'
FROM mcr.microsoft.com/dotnet/aspnet:8.0
COPY app /app
EOF
commit_repo "$REPO"
OUT="$TEST_TMPDIR/roles-out"
mkdir -p "$OUT"
bash "$COLLECT" --repo "$REPO" --out "$OUT/containers.json" --generated-on 2026-09-28 >"$OUT/collect.out"
REC="$OUT/containers.json"
web_line="$(node_line "$REC" 'src/Worker/WebHost.csproj')"
assert_equals "web sdk in a Worker directory is output_kind web" "$(field "$web_line" output_kind)" "web"
assert_equals "web sdk name is the project file" "$(field "$web_line" name)" "WebHost"
assert_contains "web sdk technology cites the framework" "$(field "$web_line" technology)" "net8.0"
worker_line="$(node_line "$REC" 'src/Api/JobWorker.csproj')"
assert_equals "worker sdk in an Api directory is output_kind worker" "$(field "$worker_line" output_kind)" "worker"
cli_line="$(node_line "$REC" 'src/Web/Tool.csproj')"
assert_equals "exe in a Web directory is output_kind cli" "$(field "$cli_line" output_kind)" "cli"
fn_line="$(node_line "$REC" 'src/WebJobs/Jobs.csproj')"
assert_equals "AzureFunctionsVersion wins over OutputType Exe" "$(field "$fn_line" output_kind)" "function"
lib_hit="$(node_line "$REC" 'src/Services/Library.csproj' || true)"
assert_equals "library in a Services directory is not a container" "$lib_hit" ""
docker_line="$(node_line "$REC" 'deploy/Worker/Dockerfile')"
assert_equals "aspnet image in a Worker directory is api, not worker" "$(field "$docker_line" output_kind)" "api"
roles_shared="$(grep -c 'shared-infrastructure' "$REC" || true)"
assert_equals "same repository is not an edge" "$roles_shared" "0"

# --- modular monolith: one deployable, libraries contained ------------------

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
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect c4-plantuml >"$MOUT/render.out"
mono_text="$(cat "$MOUT/containers.json" "$MOUT/containers.md" "$MOUT/containers.puml" "$MOUT/collect.out" "$MOUT/render.out")"
assert_contains "host is one deployable" "$mono_text" '"kind":"deployable"'
deployables="$(grep -c '"kind":"deployable"' "$MOUT/containers.json" || true)"
assert_equals "monolith is one deployable" "$deployables" "1"
assert_contains "billing is a contained module" "$mono_text" '"path":"src/Billing/Billing.csproj"'
assert_contains "domain is contained transitively" "$mono_text" '"path":"src/Domain/Domain.csproj"'
assert_not_contains "source secret is not cited" "$mono_text" "SOURCE_ONLY_SECRET"
assert_not_contains "host builder usage is not a deployable" "$mono_text" "WebApplication"
assert_contains "diagram names contained modules" "$mono_text" "Contains: Billing, Domain"
container_elems="$(grep -c 'Container(' "$MOUT/containers.puml" || true)"
assert_equals "diagram draws one container" "$container_elems" "1"
assert_contains "summary counts modules" "$(cat "$MOUT/render.out")" "modules=2"

# --- shared broker cites both config keys; credentials stay out -------------

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
cat >"$BUS/src/Api/appsettings.json" <<'EOF'
{
  "Messaging": { "Broker": "sb://orders.servicebus.windows.net/" },
  "ConnectionStrings": {
    "Orders": "Server=tcp:orders.database.windows.net,1433;User ID=sa;Password=super-secret-password;AccountKey=abcDEF123secretkey;"
  },
  "Auth": { "ApiKey": "sk-live-abc123secret" }
}
EOF
cat >"$BUS/src/Worker/appsettings.json" <<'EOF'
{
  "Messaging": { "Broker": "sb://orders.servicebus.windows.net/" },
  "Endpoint": "https://user:url-password-zzz@db.example/path"
}
EOF
commit_repo "$BUS"
cat >"$BUS/src/Api/appsettings.Local.json" <<'EOF'
{ "Messaging": { "Broker": "sb://UNTRACKED_SECRET_VALUE.servicebus.windows.net/" } }
EOF
BOUT="$TEST_TMPDIR/bus-out"
mkdir -p "$BOUT"
bash "$COLLECT" --repo "$BUS" --out "$BOUT/containers.json" --generated-on 2026-09-28 >"$BOUT/collect.out" 2>"$BOUT/collect.err"
bash "$RENDER" --record "$BOUT/containers.json" --out "$BOUT" --dialect likec4 >"$BOUT/render.out" 2>"$BOUT/render.err"
bus_text="$(cat "$BOUT/containers.json" "$BOUT/containers.md" "$BOUT/containers.likec4" "$BOUT/collect.out" "$BOUT/collect.err" "$BOUT/render.out" "$BOUT/render.err")"
assert_contains "shared-infrastructure edge exists" "$bus_text" '"kind":"shared-infrastructure"'
assert_contains "edge cites the api config" "$bus_text" "src/Api/appsettings.json: Broker"
assert_contains "edge cites the worker config" "$bus_text" "src/Worker/appsettings.json: Broker"
assert_not_contains "password is redacted" "$bus_text" "super-secret-password"
assert_not_contains "account key is redacted" "$bus_text" "abcDEF123secretkey"
assert_not_contains "api token is redacted" "$bus_text" "sk-live-abc123secret"
assert_not_contains "url password is redacted" "$bus_text" "url-password-zzz"
assert_not_contains "untracked secret is not cited" "$bus_text" "UNTRACKED_SECRET_VALUE"
assert_contains "database host remains citable" "$bus_text" "orders.database.windows.net"
missing_tech="$(awk '/\{"id":/ && $0 !~ /"technology":/ { c++ } END { print c+0 }' "$BOUT/containers.json")"
assert_equals "every node has a technology field" "$missing_tech" "0"
unknown_tech="$(grep -c '"technology":"unknown"' "$BOUT/containers.json" || true)"
if [[ "$unknown_tech" -ge 1 ]]; then
  pass "a node with no runtime is the literal unknown"
else
  fail "a node with no runtime is the literal unknown" "count=$unknown_tech text=$(cat "$BOUT/containers.json")"
fi

# --- a reformatted record writes nothing ------------------------------------

cat >"$TEST_TMPDIR/bad-record.json" <<'EOF'
{
  "schema_version": 1,
  "subject": "x",
  "generated_on": "2026-09-28",
  "dependencies": "absent",
  "node_threshold": 24,
  "system_filter": "",
  "nodes": [
    {
      "id": "a",
      "name": "a",
      "kind": "deployable",
      "output_kind": "web",
      "technology": "unknown",
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
set -e
assert_equals "renderer rejects a reformatted record" "$rend_rc" "1"
if [[ -f "$TEST_TMPDIR/bad-render/containers.md" ]]; then
  fail "renderer writes nothing on a bad record" "containers.md exists"
else
  pass "renderer writes nothing on a bad record"
fi

set +e
bash "$RENDER" --record "$MOUT/containers.json" --out "$MOUT" --dialect mermaid >"$MOUT/mermaid.out" 2>"$MOUT/mermaid.err"
mermaid_rc=$?
set -e
assert_equals "mermaid is refused" "$mermaid_rc" "2"
assert_contains "mermaid refusal names the key" "$(cat "$MOUT/mermaid.err")" "diagram_dialect.system"

printf 'cases=%s failed=%s\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
