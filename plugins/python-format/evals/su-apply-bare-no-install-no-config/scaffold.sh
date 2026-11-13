#!/usr/bin/env bash
# A git repository with a Python file and nothing else: no Ruff config, no pyproject.toml, no
# dependency manager and no .venv, so a bare apply has no managed environment to install into
# (setup SKILL.md apply lines 136-141).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf 'def main():\n    return 1\n' >app.py
git add .
git commit -q -m "chore: init"
