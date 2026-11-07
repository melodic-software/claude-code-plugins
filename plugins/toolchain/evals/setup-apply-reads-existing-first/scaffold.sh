#!/usr/bin/env bash
# A .NET and Python repository that already has tracked .claude/ecosystems/dotnet.yaml and
# python.yaml from an earlier setup run, each with a project-specific test-cmd.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude src tools Cart.sln pyproject.toml
mkdir -p .claude/ecosystems src/Cart tools/pricing
cat >.claude/ecosystems/dotnet.yaml <<'EOF'
# Ecosystem commands: https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/ecosystem-commands/README.md
globs: ["*.cs", "*.csproj", "*.sln"]
anchor: "Cart.sln"
build-cmd: 'dotnet build "Cart.sln"'
test-cmd: 'dotnet test "Cart.sln" --no-build --filter "Category!=Slow"'
check-cmd: 'dotnet format "Cart.sln" --verify-no-changes'
fix-cmd: 'dotnet format whitespace "Cart.sln"'
code-fix-cmd: null
install-hint: "https://dotnet.microsoft.com/download"
EOF
cat >.claude/ecosystems/python.yaml <<'EOF'
# Ecosystem commands: https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/ecosystem-commands/README.md
globs: ["*.py", "pyproject.toml"]
project-discovery: ["pyproject.toml"]
build-cmd: null
test-cmd: "python3 -m pytest -q -m 'not integration'"
check-cmd: "ruff check <files>"
fix-cmd: "ruff format <files>"
code-fix-cmd: null
install-hint: "pip install ruff pytest"
EOF
printf 'Microsoft Visual Studio Solution File, Format Version 12.00\n' >Cart.sln
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' >src/Cart/Cart.csproj
printf '[project]\nname = "pricing"\nversion = "0.1.0"\n' >pyproject.toml
printf 'def discount(total):\n    return total\n' >tools/pricing/discount.py
g add -A
g commit -q -m "cart and pricing with ecosystem configs"
