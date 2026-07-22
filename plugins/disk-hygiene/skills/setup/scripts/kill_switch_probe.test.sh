#!/usr/bin/env bash
# Cross-platform contract wrapper for the kill-switch probe test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v python >/dev/null 2>&1; then
  PYTHON=python
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  echo "SKIP: Python 3.11+ not found" >&2
  exit 0
fi

"$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || {
  echo "SKIP: Python 3.11+ required" >&2
  exit 0
}
"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_kill_switch_probe.py"
