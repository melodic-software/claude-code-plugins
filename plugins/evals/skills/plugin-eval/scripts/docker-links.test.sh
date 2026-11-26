#!/usr/bin/env bash
# test-scope: plugins/evals/skills/plugin-eval/scripts/docker-links.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/docker-links.py"
SUITE="$SCRIPT_DIR/test_docker_links.py"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
find_python "$ENGINE" "docker-links.py"

"$PYTHON" "$SUITE"
