#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# check-fences-exact negative-control suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-test-lib.sh
source "$SCRIPT_DIR/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR" test_check_fences_exact.py
