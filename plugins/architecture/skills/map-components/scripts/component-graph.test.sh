#!/usr/bin/env bash
# Tests for component-graph.sh and the render of a graph it collected.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/component-graph.sh"
RENDER="$SCRIPT_DIR/render-components.sh"
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

write_proj() {
  local path="$1" body="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$body" >"$path"
}

# --- A layered deployable, plus a name trap and a second deployable --------
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
# Same file name as a project that exists, but the Include does not point here.
write_proj "$root/other/Nope/Nope.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
write_proj "$root/src/host/Billing.Worker/Billing.Worker.csproj" '<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\worker\Billing.Worker.Core\Billing.Worker.Core.csproj" />
  </ItemGroup>
</Project>'
write_proj "$root/src/worker/Billing.Worker.Core/Billing.Worker.Core.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
# Generated output must not become a node.
write_proj "$root/src/host/Billing.Api/obj/Debug/Billing.Api.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
printf '{}\n' >"$root/package.json"

graph="$TEST_TMPDIR/graph.json"
bash "$SCRIPT" --repo "$root" --out "$graph" --generated-on 2026-09-28
rc=$?
assert_equals "collect: exits 0" "$rc" "0"
record="$(cat "$graph")"
assert_contains "collect: schema_version 1" "$record" '"schema_version": 1'
assert_contains "collect: ecosystem dotnet" "$record" '"ecosystem": "dotnet"'
assert_contains "collect: generated_on is the flag, not the clock" "$record" '"generated_on": "2026-09-28"'
assert_contains "collect: node_threshold is recorded" "$record" '"node_threshold": 24'
assert_contains "collect: the Api to Application edge cites the declaration" "$record" \
  'application\\Billing.Application\\Billing.Application.csproj'
assert_contains "collect: that edge is kind project and points at the resolved project" "$record" \
  '"from":"src/host/Billing.Api/Billing.Api.csproj","to":"src/application/Billing.Application/Billing.Application.csproj","kind":"project"'
assert_contains "collect: a missing Include is unresolved" "$record" '"kind":"unresolved"'
assert_contains "collect: the unresolved to is the Include text" "$record" '"to":"..\\..\\missing\\Nope.csproj"'
assert_not_contains "collect: the missing Include is not matched to other/Nope by name" "$record" \
  '"to":"other/Nope/Nope.csproj"'
assert_contains "collect: the package node is nuget-qualified" "$record" '"id":"nuget:Newtonsoft.Json"'
assert_contains "collect: package.json is unshipped, not a fake node" "$record" '"unshipped": "package.json"'
assert_not_contains "collect: obj output is not a node" "$record" 'obj/Debug'

# One object per line: the renderer accepts this record.
mkdir -p "$TEST_TMPDIR/view"
bash "$RENDER" --graph "$graph" --out "$TEST_TMPDIR/view" --container Billing.Api \
  --group-by layer --layers host,application,domain --source component-graph.sh >"$TEST_TMPDIR/view.out"
assert_equals "render collected: exits 0" "$?" "0"
view="$(cat "$TEST_TMPDIR/view/components.md")"
summary="$(cat "$TEST_TMPDIR/view.out")"
assert_contains "render collected: summary names the container" "$summary" 'container="Billing.Api"'
assert_contains "render collected: three internal edges" "$summary" 'edges=3'
assert_contains "render collected: one violation" "$summary" 'violations=1'
assert_contains "render collected: the package is collapsed" "$summary" 'external_collapsed=1'
assert_contains "render collected: the missing reference is unresolved" "$summary" 'unresolved=1'
assert_contains "render collected: host boundary" "$view" 'Boundary(grp_0, "host", "layer")'
assert_contains "render collected: application boundary" "$view" 'Boundary(grp_1, "application", "layer")'
assert_contains "render collected: domain boundary" "$view" 'Boundary(grp_2, "domain", "layer")'
assert_contains "render collected: Domain to Application is the violation" "$view" \
  '| Billing.Domain | Billing.Application |'
assert_contains "render collected: the violation arrow is labeled" "$view" 'ProjectReference, layer violation'
assert_not_contains "render collected: Worker is outside this container" "$view" 'Billing.Worker'
assert_contains "render collected: outside modules are named as a count" "$view" 'Modules outside this container:'
assert_contains "render collected: violations do not fail the prose" "$view" 'does not fail'

