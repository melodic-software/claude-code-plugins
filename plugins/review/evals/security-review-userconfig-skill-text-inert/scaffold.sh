#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# notes is an existing plugin. The branch adds a wrap_column number key that
# only the summary skill's prose reads; no hook, server, script or code file
# reads it, so it is inert.
mkdir -p .claude-plugin plugins/notes/.claude-plugin plugins/notes/skills/summary

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "notes", "source": "./plugins/notes", "description": "Summarize notes" }
  ]
}
JSON

cat >plugins/notes/.claude-plugin/plugin.json <<'JSON'
{ "name": "notes", "version": "1.4.0", "description": "Summarize notes" }
JSON

cat >plugins/notes/skills/summary/SKILL.md <<'MD'
---
description: "Summarize the notes in the current folder"
---

Read the notes in the current folder and print a summary, one bullet per note.
MD

git add .
git commit -q -m "feat: notes plugin"

git checkout -q -b feat/notes-wrap
cat >plugins/notes/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "1.4.0",
  "description": "Summarize notes",
  "userConfig": {
    "wrap_column": {
      "type": "number",
      "title": "Wrap column",
      "description": "The column /notes:summary wraps its bullets at.",
      "default": 100
    }
  }
}
JSON

cat >plugins/notes/skills/summary/SKILL.md <<'MD'
---
description: "Summarize the notes in the current folder"
---

Read the notes in the current folder and print a summary, one bullet per note.
Wrap each bullet at column ${user_config.wrap_column}.
MD

git add .
git commit -q -m "feat(notes): add a wrap column option"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
