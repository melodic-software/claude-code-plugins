#!/usr/bin/env bash
# A uv-managed git repository where every check step passes or is INFO: a [tool.ruff] section governs
# it, ruff is already a recorded dev dependency, a gitignored executable .venv/bin/ruff stub is what
# the hook resolves, and this clone has declined the git pre-commit entry, so verify reports
# declined (INFO) rather than missing (setup SKILL.md check step 8).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.python-format.ruff-check.declined true
mkdir -p src/demo .venv/bin
cat >pyproject.toml <<'EOF'
[project]
name = "demo"
version = "0.1.0"
requires-python = ">=3.10"

[dependency-groups]
dev = ["ruff>=0.6"]

[tool.ruff]
line-length = 100
EOF
cat >uv.lock <<'EOF'
version = 1
requires-python = ">=3.10"

[[package]]
name = "ruff"
version = "0.6.9"
source = { registry = "https://pypi.org/simple" }
EOF
printf 'def main():\n    return 1\n' >src/demo/__init__.py
printf '#!/bin/sh\necho "ruff 0.6.9"\n' >.venv/bin/ruff
chmod +x .venv/bin/ruff
printf '.venv/\n' >.gitignore
git add .
git commit -q -m "chore: init"
