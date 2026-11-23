#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src docs ARCHITECTURE.md AGENTS.md
# shellcheck source=../fixtures/git-history.sh
. "${here}/../fixtures/git-history.sh"

repo_init
bash "${here}/../fixtures/convention-home.sh"
{
  printf '# Architecture\n\n'
  for i in $(seq 3 13); do printf 'Line %s of the overview.\n' "${i}"; done
  printf 'Billing.Reports must not reference Billing.Ledger directly.\n'
} >ARCHITECTURE.md
mkdir -p src/Billing.Ledger src/Billing.Reports
cat >src/Billing.Ledger/Billing.Ledger.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML
cat >src/Billing.Reports/Billing.Reports.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\Billing.Ledger\Billing.Ledger.csproj" />
  </ItemGroup>
</Project>
XML
git add -A
git commit -q -m "feat(billing): ledger and reports"
git checkout -q -b feature/billing-split
mkdir -p docs/architecture
bash "${here}/../../skills/map-dependencies/scripts/dependency-graph.sh" \
  --out docs/architecture/dependency-graph.json .
git add -A
git commit -q -m "docs(architecture): dependency graph"
