#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# main serves the format plugin from the repository. The branch points the
# entry at an outside GitHub repository with no ref or sha; the entry sets no
# defaultEnabled, so it stays on for every user.
mkdir -p .claude-plugin plugins/format/.claude-plugin

cat >plugins/format/.claude-plugin/plugin.json <<'JSON'
{ "name": "format", "version": "2.0.1", "description": "Format on save" }
JSON

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "format", "source": "./plugins/format", "description": "Format on save" }
  ]
}
JSON

git add .
git commit -q -m "feat: marketplace"

git checkout -q -b chore/format-upstream
cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    {
      "name": "format",
      "source": { "source": "github", "repo": "fmt-tools/claude-format" },
      "description": "Format on save"
    }
  ]
}
JSON

git add .
git commit -q -m "chore(format): install from the upstream repository"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
