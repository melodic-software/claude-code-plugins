#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-readme.md.txt README.md \
  oe-setup.md.txt docs/setup.md \
  oe-changelog.md.txt docs/changelog.md
