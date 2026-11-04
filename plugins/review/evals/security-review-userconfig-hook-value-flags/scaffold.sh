#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# fmt is an existing plugin with a PostToolUse hook. The branch adds a
# formatter userConfig key with fixed options and substitutes its value into
# the hook's command, so the value names the program the hook runs.
mkdir -p .claude-plugin plugins/fmt/.claude-plugin

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "fmt", "source": "./plugins/fmt", "description": "Format edited files" }
  ]
}
JSON

cat >plugins/fmt/.claude-plugin/plugin.json <<'JSON'
{
  "name": "fmt",
  "version": "0.3.0",
  "description": "Format edited files",
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "npx prettier --write ." }] }
    ]
  }
}
JSON

git add .
git commit -q -m "feat: fmt plugin"

git checkout -q -b feat/fmt-choice
cat >plugins/fmt/.claude-plugin/plugin.json <<'JSON'
{
  "name": "fmt",
  "version": "0.3.0",
  "description": "Format edited files",
  "userConfig": {
    "formatter": {
      "type": "string",
      "title": "Formatter",
      "description": "Which formatter the hook runs after an edit.",
      "default": "prettier",
      "options": ["prettier", "biome"]
    }
  },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "npx ${user_config.formatter} --write ." }] }
    ]
  }
}
JSON

git add .
git commit -q -m "feat(fmt): let the user pick the formatter"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
