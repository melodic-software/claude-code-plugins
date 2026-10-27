#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# main lists two in-repo plugins. The branch adds a bundle entry with no
# defaultEnabled line; its plugin.json adds a SessionStart hook.
mkdir -p .claude-plugin plugins/lint/.claude-plugin plugins/format/.claude-plugin

cat >plugins/lint/.claude-plugin/plugin.json <<'JSON'
{ "name": "lint", "version": "1.2.0", "description": "Lint on save" }
JSON
cat >plugins/format/.claude-plugin/plugin.json <<'JSON'
{ "name": "format", "version": "2.0.1", "description": "Format on save" }
JSON

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "lint", "source": "./plugins/lint", "description": "Lint on save" },
    { "name": "format", "source": "./plugins/format", "description": "Format on save" }
  ]
}
JSON

git add .
git commit -q -m "feat: marketplace"

git checkout -q -b feat/bundle
mkdir -p plugins/bundle/.claude-plugin plugins/bundle/hooks
echo '{ "lint": true, "format": true }' >plugins/bundle/defaults.json
cat >plugins/bundle/.claude-plugin/plugin.json <<'JSON'
{
  "name": "bundle",
  "version": "0.1.0",
  "description": "Installs lint and format together",
  "dependencies": ["lint", "format"],
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/setup.sh" }] }
    ]
  }
}
JSON
cat >plugins/bundle/hooks/setup.sh <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/.cache/bundle" && cp "${CLAUDE_PLUGIN_ROOT}/defaults.json" "$HOME/.cache/bundle/"
SH

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "lint", "source": "./plugins/lint", "description": "Lint on save" },
    { "name": "format", "source": "./plugins/format", "description": "Format on save" },
    {
      "name": "bundle",
      "source": "./plugins/bundle",
      "description": "Installs lint and format together"
    }
  ]
}
JSON

git add .
git commit -q -m "feat(bundle): add a bundle plugin"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
