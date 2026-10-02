#!/usr/bin/env bash
# Unit tests for sync-html-escape.sh. The cases, the fixture builders and the
# wordings live in scripts/lib/sync-cluster-suite.sh, shared with the sibling
# sync-<cluster>.test.sh suites; this file is the cluster's constants and the
# entry point the plugin and CI gates resolve by filename.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/sync-cluster-suite.sh
. "$SELF_DIR/lib/sync-cluster-suite.sh"

sync_cluster_suite::run \
  --script "$SELF_DIR/sync-html-escape.sh" \
  --canonical 'lib/html-escape.mjs' \
  --copy 'plugins/review/lib/html-escape.mjs' \
  --extra-copy 'plugins/event-storming/lib/html-escape.mjs' \
  --extra-copy 'plugins/harness-ops/lib/html-escape.mjs' \
  --extra-copy 'plugins/knowledge/lib/html-escape.mjs' \
  --v1 'export const escapeHtml = (s) => String(s);\n' \
  --v2 'export const escapeHtml = (s) => String(s ?? "");\n' \
  --drift '// drifted\n' \
  --unknown-flag-arm \
  --unchanged-bump-arm

test_harness::report
