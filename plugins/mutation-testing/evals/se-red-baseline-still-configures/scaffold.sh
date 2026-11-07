#!/usr/bin/env bash
# A Python repo with no config whose branch commits a failing test.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
sed -i 's/shipping_fee(1), 4/shipping_fee(1), 5/' tests/test_calc.py
git commit -q -am "test: expect a 5 fee"
