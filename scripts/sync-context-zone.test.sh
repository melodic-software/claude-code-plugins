#!/usr/bin/env bash
# Unit tests for sync-context-zone.sh. The cases, the fixture builders and the
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
  --script "$SELF_DIR/sync-context-zone.sh" \
  --canonical 'plugins/context-guard/scripts/context-zone.sh' \
  --copy 'plugins/plugin-quality/scripts/context-zone.sh' \
  --v1 '#!/usr/bin/env bash\n# smart <= 50 < acceptable <= 75 < dumb\n' \
  --v2 '#!/usr/bin/env bash\n# smart <= 40 < acceptable <= 70 < dumb\n' \
  --drift '# drifted\n' \
  --unknown-flag-arm \
  --unchanged-bump-arm

test_harness::report
