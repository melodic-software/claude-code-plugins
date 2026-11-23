#!/usr/bin/env bash
# test-scope: plugins/evals/scripts/case_skills.py plugins/evals/skills/validate/scripts/validate-cases.py plugins/evals/evals/* plugins/evals/.claude-plugin/plugin.json
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/audit-suite.py"
SUITE="$SCRIPT_DIR/test_audit_suite.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "audit-suite.py"

"$PYTHON" "$SUITE"
