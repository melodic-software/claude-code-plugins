#!/usr/bin/env bash
# Seeds a .NET repo (one library, one xUnit test project) whose feature branch commits a change to
# src/Shop/Discount.cs. Usage: seed-dotnet.sh <unconfigured|stryker>. stryker writes
# docs/conventions/mutation-testing.yaml naming tool: stryker-net on main.
set -euo pipefail
mode="${1:?usage: seed-dotnet.sh <unconfigured|stryker>}"
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/Shop tests/Shop.Tests
printf 'bin/\nobj/\n.work/\n' >.gitignore
cat >src/Shop/Shop.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
XML
cat >src/Shop/Discount.cs <<'CS'
namespace Shop;

public static class Discount
{
    public static int Apply(int price, int percent)
    {
        if (percent <= 0)
        {
            return price;
        }
        return price - price * percent / 100;
    }
}
CS
cat >tests/Shop.Tests/Shop.Tests.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../src/Shop/Shop.csproj" />
  </ItemGroup>
</Project>
XML
cat >tests/Shop.Tests/DiscountTests.cs <<'CS'
using Shop;
using Xunit;

public class DiscountTests
{
    [Fact]
    public void AppliesPercent() => Assert.Equal(90, Discount.Apply(100, 10));

    [Fact]
    public void IgnoresZeroPercent() => Assert.Equal(100, Discount.Apply(100, 0));
}
CS
if [[ "${mode}" == stryker ]]; then
  mkdir -p docs/conventions
  cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: stryker-net
diff-target: main
mutate:
  - 'src/**/*.cs'
test-command: 'dotnet test tests/Shop.Tests/Shop.Tests.csproj'
YAML
fi
git add -A
git commit -q -m "feat: add discount"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b feature/cap-discount
sed -i 's/return price - price \* percent \/ 100;/return price - price * System.Math.Min(percent, 50) \/ 100;/' src/Shop/Discount.cs
git commit -q -am "feat: cap the discount at 50 percent"
