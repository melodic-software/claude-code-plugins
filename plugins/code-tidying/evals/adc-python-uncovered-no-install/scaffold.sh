#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-py-main.py.txt app/main.py \
  adc-py-pricing.py.txt app/pricing.py \
  adc-py-deploy.sh.txt deploy.sh \
  adc-py-readme.md.txt README.md
