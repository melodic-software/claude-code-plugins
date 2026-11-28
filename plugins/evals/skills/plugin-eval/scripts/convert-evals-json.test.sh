# shellcheck shell=bash
# test-scope: plugins/evals/skills/validate/scripts/validate-cases.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/convert-evals-json.py"
SUITE="$SCRIPT_DIR/test_convert_evals_json.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "convert-evals-json.py"

"$PYTHON" "$SUITE"
