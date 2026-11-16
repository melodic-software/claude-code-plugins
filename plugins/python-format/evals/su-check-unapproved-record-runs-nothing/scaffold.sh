#!/usr/bin/env bash
# A git repository whose default branch (origin/HEAD) has a ruff.toml and no python record; the
# current branch then commits a python record. The record differs from the default branch and
# has no approval for this clone, so it is unapproved and the hooks run nothing for its concerns,
# not even the Ruff adapter.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src .claude/ecosystems
printf 'line-length = 88\n' >ruff.toml
printf 'def main():\n    return 1\n' >src/app.py
git add .
git commit -q -m "chore: init"
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b feat/record
cat >.claude/ecosystems/python.yaml <<'EOF'
globs: ["*.py", "*.pyi"]
build-cmd: null
test-cmd: null
check-cmd: null
fix-cmd: "ruff format --line-length 120 <files>"
lint-cmd: "ruff check --output-format concise <files>"
EOF
git add .claude/ecosystems/python.yaml
git commit -q -m "feat: add python record"
