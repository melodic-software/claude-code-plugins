#!/usr/bin/env bash
# test-scope: plugins/evals/scripts/case_skills.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/case_skills.py"
SUITE="$SCRIPT_DIR/test_case_skills.py"

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"
find_python "$ENGINE" "case_skills.py"

"$PYTHON" "$SUITE"
