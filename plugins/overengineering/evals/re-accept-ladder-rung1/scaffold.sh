#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-readme.md.txt README.md \
  oe-stale.yml.txt .github/workflows/stale.yml \
  --commit "Add stale workflow" \
  oe-work-gitignore.txt .work/.gitignore \
  oe-findings-retire.md.txt .work/overengineering/main/findings.md
