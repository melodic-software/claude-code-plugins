#!/usr/bin/env bash
# test-scope: plugins/session-flow/skills/running-retro/scripts/arm_observer.py
# test-scope: plugins/session-flow/hooks/observer-catchup.sh
# test-scope: plugins/session-flow/.claude-plugin/plugin.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python 3.10+ not found" >&2
  exit 0
fi

"$PYTHON" -m unittest -v "$SCRIPT_DIR/test_observer.py"
