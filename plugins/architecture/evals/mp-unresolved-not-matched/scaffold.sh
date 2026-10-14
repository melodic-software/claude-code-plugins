#!/usr/bin/env bash
# Api references Domain (present) and ../Shared/Shared.csproj (missing). A project named
# Shared does exist, but under legacy/, so a name match would be a wrong edge.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/Api src/Domain legacy/Shared

cat >src/Api/Api.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../Domain/Domain.csproj" />
    <ProjectReference Include="../Shared/Shared.csproj" />
    <PackageReference Include="Serilog" Version="3.1.1" />
  </ItemGroup>
</Project>
XML

cat >src/Domain/Domain.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

cat >legacy/Shared/Shared.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML

git add -A
git commit -q -m "Api, Domain and a legacy Shared library"
mkdir -p docs/architecture
