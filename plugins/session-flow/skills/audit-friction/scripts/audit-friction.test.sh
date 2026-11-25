#!/usr/bin/env bash
# test-scope: plugins/session-flow/skills/audit-friction/scripts/tests/fixtures/*
# test-scope: plugins/session-flow/scripts/collect.py plugins/session-flow/scripts/census.py plugins/session-flow/scripts/friction_scan.py plugins/session-flow/scripts/redact.py plugins/session-flow/scripts/transcript_reader.py
# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/lib/state-key.sh plugins/session-flow/skills/audit-friction/scripts/*
# test-scope: plugins/session-flow/vendor/gitleaks/gitleaks-rules.json plugins/session-flow/reference/canaries.json
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

exec "$PY" -m pytest tests -q -p no:cacheprovider
