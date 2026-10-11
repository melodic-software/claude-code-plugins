#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# pin-manifest suite.
# test-scope: plugins/knowledge/skills/docpage-digest/scripts/test_pin_manifest.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate-test-lib.sh
source "$SCRIPT_DIR/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR" test_pin_manifest.py
