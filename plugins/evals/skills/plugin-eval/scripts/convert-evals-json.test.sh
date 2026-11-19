# shellcheck shell=bash
# Cross-platform wrapper for convert-evals-json.py's unittest suite, so the
# repo's run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The
# interpreter discovery follows validate-cases.test.sh beside the validator.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/skills/validate/scripts/validate-cases.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/convert-evals-json.py"
SUITE="$SCRIPT_DIR/test_convert_evals_json.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "convert-evals-json.py"

"$PYTHON" "$SUITE"
