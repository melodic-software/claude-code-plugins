#!/usr/bin/env bash
# Seeds a repository whose project settings relocate the auto-memory store into the working
# tree, outside the config root, and hold two notes there. A run's user scope and default store
# are unreadable, so the store and the auto-memory state the purge resolves are both set here.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude notes/assistant-memory
cat >.claude/settings.json <<JSON
{
  "autoMemoryEnabled": false,
  "autoMemoryDirectory": "$PWD/notes/assistant-memory"
}
JSON

cat >notes/assistant-memory/MEMORY.md <<'MD'
# Saved notes

- [Build notes](build-notes.md): what the nightly build needs before it starts.
MD
printf '# Build notes\n\nThe nightly build needs the container registry login first.\n' >notes/assistant-memory/build-notes.md

printf 'notes/\n' >.gitignore
printf '# Parcel tracker\n\nShipment status service.\n' >README.md
git add .gitignore .claude/settings.json README.md
git commit -q -m "chore: initial layout"
