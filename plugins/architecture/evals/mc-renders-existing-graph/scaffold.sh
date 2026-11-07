#!/usr/bin/env bash
# Billing.Api references Billing.Application, which references Billing.Domain. The convention home
# declares architecture_dir docs/architecture and diagram_dialect.system c4-plantuml, declares no
# component_layers, and docs/architecture/dependency-graph.json already holds the collected graph.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh" --dialect c4-plantuml
mkdir -p src/Billing.Api src/Billing.Application src/Billing.Domain docs/architecture

cat >src/Billing.Api/Billing.Api.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../Billing.Application/Billing.Application.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/Billing.Application/Billing.Application.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../Billing.Domain/Billing.Domain.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/Billing.Domain/Billing.Domain.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

cat >docs/architecture/dependency-graph.json <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-11-07",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "cycles_truncated": false,
  "nodes": [
    {"id":"src/Billing.Api/Billing.Api.csproj","name":"Billing.Api","path":"src/Billing.Api/Billing.Api.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/Billing.Application/Billing.Application.csproj","name":"Billing.Application","path":"src/Billing.Application/Billing.Application.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/Billing.Domain/Billing.Domain.csproj","name":"Billing.Domain","path":"src/Billing.Domain/Billing.Domain.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/Billing.Api/Billing.Api.csproj","to":"src/Billing.Application/Billing.Application.csproj","kind":"project","status":"resolved","evidence":"src/Billing.Api/Billing.Api.csproj: <ProjectReference Include=\"../Billing.Application/Billing.Application.csproj\" />"},
    {"from":"src/Billing.Application/Billing.Application.csproj","to":"src/Billing.Domain/Billing.Domain.csproj","kind":"project","status":"resolved","evidence":"src/Billing.Application/Billing.Application.csproj: <ProjectReference Include=\"../Billing.Domain/Billing.Domain.csproj\" />"}
  ],
  "cycles": [],
  "findings": []
}
JSON

git add -A
# Commit on the date the graph records, so the renderer reports no stale graph.
GIT_AUTHOR_DATE=2026-11-07T12:00:00Z GIT_COMMITTER_DATE=2026-11-07T12:00:00Z \
  git commit -q -m "Billing API, application and domain with the collected dependency graph"
