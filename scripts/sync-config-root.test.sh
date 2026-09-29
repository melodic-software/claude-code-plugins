#!/usr/bin/env bash
# Unit tests for sync-config-root.sh. The cases, the fixture builders and the
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
  --script "$SELF_DIR/sync-config-root.sh" \
  --canonical 'plugins/source-control/lib/config-root.sh' \
  --copy 'plugins/docs-hygiene/lib/config-root.sh' \
  --v1 'config_root_classify() { echo repo; }\n' \
  --v2 'config_root_classify() { echo repo; }\nconfig_root_resolve() { echo /r; }\n' \
  --drift 'config_root_classify() { echo home; }\n' \
  --check-agree-note ' — it would report clean whether or not the copies agree'

test_harness::report
