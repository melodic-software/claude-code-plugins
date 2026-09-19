#!/usr/bin/env bash
# Cross-platform contract wrapper for the contract-clause coverage gate's
# test suite. Same shape as scripts/check-manifest-duplicate-keys.test.sh:
# both gates are Python engines run from a bash-only CI step, and both resolve
# the interpreter through scripts/lib/python-probe.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the gate itself, and the probe
# below parses it there rather than restating the number here.
# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/check-contract-clause-coverage.py"

# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_check_contract_clause_coverage.py" -v
