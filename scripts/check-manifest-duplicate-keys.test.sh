#!/usr/bin/env bash
# Cross-platform contract wrapper for the manifest duplicate-key detector's
# test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor lives in the detector's MIN_PYTHON; the probe parses it there.
# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/check-manifest-duplicate-keys.py"

# Run the file directly: `-m unittest <abs path>` resolves it as a module name
# relative to the cwd and breaks outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_check_manifest_duplicate_keys.py" -v
