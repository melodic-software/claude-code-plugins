#!/usr/bin/env bash
# Seeds a git repo with a docs-naming team config and a conforming docs tree.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p docs/conventions
cat >docs/conventions/docs-naming.yaml <<'YAML'
# File-name convention for the docs tree.
roots:
  - "docs"
rule: "lower-kebab"
YAML
printf '# Harbor\n\nShipment tracking service.\n' >README.md
printf '# Getting started\n\nInstall and run the service.\n' >docs/getting-started.md
printf '# API reference\n\nEndpoints for shipments.\n' >docs/api-reference.md

git add -A
git commit -q -m "chore: seed"
