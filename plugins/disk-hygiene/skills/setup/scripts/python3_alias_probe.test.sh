#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../scripts/test-wrapper-lib.sh
source "$SCRIPT_DIR/../../../scripts/test-wrapper-lib.sh"

ENGINE="$SCRIPT_DIR/../../clean/scripts/hygiene.py"
FLOOR=""
test_wrapper::floor_to FLOOR "$ENGINE"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

FLOOR_CHECK=""
test_wrapper::floor_check_to FLOOR_CHECK "$FLOOR"

PYTHON=""
for candidate in python python3; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  if "$candidate" -c "$FLOOR_CHECK"; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: Python ${FLOOR}+ not found" >&2
  exit 0
fi
PYFILE=""
test_wrapper::python_file_to PYFILE "$SCRIPT_DIR/test_python3_alias_probe.py"
"$PYTHON" "$PYFILE" -v
