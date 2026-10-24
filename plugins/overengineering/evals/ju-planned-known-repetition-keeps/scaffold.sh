#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/oe-seed.sh" main \
  oe-notify-requirements.md.txt docs/requirements.md \
  oe-notify-orders.py.txt src/orders.py
