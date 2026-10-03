#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# extract_blog_body fixture suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-test-lib.sh
source "$SCRIPT_DIR/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR" test_extract_blog_body.py
