#!/usr/bin/env bash
# Cross-platform wrapper for win-test.py's unittest suite, so the repo's
# run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The interpreter
# discovery follows plugins/evals/skills/validate/scripts/validate-cases.test.sh.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/win-test.py"
SUITE="$SCRIPT_DIR/test_win_test.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "win-test.py"

"$PYTHON" "$SUITE"
