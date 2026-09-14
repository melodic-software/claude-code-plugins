#!/usr/bin/env bash
# Cross-platform contract wrapper for the manifest duplicate-key detector's
# test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the detector itself (needed
# because `from __future__ import annotations` requires 3.7+), and the probe
# below parses it there rather than restating the number here.
# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/check-manifest-duplicate-keys.py"

# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_check_manifest_duplicate_keys.py" -v
