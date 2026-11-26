#!/usr/bin/env bash
# test-scope: plugins/evals/evals/* plugins/evals/scripts/case_skills.py plugins/evals/skills/*/SKILL.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/validate-cases.py"
SUITE="$SCRIPT_DIR/test_validate_cases.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "validate-cases.py"

"$PYTHON" "$SUITE"
