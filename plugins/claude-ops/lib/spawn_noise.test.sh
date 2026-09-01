#!/usr/bin/env bash
# Cross-platform contract wrapper for the spawn-noise lib test suite.
#
# The lib is imported by the audit-performance engine and (from #3530) by the
# performance plugin, so its tests live beside the canonical copy rather than
# inside either consumer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the engine that consumes this
# lib. Parse it rather than restating the number here.
ENGINE="$SCRIPT_DIR/../skills/audit-performance/scripts/audit_performance.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" -c "import sys; floor = tuple(int(p) for p in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" || {
  echo "SKIP: Python ${FLOOR}+ required" >&2
  exit 0
}

(cd "$SCRIPT_DIR" && "$PYTHON" -m unittest -v test_spawn_noise)

echo "OK: spawn-noise lib contract"
