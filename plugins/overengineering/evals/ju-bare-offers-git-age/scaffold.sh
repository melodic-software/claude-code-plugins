#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-readme.md.txt README.md \
  --commit "add readme" \
  oe-setup.md.txt docs/setup.md \
  oe-build.sh.txt scripts/build.sh \
  --commit "add setup and build" \
  oe-changelog.md.txt CHANGELOG.md
