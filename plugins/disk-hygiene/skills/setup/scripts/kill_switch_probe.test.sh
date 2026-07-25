#!/usr/bin/env bash
# Cross-platform contract wrapper for the kill-switch probe test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the clean engine. Parse it
# rather than restating the number here.
ENGINE="$SCRIPT_DIR/../../clean/scripts/hygiene.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

if command -v python >/dev/null 2>&1; then
  PYTHON=python
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(part) for part in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}
"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_kill_switch_probe.py"
