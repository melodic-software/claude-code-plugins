#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-readme.md.txt README.md \
  oe-pre-commit.txt .githooks/pre-commit \
  oe-stale.yml.txt .github/workflows/stale.yml \
  oe-work-gitignore.txt .work/.gitignore \
  oe-findings-walk.md.txt .work/overengineering/main/findings.md
