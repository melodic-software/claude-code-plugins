#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-notify-spec.md.txt docs/requirements.md \
  oe-notify-orders.py.txt src/orders.py
