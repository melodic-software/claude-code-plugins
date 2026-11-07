#!/usr/bin/env bash
# Billing.Api (src/host) references Billing.Application and Billing.Shared; Billing.Application
# references Billing.Domain, and Billing.Domain references Billing.Application back: an edge from
# the inner domain layer out to the application layer. The convention home declares
# component_layers host, application, domain and diagram_dialect.system c4-plantuml. Billing.Shared
# (src/shared) matches no declared layer.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh" --dialect c4-plantuml --layers "host, application, domain"
mkdir -p src/host/Billing.Api src/application/Billing.Application src/domain/Billing.Domain src/shared/Billing.Shared

cat >src/host/Billing.Api/Billing.Api.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../application/Billing.Application/Billing.Application.csproj" />
    <ProjectReference Include="../../shared/Billing.Shared/Billing.Shared.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/application/Billing.Application/Billing.Application.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../domain/Billing.Domain/Billing.Domain.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/domain/Billing.Domain/Billing.Domain.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../../application/Billing.Application/Billing.Application.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/shared/Billing.Shared/Billing.Shared.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

git add -A
git commit -q -m "Billing host, application, domain and shared projects"
mkdir -p docs/architecture
