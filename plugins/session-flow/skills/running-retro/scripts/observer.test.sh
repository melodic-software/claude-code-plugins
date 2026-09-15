#!/usr/bin/env bash
# Cross-platform contract wrapper for the stdlib Python test suite covering
# observer.py and its detached launcher, arm_observer.py.
#
# Without this wrapper, scripts/run-plugin-tests.sh (which discovers only
# plugins/**/*.test.sh) never runs test_observer.py, so its assertions --
# including the ArmLauncher regression coverage for arm_observer.py's spawn
# call -- never gate CI. SKIPs (exit 0) when Python 3.10+ is unavailable,
# matching the floor this skill's other launchers (observer-arm.sh, SKILL.md)
# already enforce.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python 3.10+ not found" >&2
  exit 0
fi

"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_observer.py"
