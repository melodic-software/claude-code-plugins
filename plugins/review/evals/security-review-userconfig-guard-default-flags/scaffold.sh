#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# notes is an existing plugin. The branch adds a max_files number key that
# only the summary skill's prose reads. The key caps how many files the skill
# reads, so it is a guard, and its default 0 means no limit: the permissive
# value. The guard bullet makes it a finding before the inert bullet applies.
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

Read at most 20 notes files in the current folder and print a summary, one bullet per note.
MD

git add .
git commit -q -m "feat: notes plugin"

git checkout -q -b feat/notes-max-files
cat >plugins/notes/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "1.4.0",
  "description": "Summarize notes",
  "userConfig": {
    "max_files": {
      "type": "number",
      "title": "Most files to read",
      "description": "The most notes files /notes:summary reads. 0 (default): no limit.",
      "default": 0
    }
  }
}
JSON

cat >plugins/notes/skills/summary/SKILL.md <<'MD'
---
description: "Summarize the notes in the current folder"
---

Read at most ${user_config.max_files} notes files in the current folder and print a summary, one
bullet per note. When ${user_config.max_files} is 0 there is no limit: read every file.
MD

git add .
git commit -q -m "feat(notes): make the file limit configurable"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
