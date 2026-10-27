#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# main lists two in-repo plugins. The branch adds a third entry, a bundle
# whose plugin.json depends on the other two, and sets "defaultEnabled": false
# on the entry, so it installs nothing until a user enables it.
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
mkdir -p plugins/bundle/.claude-plugin
cat >plugins/bundle/.claude-plugin/plugin.json <<'JSON'
{
  "name": "bundle",
  "version": "0.1.0",
  "description": "Installs lint and format together",
  "dependencies": ["lint", "format"]
}
JSON

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
      "description": "Installs lint and format together",
      "defaultEnabled": false
    }
  ]
}
JSON

git add .
git commit -q -m "feat(bundle): add a bundle plugin"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
