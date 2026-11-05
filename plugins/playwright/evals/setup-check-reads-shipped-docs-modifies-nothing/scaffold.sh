#!/usr/bin/env bash
# A git repository whose .gitignore does not cover .playwright-cli/, so check has an artifact-directory note to make.
set -euo pipefail
git init -q -b main
git config core.excludesFile /dev/null
printf 'node_modules/\n' >.gitignore
printf '# demo\n' >README.md
