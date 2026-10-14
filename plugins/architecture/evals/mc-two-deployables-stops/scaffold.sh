#!/usr/bin/env bash
# Two deployables (a web API and a worker) share one domain library, so no single
# container covers every project and the component view must ask which one to chart.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/OrdersApi src/OrdersWorker src/OrdersDomain

cat >src/OrdersApi/OrdersApi.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../OrdersDomain/OrdersDomain.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/OrdersWorker/OrdersWorker.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../OrdersDomain/OrdersDomain.csproj" />
  </ItemGroup>
</Project>
XML

cat >src/OrdersDomain/OrdersDomain.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

git add -A
git commit -q -m "Orders API, worker and domain"
mkdir -p docs/architecture
