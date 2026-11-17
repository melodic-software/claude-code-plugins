#!/usr/bin/env bash
# A git repository with Markdown files, no markdown record and no markdownlint config, so both
# concerns resolve to nothing: the plugin is inert by design.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p docs
printf '# Demo\n' >README.md
printf '# Guide\n\nSome text.\n' >docs/guide.md
git add .
git commit -q -m "chore: init"
