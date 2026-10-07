#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-quiet-build.sh.txt scripts/build.sh \
  adc-quiet-ci.yml.txt .github/workflows/ci.yml \
  adc-quiet-planted.sh.txt evals/fixtures/planted-dead.sh
