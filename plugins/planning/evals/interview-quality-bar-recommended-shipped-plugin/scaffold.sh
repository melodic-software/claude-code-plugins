#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .claude-plugin .github/workflows plugins/notes-export/.claude-plugin plugins/notes-export/scripts

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-tools",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "notes-export", "source": "./plugins/notes-export", "description": "Export your notes to Markdown files" }
  ]
}
JSON

cat >plugins/notes-export/.claude-plugin/plugin.json <<'JSON'
{ "name": "notes-export", "version": "2.3.0", "description": "Export your notes to Markdown files" }
JSON

cat >README.md <<'MD'
# Acme tools

Public plugin marketplace. Users install a plugin with:

    /plugin marketplace add acme/acme-tools
    /plugin install notes-export@acme-tools

`notes-export` runs on each user's own machine and writes into their notes folder.
MD

cat >.github/workflows/release.yml <<'YAML'
name: release
on:
  push:
    branches: [main]
jobs:
  tag:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "tag each plugin version from plugin.json"
YAML

cat >plugins/notes-export/scripts/export.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
target="$1"
for note in "$HOME"/.notes/*.json; do
  name="$(basename "$note" .json)"
  printf '# %s\n' "$name" >"$target/$name.md"
done
SH
chmod +x plugins/notes-export/scripts/export.sh

git add .
git commit -q -m "feat(notes-export): export notes to Markdown"
