#!/usr/bin/env bash
# Cross-platform contract wrapper for the python3 alias-stub probe test suite.
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

# A zero-length candidate under a WindowsApps path component is the Store's App
# Execution Alias stub — the very artifact this suite tests for. Executing it
# opens the Microsoft Store (or hangs) instead of running an interpreter, so
# each candidate is inspected before anything executes it. A candidate that is
# real but below the floor does not end the search: the next candidate may
# satisfy it (e.g. an old `python` alongside a current `python3`).
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
# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_python3_alias_probe.py" -v
