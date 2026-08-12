#!/usr/bin/env bash
# CI wrapper: run-plugin-tests.sh only discovers *.test.sh.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SELF_DIR/check-usage-limit-reset.test.py"
