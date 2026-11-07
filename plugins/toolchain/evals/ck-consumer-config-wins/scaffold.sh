#!/usr/bin/env bash
# A .NET repository whose tracked .claude/ecosystems/dotnet.yaml declares its own build, test and
# lint commands (they log to .calls.log); a .cs file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src Cart.sln
eval_logger
eval_eco dotnet '["*.cs", "*.csproj", "*.sln"]' build test check
mkdir -p src/Cart
printf 'Microsoft Visual Studio Solution File, Format Version 12.00\n' >Cart.sln
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' >src/Cart/Cart.csproj
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => a + b; }\n' >src/Cart/Totals.cs
g add -A
g commit -q -m "cart"
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => checked(a + b); }\n' >src/Cart/Totals.cs
