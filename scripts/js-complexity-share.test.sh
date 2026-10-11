#!/usr/bin/env bash
# Cross-platform contract wrapper for the js-complexity-share counter's test
# suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/js-complexity-share.py"

"$PYTHON" "$SCRIPT_DIR/test_js_complexity_share.py" -v
