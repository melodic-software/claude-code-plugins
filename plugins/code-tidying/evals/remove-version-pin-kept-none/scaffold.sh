#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/comment-tooling-seed.sh"
git init -q
mkdir -p .github/workflows
printf '%s\n' \
  'name: ci' \
  'on: [push]' \
  'jobs:' \
  '  test:' \
  '    runs-on: ubuntu-latest' \
  '    steps:' \
  '      # check out the code' \
  '      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567 # v4.2.2' \
  '      - uses: actions/setup-node@89abcdef0123456789abcdef0123456789abcdef # 2026-01-10' \
  '        with:' \
  '          node-version: 20' \
  '      - run: npm test' >.github/workflows/ci.yml
git add .github/workflows/ci.yml
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
