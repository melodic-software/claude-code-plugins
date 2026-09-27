#!/usr/bin/env bash
# Contract tests for save_point.py — delegates to the pytest suite under tests/.
#
# SKIPs (exit 0) when Python 3.10+ or pytest is unavailable, matching the
# repo test-runner convention for optional toolchains.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

source "../lib/python-probe.sh"

PY=""
python_probe::floor_interpreter_to PY

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.10+ not found"
  exit 0
fi

if ! "$PY" -c 'import pytest' 2>/dev/null; then
  echo "SKIP: pytest not installed for $PY"
  exit 0
fi

# No cache provider: a .pytest_cache/ beside the script would otherwise carry a
# README.md that the plugin-wide markdownlint glob picks up.
exec "$PY" -m pytest tests/test_save_point.py -q -p no:cacheprovider
