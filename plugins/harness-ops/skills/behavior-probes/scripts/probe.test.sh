#!/usr/bin/env bash
# Cross-platform wrapper for probe.py's unittest suite, so the repo's
# `run-plugin-tests.sh` discovery (plugins/**/*.test.sh) runs it. Nothing in the
# suite starts `claude`: every run is --dry-run or a stub runner.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/python-probe.sh
source "$SCRIPT_DIR/../../../lib/python-probe.sh"
ENGINE="$SCRIPT_DIR/probe.py"
SUITE="$SCRIPT_DIR/test_probe.py"

FLOOR=""
python_probe::floor_to FLOOR "$ENGINE"
if [[ -z "$FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 2
fi

# A zero-length candidate under a WindowsApps path component is the Store's App
# Execution Alias stub, which opens the Store instead of running Python.
PYTHON=""
FLOOR_MET=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  python_probe::floor_met_to FLOOR_MET "$candidate" "$FLOOR" 2>/dev/null
  if [[ -n "$FLOOR_MET" ]]; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "error: Python ${FLOOR}+ not found (tried python3, python) -- probe.py's suite cannot run" >&2
  exit 2
fi

"$PYTHON" "$SUITE"
