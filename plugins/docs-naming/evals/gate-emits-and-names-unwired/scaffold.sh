#!/usr/bin/env bash
# Seeds a git repo with a docs-naming team config, a docs tree holding one
# offending name, and a CI workflow the gate is not yet wired into.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p docs/conventions .github/workflows
cat >docs/conventions/docs-naming.yaml <<'YAML'
# File-name convention for the docs tree.
roots:
  - "docs"
rule: "lower-kebab"
YAML
printf '# Harbor\n\nShipment tracking service.\n' >README.md
printf '# Getting started\n\nInstall and run the service.\n' >docs/getting-started.md
printf '# API reference\n\nEndpoints for shipments.\n' >docs/api-reference.md
printf '# Release notes\n\n## 1.4.0\n\nFaster label printing.\n' >docs/Release_Notes.md
cat >.github/workflows/ci.yml <<'YAML'
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make test
YAML

git add -A
git commit -q -m "chore: seed"
