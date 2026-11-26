#!/usr/bin/env bash
# test-scope: plugins/evals/evals/* plugins/evals/skills/plugin-eval/scripts/fixtures/calibrate-judge/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/calibrate-judge.py"
SUITE="$SCRIPT_DIR/test_calibrate_judge.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "calibrate-judge.py"

"$PYTHON" "$SUITE"
