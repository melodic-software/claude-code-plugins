#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the verify-batch-page suite.
# test-scope: plugins/knowledge/tests/test_verify_batch_page.py plugins/knowledge/skills/docpage-digest/scripts/*
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../skills/docpage-digest/scripts/gate-test-lib.sh
source "$SCRIPT_DIR/../skills/docpage-digest/scripts/gate-test-lib.sh"

# run_suite resolves the MIN_PYTHON floor from the scripts directory, so it runs the suite by a
# path relative to that directory.
gate_test::run_suite "$SCRIPT_DIR/../skills/docpage-digest/scripts" ../../../tests/test_verify_batch_page.py
