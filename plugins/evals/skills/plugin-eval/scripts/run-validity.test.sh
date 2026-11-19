#!/usr/bin/env bash
# Cross-platform wrapper for run-validity.py's unittest suite, so the repo's
# run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The interpreter
# discovery follows plugins/evals/skills/validate/scripts/validate-cases.test.sh.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/skills/plugin-eval/scripts/fixtures/run-validity/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/run-validity.py"
SUITE="$SCRIPT_DIR/test_run_validity.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "run-validity.py"

"$PYTHON" "$SUITE"
