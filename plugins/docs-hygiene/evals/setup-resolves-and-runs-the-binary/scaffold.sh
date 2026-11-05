#!/usr/bin/env bash
# A git repository with a real markdownlint-cli2 0.24.0 (the version the marketplace's package.json pins) in node_modules/.bin and no markdownlint configuration.
set -euo pipefail

git init -q
printf 'node_modules/\n' >.gitignore
printf '# Harbor\n\nInventory service.\n' >README.md
cat >package.json <<'JSON'
{
  "name": "harbor",
  "private": true,
  "devDependencies": {
    "markdownlint-cli2": "0.24.0"
  }
}
JSON
npm install --include=dev --no-package-lock --no-audit --no-fund --ignore-scripts --loglevel=error >/dev/null
[[ -x node_modules/.bin/markdownlint-cli2 ]]
