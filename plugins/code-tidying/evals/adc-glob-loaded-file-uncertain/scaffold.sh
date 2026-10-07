#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-glob-run.sh.txt run.sh \
  adc-glob-greet.sh.txt plugins/greet.sh \
  adc-glob-migrate.sh.txt tools/old-migrate.sh \
  adc-glob-readme.md.txt README.md
