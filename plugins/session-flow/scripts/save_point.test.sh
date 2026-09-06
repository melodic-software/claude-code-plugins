#!/usr/bin/env bash
# Contract tests for save_point.py — delegates to the pytest suite under tests/.
#
# SKIPs (exit 0) when Python 3.10+ or pytest is unavailable, matching the
# repo test-runner convention for optional toolchains (the retro skill's
# parse-transcript.test.sh is the precedent this mirrors).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$candidate"
    break
  fi
done

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
