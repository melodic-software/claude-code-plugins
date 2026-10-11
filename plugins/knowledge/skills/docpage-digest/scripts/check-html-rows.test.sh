#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# check-html-rows negative-control suite.
# test-scope: plugins/knowledge/skills/docpage-digest/scripts/fixtures/html-rows/*
# test-scope: plugins/knowledge/skills/docpage-digest/scripts/test_check_html_rows.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-test-lib.sh
source "$SCRIPT_DIR/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR" test_check_html_rows.py
