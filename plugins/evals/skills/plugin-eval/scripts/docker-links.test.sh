#!/usr/bin/env bash
# Cross-platform wrapper for docker-links.py's unittest suite, so the repo's
# run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The interpreter
# discovery follows plugins/evals/skills/validate/scripts/validate-cases.test.sh.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/skills/plugin-eval/scripts/docker-links.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/docker-links.py"
SUITE="$SCRIPT_DIR/test_docker_links.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "docker-links.py"

"$PYTHON" "$SUITE"
