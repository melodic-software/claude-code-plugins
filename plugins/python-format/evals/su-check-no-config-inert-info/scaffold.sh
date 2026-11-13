#!/usr/bin/env bash
# A git repository with Python files and a pyproject.toml that has no [tool.ruff] section or
# subtable, and no ruff.toml or .ruff.toml, so no Ruff config governs it (setup SKILL.md check step 4).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf '[project]\nname = "demo"\nversion = "0.1.0"\n\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' >pyproject.toml
printf 'def main():\n    return 1\n' >src/app.py
git add .
git commit -q -m "chore: init"
