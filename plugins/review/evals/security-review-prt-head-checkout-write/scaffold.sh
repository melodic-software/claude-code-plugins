#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# main tests pull requests under pull_request with a read token. The branch
# moves to pull_request_target, checks out the head and keeps a write token.
mkdir -p .github/workflows

cat >.github/workflows/test.yml <<'YAML'
name: test
on:
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      - run: npm ci && npm test
YAML

git add .
git commit -q -m "feat: test pull requests"

git checkout -q -b ci/label-fork-prs
cat >.github/workflows/test.yml <<'YAML'
name: test
on:
  pull_request_target:
permissions:
  contents: write
  pull-requests: write
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - run: npm ci && npm test
      - run: gh pr edit "$PR" --add-label tested
        env:
          GH_TOKEN: ${{ github.token }}
          PR: ${{ github.event.pull_request.number }}
YAML

git add .
git commit -q -m "ci(test): label fork pull requests once they pass"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
