#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/adc-seed.sh" \
  adc-util-report.sh.txt bin/report.sh \
  adc-util-lib.sh.txt lib/util.sh \
  adc-util-readme.md.txt README.md
