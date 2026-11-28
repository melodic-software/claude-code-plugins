#!/usr/bin/env bash
# test-scope: plugins/code-metrics/skills/*/SKILL.md # check-code-metrics-skill-prose.py reads each skill it checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/python-probe.sh
. "$SCRIPT_DIR/lib/python-probe.sh"

PYTHON=""
python_probe::require_to PYTHON "$SCRIPT_DIR/check-code-metrics-skill-prose.py"
"$PYTHON" "$SCRIPT_DIR/test_check_code_metrics_skill_prose.py" -v
