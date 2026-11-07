#!/usr/bin/env bash
# One web project with no project references. The convention home declares architecture_dir
# docs/architecture and diagram_dialect.system c4-plantuml.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh" --dialect c4-plantuml
mkdir -p src/Ledger.Api

cat >src/Ledger.Api/Ledger.Api.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

cat >src/Ledger.Api/Program.cs <<'CS'
var app = WebApplication.CreateBuilder(args).Build();
app.MapGet("/balance", () => 0);
app.Run();
CS

git add -A
git commit -q -m "Ledger API"
mkdir -p docs/architecture
