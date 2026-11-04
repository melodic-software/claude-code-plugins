#!/usr/bin/env bash
# Seeds a repository whose project settings set the auto-memory env var to 0 while its local
# settings set autoMemoryEnabled to false, with the store relocated into the working tree.
# A run's user scope and default store are unreadable, so everything the answer needs is here.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude notes/assistant-memory
cat >.claude/settings.json <<JSON
{
  "autoMemoryDirectory": "$PWD/notes/assistant-memory",
  "env": {
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "0"
  }
}
JSON
printf '{\n  "autoMemoryEnabled": false\n}\n' >.claude/settings.local.json

cat >notes/assistant-memory/MEMORY.md <<'MD'
# Saved notes

- [Release steps](release-steps.md): the order the service's releases go out in.
MD
printf '# Release steps\n\nTag first, then publish the container image.\n' >notes/assistant-memory/release-steps.md

printf '.claude/settings.local.json\nnotes/\n' >.gitignore
printf '# Parcel tracker\n\nShipment status service.\n' >README.md
git add .gitignore .claude/settings.json README.md
git commit -q -m "chore: initial layout"
