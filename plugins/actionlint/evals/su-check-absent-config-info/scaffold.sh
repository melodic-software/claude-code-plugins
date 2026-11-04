#!/usr/bin/env bash
# A git repository with one committed workflow, no actionlint config and no pre-commit entry, so
# install.mjs verify reports the entry missing (setup SKILL.md check step 7).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p .github/workflows
printf 'name: ci\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n' >.github/workflows/ci.yml
git add .
git commit -q -m "chore: init"
