#!/usr/bin/env bash
# test-scope: plugins/evals/skills/plugin-eval/scripts/fixtures/run-validity/* plugins/evals/scripts/redact.py plugins/evals/vendor/gitleaks/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/run-validity.py"
SUITE="$SCRIPT_DIR/test_run_validity.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "run-validity.py"

"$PYTHON" "$SUITE"
