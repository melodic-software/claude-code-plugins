#!/usr/bin/env bash
# Contract tests for the audit-sessions scripts — delegates to the pytest suite.
#
# SKIPs (exit 0) when Python 3.10+ or pytest is unavailable, matching the
# repo test-runner convention for optional toolchains. -p no:cacheprovider keeps
# a .pytest_cache/README.md out of the plugin-wide markdownlint glob.
# test-scope: plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/*
# test-scope: plugins/session-flow/skills/audit-sessions/scripts/*.py plugins/session-flow/skills/audit-sessions/reference/*.json plugins/session-flow/skills/audit-sessions/vendor/gitleaks/gitleaks-rules.json
# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/lib/state-key.sh plugins/session-flow/scripts/transcript_reader.py plugins/session-flow/skills/retro/scripts/parse_transcript.py
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
