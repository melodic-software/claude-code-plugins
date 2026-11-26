#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/python-probe.sh
source "$SCRIPT_DIR/../../../lib/python-probe.sh"
ENGINE="$SCRIPT_DIR/native_drift.py"
SUITE="$SCRIPT_DIR/test_native_drift.py"

FLOOR=""
python_probe::floor_to FLOOR "$ENGINE"
if [[ -z "$FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 2
fi

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
  echo "error: Python ${FLOOR}+ not found (tried python3, python) -- native_drift.py's suite cannot run" >&2
  exit 2
fi

"$PYTHON" "$SUITE"
