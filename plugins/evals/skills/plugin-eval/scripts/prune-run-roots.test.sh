#!/usr/bin/env bash
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter.
# test-scope: plugins/evals/skills/plugin-eval/scripts/prune-run-roots.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/prune-run-roots.py"
SUITE="$SCRIPT_DIR/test_prune_run_roots.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "prune-run-roots.py"

"$PYTHON" "$SUITE"
