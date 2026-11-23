#!/usr/bin/env bash
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/skills/plugin-eval/scripts/select_mapping.py plugins/evals/scripts/case_skills.py plugins/evals/skills/validate/scripts/validate-cases.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/select-cases.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "select-cases.py"

rc=0
"$PYTHON" "$SCRIPT_DIR/test_select_cases.py" || rc=$?
"$PYTHON" "$SCRIPT_DIR/test_select_cases_mapping.py" || rc=$?
exit "$rc"
