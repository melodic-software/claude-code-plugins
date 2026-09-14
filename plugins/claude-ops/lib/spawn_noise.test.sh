#!/usr/bin/env bash
# Cross-platform contract wrapper for the spawn-noise lib test suite.
#
# The lib is imported by the audit-performance engine and (from #3530) by the
# performance plugin, so its tests live beside the canonical copy rather than
# inside either consumer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./python-probe.sh
source "$SCRIPT_DIR/python-probe.sh"

# The floor's one origin is MIN_PYTHON in the engine that consumes this lib.
ENGINE="$SCRIPT_DIR/../skills/audit-performance/scripts/audit_performance.py"
FLOOR=""
python_probe::floor_to FLOOR "$ENGINE"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

PYTHON=""
python_probe::interpreter_to PYTHON
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

FLOOR_MET=""
python_probe::floor_met_to FLOOR_MET "$PYTHON" "$FLOOR"
if [[ -z "$FLOOR_MET" ]]; then
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
fi

(cd "$SCRIPT_DIR" && "$PYTHON" -m unittest -v test_spawn_noise)

echo "OK: spawn-noise lib contract"
