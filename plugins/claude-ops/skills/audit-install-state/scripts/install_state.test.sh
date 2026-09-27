#!/usr/bin/env bash
# Cross-platform contract wrapper for the install-state engine test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/python-probe.sh
source "$SCRIPT_DIR/../../../lib/python-probe.sh"

ENGINE="$SCRIPT_DIR/install_state.py"
FLOOR=""
python_probe::floor_to FLOOR "$ENGINE"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

PYTHON=""
python_probe::interpreter_to PYTHON
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

FLOOR_MET=""
python_probe::floor_met_to FLOOR_MET "$PYTHON" "$FLOOR"
if [[ -z "$FLOOR_MET" ]]; then
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
fi

"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_install_state.py"
