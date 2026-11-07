#!/usr/bin/env bash
# Tracked dotnet, python and powershell configs whose commands log to .calls.log. A .cs file and a
# pyproject-managed .py module changed; the .ps1 script did not.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src scripts pyproject.toml
eval_logger
eval_eco dotnet '["*.cs", "*.csproj"]' build test check
eval_eco python '["*.py", "pyproject.toml"]' build test check
eval_eco powershell '["*.ps1"]' build test check
mkdir -p src/Cart src/pricing scripts
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' >src/Cart/Cart.csproj
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => a + b; }\n' >src/Cart/Totals.cs
printf '[project]\nname = "pricing"\nversion = "0.1.0"\n' >pyproject.toml
printf 'def discount(total):\n    return total\n' >src/pricing/discount.py
printf 'Write-Output "deploy"\n' >scripts/deploy.ps1
g add -A
g commit -q -m "cart, pricing and deploy"
printf 'namespace Cart;\npublic static class Totals { public static int Sum(int a, int b) => checked(a + b); }\n' >src/Cart/Totals.cs
printf 'def discount(total):\n    return round(total * 0.9, 2)\n' >src/pricing/discount.py
