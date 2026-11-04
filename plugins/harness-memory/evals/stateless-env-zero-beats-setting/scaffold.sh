#!/usr/bin/env bash
# Seeds a repository whose project settings set the auto-memory env var to 0 while its local
# settings set autoMemoryEnabled to false. A run's user scope is unreadable, so everything
# the answer needs is here.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude
cat >.claude/settings.json <<'JSON'
{
  "env": {
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "0"
  }
}
JSON
printf '{\n  "autoMemoryEnabled": false\n}\n' >.claude/settings.local.json

printf '.claude/settings.local.json\n' >.gitignore
printf '# Parcel tracker\n\nShipment status service.\n' >README.md
git add .gitignore .claude/settings.json README.md
git commit -q -m "chore: initial layout"
