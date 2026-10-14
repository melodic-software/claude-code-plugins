#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" feat/ci-cleanup \
  oe-readme.md.txt README.md \
  oe-lint.yml.txt .github/workflows/lint.yml \
  oe-pre-commit.txt .githooks/pre-commit
