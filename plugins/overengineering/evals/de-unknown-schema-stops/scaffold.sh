#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-readme.md.txt README.md \
  oe-pre-commit.txt .githooks/pre-commit \
  oe-work-gitignore.txt .work/.gitignore \
  oe-findings-schema9.md.txt .work/overengineering/main/findings.md
