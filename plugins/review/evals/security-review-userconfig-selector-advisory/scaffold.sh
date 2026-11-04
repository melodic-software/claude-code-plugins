#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# notes is an existing plugin. The branch adds a layout userConfig key whose
# options only pick how the summary skill prints; the skill passes it as one
# quoted argument to lib/layout.mjs, which rejects any other value.
mkdir -p .claude-plugin plugins/notes/.claude-plugin plugins/notes/skills/summary plugins/notes/lib

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

Run `node "${CLAUDE_PLUGIN_ROOT}/lib/layout.mjs"` and print the notes summary in the layout it names.
MD

cat >plugins/notes/lib/layout.mjs <<'JS'
const LAYOUTS = ["compact", "wide"];
const arg = process.argv[process.argv.indexOf("--layout") + 1];
console.log(LAYOUTS.includes(arg) ? arg : "compact");
JS

git add .
git commit -q -m "feat: notes plugin"

git checkout -q -b feat/notes-layout
cat >plugins/notes/.claude-plugin/plugin.json <<'JSON'
{
  "name": "notes",
  "version": "1.4.0",
  "description": "Summarize notes",
  "userConfig": {
    "layout": {
      "type": "string",
      "title": "Summary layout",
      "description": "How /notes:summary prints. auto (default): compact; compact: one line per note; wide: a table.",
      "default": "auto",
      "options": ["auto", "compact", "wide"]
    }
  }
}
JSON

cat >plugins/notes/skills/summary/SKILL.md <<'MD'
---
description: "Summarize the notes in the current folder"
---

Run `node "${CLAUDE_PLUGIN_ROOT}/lib/layout.mjs" --layout "${user_config.layout}"` and print the notes summary in the layout it names.
MD

cat >plugins/notes/lib/layout.mjs <<'JS'
// auto and any value outside the list give the compact layout.
const LAYOUTS = ["compact", "wide"];
const arg = process.argv[process.argv.indexOf("--layout") + 1];
console.log(LAYOUTS.includes(arg) ? arg : "compact");
JS

git add .
git commit -q -m "feat(notes): add a summary layout option"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
