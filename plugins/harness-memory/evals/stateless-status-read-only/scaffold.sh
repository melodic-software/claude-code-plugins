#!/usr/bin/env bash
# Seeds a repository whose project settings name auto memory explicitly, so the
# status action has a setting to report.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude
cat >.claude/settings.json <<'JSON'
{
  "autoMemoryEnabled": true
}
JSON
printf '# Tide tables\n\nTide prediction service.\n' >README.md

git add -A
git commit -q -m "chore: initial commit"
