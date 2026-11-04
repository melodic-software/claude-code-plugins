#!/usr/bin/env bash
# A git repository where the closest-config walk differs per file: src/ruff.toml governs
# src/pkg/mod.py past a pyproject.toml with no [tool.ruff] table, and the root pyproject.toml's
# [tool.ruff.lint] subtable governs scripts/run.py. A gitignored, executable .venv/bin/ruff stub is
# what the hook's venv walk resolves (setup SKILL.md check steps 3-4).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/pkg scripts .venv/bin
printf '[project]\nname = "demo"\nversion = "0.1.0"\n\n[tool.ruff.lint]\nselect = ["E", "F"]\n' >pyproject.toml
printf 'line-length = 100\n' >src/ruff.toml
printf '[project]\nname = "pkg"\nversion = "0.1.0"\n' >src/pkg/pyproject.toml
printf 'x = 1\n' >src/pkg/mod.py
printf 'print("run")\n' >scripts/run.py
printf '#!/bin/sh\necho "ruff 0.6.9"\n' >.venv/bin/ruff
chmod +x .venv/bin/ruff
printf '.venv/\n' >.gitignore
git add .
git commit -q -m "chore: init"
