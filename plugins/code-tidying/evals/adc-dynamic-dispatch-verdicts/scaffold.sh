#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-dispatch-cli.sh.txt cli.sh \
  adc-dispatch-handlers.sh.txt lib/handlers.sh \
  adc-dispatch-readme.md.txt README.md
