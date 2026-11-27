#!/usr/bin/env bash
set -euo pipefail

git init -q
mkdir -p docs/conventions
printf 'compress_articles: cut\n' >docs/conventions/docs-hygiene.yaml
printf '# Harbor\n\nInventory service.\n' >README.md
cat >package.json <<'JSON'
{
  "name": "harbor",
  "private": true,
  "scripts": {
    "lint:md": "markdownlint-cli2 \"**/*.md\""
  },
  "devDependencies": {
    "markdownlint-cli2": "0.24.0"
  }
}
JSON
