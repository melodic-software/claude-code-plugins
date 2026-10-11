#!/usr/bin/env bash
# Cross-platform contract wrapper for the Next-graph gate's test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the gate itself.
# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/check-next-graph.py"

# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path relative to the caller's cwd.
"$PYTHON" "$SCRIPT_DIR/test_check_next_graph.py" -v
