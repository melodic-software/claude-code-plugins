#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-ts-package.json.txt package.json \
  adc-ts-index.ts.txt src/index.ts \
  adc-ts-math.ts.txt src/math.ts
