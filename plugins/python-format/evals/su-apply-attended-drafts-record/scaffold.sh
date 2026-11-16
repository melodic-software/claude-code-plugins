#!/usr/bin/env bash
# A git repository whose own config shows its formatter and linter (a [tool.black] section and a
# .flake8 file), with no python record and no Ruff config. apply drafts the fix-cmd and lint-cmd
# for /toolchain:setup and writes no record itself.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf '[project]\nname = "demo"\nversion = "0.1.0"\n\n[tool.black]\nline-length = 100\n' >pyproject.toml
printf '[flake8]\nmax-line-length = 100\n' >.flake8
printf 'def main():\n    return 1\n' >src/app.py
git add .
git commit -q -m "chore: init"
