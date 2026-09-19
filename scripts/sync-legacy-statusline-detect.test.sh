#!/usr/bin/env bash
# Unit tests for sync-legacy-statusline-detect.sh. The cases, the fixture
# builders and the wordings live in scripts/lib/sync-cluster-suite.sh, shared
# with the sibling sync-<cluster>.test.sh suites; this file is the cluster's
# constants and the entry point the plugin and CI gates resolve by filename.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/sync-cluster-suite.sh
. "$SELF_DIR/lib/sync-cluster-suite.sh"

sync_cluster_suite::run \
  --script "$SELF_DIR/sync-legacy-statusline-detect.sh" \
  --canonical 'plugins/context-guard/skills/setup/reference/legacy-statusline-detect.md' \
  --copy 'plugins/rate-limit-guard/skills/setup/reference/legacy-statusline-detect.md' \
  --v1 '# Legacy statusline detect\n\nshared spoke v1\n' \
  --v2 '# Legacy statusline detect\n\nshared spoke v2\n' \
  --drift '# drifted\n'

test_harness::report
