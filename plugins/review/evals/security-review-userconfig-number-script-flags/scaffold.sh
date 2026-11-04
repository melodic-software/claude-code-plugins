#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# notes is an existing plugin whose PostToolUse hook runs hooks/wrap-check.sh.
# The branch adds a wrap_column number key that the summary skill's prose
# reads and that the hook script also reads through CLAUDE_PLUGIN_OPTION_WRAP_COLUMN,
# so the value reaches code and the key is not inert.
mkdir -p .claude-plugin plugins/notes/.claude-plugin plugins/notes/skills/summary plugins/notes/hooks

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
{
  "name": "notes",
  "version": "1.4.0",
  "description": "Summarize notes",
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/wrap-check.sh\"" }] }
    ]
  }
}
JSON

cat >plugins/notes/skills/summary/SKILL.md <<'MD'
---
description: "Summarize the notes in the current folder"
---

Read the notes in the current folder and print a summary, one bullet per note.
MD

cat >plugins/notes/hooks/wrap-check.sh <<'SH'
#!/usr/bin/env bash
# Warn when an edited notes file has a line longer than the wrap column.
set -euo pipefail
file=$(jq -r '.tool_input.file_path // empty')
[[ -n "$file" && -f "$file" ]] || exit 0
awk -v max=100 'length($0) > max { print FILENAME ":" NR ": longer than " max " columns" }' "$file" >&2
SH
chmod +x plugins/notes/hooks/wrap-check.sh

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
      "description": "The column /notes:summary wraps its bullets at and the edit hook checks.",
      "default": 100
    }
  },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/wrap-check.sh\"" }] }
    ]
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

cat >plugins/notes/hooks/wrap-check.sh <<'SH'
#!/usr/bin/env bash
# Warn when an edited notes file has a line longer than the wrap column.
set -euo pipefail
file=$(jq -r '.tool_input.file_path // empty')
[[ -n "$file" && -f "$file" ]] || exit 0
max=${CLAUDE_PLUGIN_OPTION_WRAP_COLUMN:-100}
awk -v max="$max" 'length($0) > max { print FILENAME ":" NR ": longer than " max " columns" }' "$file" >&2
SH

git add .
git commit -q -m "feat(notes): add a wrap column option"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
