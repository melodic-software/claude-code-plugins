#!/usr/bin/env bash
# Unit tests for sync-spawn-noise.sh. The cases, the fixture builders and the
# wordings live in scripts/lib/sync-cluster-suite.sh, shared with the sibling
# sync-<cluster>.test.sh suites; this file is the cluster's constants and the
# entry point the plugin and CI gates resolve by filename.
#
# The threshold is the whole point of this cluster: claude-ops and performance
# disagreeing about what counts as an unmeasurable host is the failure the gate
# prevents, so the --check arms carry that consequence into their wording.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/sync-cluster-suite.sh
. "$SELF_DIR/lib/sync-cluster-suite.sh"

sync_cluster_suite::run \
  --script "$SELF_DIR/sync-spawn-noise.sh" \
  --canonical 'plugins/claude-ops/lib/spawn_noise.py' \
  --copy 'plugins/performance/lib/spawn_noise.py' \
  --v1 'BIMODAL_SPREAD_RATIO = 3.0\nSLOW_SPAWN_FLOOR_MS = 500.0\n' \
  --v2 'BIMODAL_SPREAD_RATIO = 3.0\nSLOW_SPAWN_FLOOR_MS = 500.0\n\ndef is_measurable(s):\n    return True\n' \
  --drift 'BIMODAL_SPREAD_RATIO = 9.0\n' \
  --check-agree-note ' — it would report clean whether or not the threshold agrees'

test_harness::report
