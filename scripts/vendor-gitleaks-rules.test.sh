#!/usr/bin/env bash
# test-scope: scripts/fixtures/vendor-gitleaks-rules/*
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/vendor_gitleaks_rules.py"

if ! "$PYTHON" -c 'import pytest' 2>/dev/null; then
  echo "SKIP: pytest not installed for $PYTHON"
  exit 0
fi

exec "$PYTHON" -m pytest "$SCRIPT_DIR/test_vendor_gitleaks_rules.py" -q -p no:cacheprovider
