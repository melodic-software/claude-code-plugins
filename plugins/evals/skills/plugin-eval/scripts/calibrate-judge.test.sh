#!/usr/bin/env bash
# Cross-platform wrapper for calibrate-judge.py's unittest suite, so the repo's
# run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The interpreter
# discovery follows plugins/evals/skills/validate/scripts/validate-cases.test.sh.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/evals/* plugins/evals/skills/plugin-eval/scripts/fixtures/calibrate-judge/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/calibrate-judge.py"
SUITE="$SCRIPT_DIR/test_calibrate_judge.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "calibrate-judge.py"

"$PYTHON" "$SUITE"
