#!/usr/bin/env bash
# Cross-platform contract wrapper for the python3 alias-stub probe test suite.
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

# A zero-length candidate under a WindowsApps path component is the Store's App
# Execution Alias stub — the very artifact this suite tests for. Executing it
# opens the Microsoft Store (or hangs) instead of running an interpreter, so
# each candidate is inspected before anything executes it.
PYTHON=""
for candidate in python python3; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  PYTHON="$candidate"
  break
done
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(part) for part in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}
"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_python3_alias_probe.py"
