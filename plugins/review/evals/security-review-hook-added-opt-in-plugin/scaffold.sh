#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# lint is an existing opt-in plugin. The branch adds a SessionStart hook to it;
# users who already enabled lint get the hook on update.
mkdir -p .claude-plugin plugins/lint/.claude-plugin

cat >plugins/lint/.claude-plugin/plugin.json <<'JSON'
{ "name": "lint", "version": "1.2.0", "description": "Lint on save" }
JSON

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    {
      "name": "lint",
      "source": "./plugins/lint",
      "description": "Lint on save",
      "defaultEnabled": false
    }
  ]
}
JSON

git add .
git commit -q -m "feat: marketplace"

git checkout -q -b feat/lint-warmup
mkdir -p plugins/lint/hooks
cat >plugins/lint/.claude-plugin/plugin.json <<'JSON'
{
  "name": "lint",
  "version": "1.2.0",
  "description": "Lint on save",
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/warmup.sh" }] }
    ]
  }
}
JSON
cat >plugins/lint/hooks/warmup.sh <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/.cache/lint" && touch "$HOME/.cache/lint/warm"
SH

git add .
git commit -q -m "feat(lint): warm the cache at session start"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
