#!/usr/bin/env bash
# Cross-platform wrapper so plugin-gate (plugins/**/*.test.sh) runs the
# check-snippets negative-control suite. The Python floor is parsed from
# digest_fences.py rather than restated here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/digest_fences.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

PYTHON=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi

"$PYTHON" "$SCRIPT_DIR/test_check_snippets.py" -v
