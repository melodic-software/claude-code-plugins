#!/usr/bin/env bash
# Contract tests for parse_transcript.py — delegates to the pytest suite.
#
# SKIPs (exit 0) when Python 3.10+ or pytest is unavailable, matching the
# repo test-runner convention for optional toolchains.
# test-scope: plugins/session-flow/skills/retro/scripts/parse_transcript.py
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

source "../../../lib/python-probe.sh"

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

exec "$PY" -m pytest test_parse_transcript.py -q
