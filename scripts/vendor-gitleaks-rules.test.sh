#!/usr/bin/env bash
# Contract wrapper for vendor_gitleaks_rules.py's pytest suite.
#
# SKIPs (exit 0) when no interpreter meets the script's MIN_PYTHON (3.11, for
# tomllib) or pytest is missing. -p no:cacheprovider keeps a .pytest_cache out
# of the tree.
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
