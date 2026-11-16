#!/usr/bin/env bash
# A git repository with a ruff.toml (the Ruff adapter's opt-in) and a committed python record whose
# fix-cmd and lint-cmd run the repository's own scripts. The default branch (origin/HEAD) holds the
# same record and scripts, so the record is accepted and wins over the adapter for both concerns.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src tools .claude/ecosystems
printf 'line-length = 88\n' >ruff.toml
printf 'def main():\n    return 1\n' >src/app.py
printf '#!/bin/sh\nexit 0\n' >tools/fmt.sh
printf '#!/bin/sh\nexit 0\n' >tools/lint.sh
chmod +x tools/fmt.sh tools/lint.sh
cat >.claude/ecosystems/python.yaml <<'EOF'
globs: ["*.py", "*.pyi"]
build-cmd: null
test-cmd: null
check-cmd: null
fix-cmd: "$REPO_ROOT/tools/fmt.sh <files>"
lint-cmd: "$REPO_ROOT/tools/lint.sh <files>"
EOF
git add .
git commit -q -m "chore: init"
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
