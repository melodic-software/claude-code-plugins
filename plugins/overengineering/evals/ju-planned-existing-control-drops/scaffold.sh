#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-pkg-readme.md.txt README.md \
  oe-pkg-consuming.md.txt docs/consuming.md \
  oe-pkg-protection.md.txt docs/branch-protection.md \
  oe-pkg-ci.yml.txt .github/workflows/ci.yml