# Directory and namespace grouping of the same graph.
mkdir -p "$TEST_TMPDIR/dir" "$TEST_TMPDIR/ns"
bash "$RENDER" --graph "$graph" --out "$TEST_TMPDIR/dir" --container Billing.Api --group-by directory >/dev/null
bash "$RENDER" --graph "$graph" --out "$TEST_TMPDIR/ns" --container Billing.Api --group-by namespace >/dev/null
assert_contains "group directory: a path boundary" "$(cat "$TEST_TMPDIR/dir/components.md")" \
  'Boundary(grp_0, "src/application/Billing.Application", "directory")'
assert_contains "group namespace: the project name is the namespace" "$(cat "$TEST_TMPDIR/ns/components.md")" \
  'Boundary(grp_0, "Billing.Api", "namespace")'

# Several deployables, no --container.
mkdir -p "$TEST_TMPDIR/choice"
choice="$(bash "$RENDER" --graph "$graph" --out "$TEST_TMPDIR/choice" 2>&1)" || choice_rc=$?
choice_rc="${choice_rc:-0}"
assert_equals "choice: several deployables exit 3" "$choice_rc" "3"
assert_contains "choice: the message names the flag" "$choice" 'pass --container'
assert_contains "choice: Api is a candidate" "$choice" 'Billing.Api'
assert_contains "choice: Worker is a candidate" "$choice" 'Billing.Worker'
if [[ -e "$TEST_TMPDIR/choice/components.md" ]]; then
  fail "choice: writes nothing" "components.md exists"
else
  pass "choice: writes nothing"
fi

# Unknown ecosystem.
unk="$TEST_TMPDIR/node-only"
mkdir -p "$unk"
printf '{ "name": "web" }\n' >"$unk/package.json"
bash "$SCRIPT" --repo "$unk" --out "$TEST_TMPDIR/unknown.json" --generated-on 2026-09-28
unkrec="$(cat "$TEST_TMPDIR/unknown.json")"
assert_contains "unknown: ecosystem unknown" "$unkrec" '"ecosystem": "unknown"'
assert_contains "unknown: the reason names the manifest" "$unkrec" 'package.json'
assert_contains "unknown: nodes are an empty array, not a fake graph" "$unkrec" '"nodes": []'
mkdir -p "$TEST_TMPDIR/unkout"
bash "$RENDER" --graph "$TEST_TMPDIR/unknown.json" --out "$TEST_TMPDIR/unkout" >"$TEST_TMPDIR/unkout.txt"
assert_equals "unknown render: exits 0" "$?" "0"
unkmd="$(cat "$TEST_TMPDIR/unkout/components.md")"
assert_contains "unknown render: says unknown" "$unkmd" 'ecosystem `unknown`'
assert_not_contains "unknown render: no diagram" "$unkmd" 'C4Component'
assert_contains "unknown render: summary is thin" "$(cat "$TEST_TMPDIR/unkout.txt")" 'thin=yes'

# A single project is thin, and not a one-box diagram.
solo="$TEST_TMPDIR/solo"
write_proj "$solo/Only.csproj" '<Project Sdk="Microsoft.NET.Sdk"></Project>'
bash "$SCRIPT" --repo "$solo" --out "$TEST_TMPDIR/solo.json" --generated-on 2026-09-28
mkdir -p "$TEST_TMPDIR/soloout"
bash "$RENDER" --graph "$TEST_TMPDIR/solo.json" --out "$TEST_TMPDIR/soloout" >"$TEST_TMPDIR/soloout.txt"
solomd="$(cat "$TEST_TMPDIR/soloout/components.md")"
assert_contains "thin: the summary says thin" "$(cat "$TEST_TMPDIR/soloout.txt")" 'thin=yes'
assert_contains "thin: names map-landscape" "$solomd" '/architecture:map-landscape'
assert_contains "thin: names map-containers" "$solomd" '/architecture:map-containers'
assert_contains "thin: names improve" "$solomd" '/architecture:improve'
assert_not_contains "thin: no one-box diagram" "$solomd" 'C4Component'
assert_contains "thin: says a one-box diagram is not the answer" "$solomd" 'one-box diagram is not the answer'

bad="$(bash "$SCRIPT" --repo "$TEST_TMPDIR/no-such-dir" 2>&1)"
assert_equals "usage: a missing repo exits 1" "$?" "1"
assert_contains "usage: and says so" "$bad" 'not a directory'

help_out="$(bash "$SCRIPT" --help 2>&1)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: documents unresolved" "$help_out" 'unresolved'

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
