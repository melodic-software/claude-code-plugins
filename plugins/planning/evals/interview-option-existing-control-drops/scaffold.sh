#!/usr/bin/env bash
# A shared-settings repository whose main branch is already protected and gated by a pull request
# end-to-end job. The user proposes a stable branch, a workflow, a ruleset and a bot app on top.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs .github/workflows

cat >README.md <<'MD'
# style-kit

Shared formatter and lint settings. Consuming repositories install it straight from `main`.
MD

cat >docs/branch-protection.md <<'MD'
# Branch protection

`main` is protected by a repository rule:

- Direct pushes are blocked; every change lands through a pull request.
- One approving review is required.
- The `ci / consumer-e2e` status check must pass before merge.
- Force pushes and deletion are blocked.
MD

cat >.github/workflows/ci.yml <<'YML'
name: ci

on:
  pull_request:

jobs:
  consumer-e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install style-kit into the sample consumer
        run: ./scripts/install.sh --target examples/consumer
      - name: Run the consumer's lint with the installed settings
        run: make -C examples/consumer lint
YML

git add -A
git commit -q -m "add fixtures"
