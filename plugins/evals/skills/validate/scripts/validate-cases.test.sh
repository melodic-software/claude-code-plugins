#!/usr/bin/env bash
# Cross-platform wrapper for validate-cases.py's unittest suite, so the repo's
# run-plugin-tests.sh discovery (plugins/**/*.test.sh) actually runs it. The
# engine is Python and the runner step is bash-only, which is what this file
# bridges; the interpreter discovery below follows the repo's candidate loop
# (the overlap.test.sh wrapper of /harness-ops:audit-native-overlap).
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/evals/* plugins/evals/scripts/case_skills.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/validate-cases.py"
SUITE="$SCRIPT_DIR/test_validate_cases.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "validate-cases.py"

# Execute the suite file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SUITE"
