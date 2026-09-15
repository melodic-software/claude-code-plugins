#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# check-snippets negative-control suite. The Python floor is parsed from
# digest_fences.py rather than restated here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-test-lib.sh
source "$SCRIPT_DIR/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR" test_check_snippets.py
