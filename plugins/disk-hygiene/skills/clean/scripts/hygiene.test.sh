#!/usr/bin/env bash
# Cross-platform contract wrapper for the stdlib Python test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../scripts/test-wrapper-lib.sh
source "$SCRIPT_DIR/../../../scripts/test-wrapper-lib.sh"

FLOOR=""
test_wrapper::floor_to FLOOR "$SCRIPT_DIR/hygiene.py"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from hygiene.py" >&2
  exit 1
fi

PYTHON=""
test_wrapper::interpreter_to PYTHON
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

FLOOR_CHECK=""
test_wrapper::floor_check_to FLOOR_CHECK "$FLOOR"
"$PYTHON" -c "$FLOOR_CHECK" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}
"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_hygiene.py"
