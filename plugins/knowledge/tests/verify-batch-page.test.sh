#!/usr/bin/env bash
# test-scope: plugins/knowledge/tests/test_verify_batch_page.py plugins/knowledge/skills/docpage-digest/scripts/*
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../skills/docpage-digest/scripts/gate-test-lib.sh
source "$SCRIPT_DIR/../skills/docpage-digest/scripts/gate-test-lib.sh"

gate_test::run_suite "$SCRIPT_DIR/../skills/docpage-digest/scripts" ../../../tests/test_verify_batch_page.py
