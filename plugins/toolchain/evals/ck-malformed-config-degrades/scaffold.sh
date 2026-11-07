#!/usr/bin/env bash
# A .NET repository whose tracked .claude/ecosystems/dotnet.yaml is invalid YAML with no command
# keys; a .cs file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude src
mkdir -p .claude/ecosystems src/Cart
printf 'globs: ["*.cs", "*.csproj"\nbuild-cmd: : dotnet build\n  test-cmd [\n' >.claude/ecosystems/dotnet.yaml
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' >src/Cart/Cart.csproj
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => a + b; }\n' >src/Cart/Totals.cs
g add -A
g commit -q -m "cart"
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => checked(a + b); }\n' >src/Cart/Totals.cs
