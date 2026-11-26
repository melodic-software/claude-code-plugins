#!/usr/bin/env bash
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter.
# test-scope: plugins/*/evals/*/case.yaml plugins/*/evals/*/matchers.json
# test-scope: plugins/*/evals/*/samples/* plugins/evals/matchers/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/validate-cases.py"
SUITE="$SCRIPT_DIR/test_check_matchers.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "check-matchers.py"
if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found -- check-matchers.py grades every sample under JavaScript too" >&2
  exit 2
fi

"$PYTHON" "$SUITE"
