#!/usr/bin/env bash
# test-scope: plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/*
# test-scope: plugins/session-flow/skills/audit-sessions/scripts/*.py plugins/session-flow/skills/audit-sessions/reference/*.json plugins/session-flow/vendor/gitleaks/gitleaks-rules.json
# test-scope: plugins/session-flow/scripts/collect.py plugins/session-flow/scripts/census.py plugins/session-flow/scripts/dispatches.py plugins/session-flow/scripts/friction_scan.py plugins/session-flow/scripts/redact.py plugins/session-flow/reference/canaries.json
# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/lib/state-key.sh plugins/session-flow/scripts/transcript_reader.py plugins/session-flow/scripts/parse_transcript.py
# test-scope: lib/redact.py lib/transcript_reader.py lib/friction_scan.py lib/claude_projects.py plugins/session-flow/scripts/claude_projects.py
# test-scope: lib/session_record.py lib/transcript_limits.py lib/transcript_run.py lib/transcript_sources.py lib/transcript_values.py plugins/session-flow/scripts/session_record.py plugins/session-flow/scripts/transcript_limits.py plugins/session-flow/scripts/transcript_run.py plugins/session-flow/scripts/transcript_sources.py plugins/session-flow/scripts/transcript_values.py
# test-scope: plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/publish.py plugins/session-flow/skills/audit-friction/scripts/friction.py
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

workers=()
if "$PY" -c 'import xdist' 2>/dev/null; then
  workers=(-n 2)
fi

exec "$PY" -m pytest tests -q -p no:cacheprovider ${workers[@]+"${workers[@]}"}
