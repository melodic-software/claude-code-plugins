#!/usr/bin/env bash
# Cross-platform contract wrapper for the contract-clause coverage gate's
# test suite. Same shape as scripts/check-manifest-duplicate-keys.test.sh --
# the interpreter discovery below is that file's, not a fork of it in spirit:
# both gates are Python engines run from a bash-only CI step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python floor has one origin: MIN_PYTHON in the gate itself. Parse it
# rather than restating the number here.
ENGINE="$SCRIPT_DIR/check-contract-clause-coverage.py"
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "FAIL: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 1
fi

# A zero-length candidate under a WindowsApps path component is the Store's
# App Execution Alias stub -- executing it opens the Microsoft Store (or
# hangs) instead of running an interpreter, so each candidate is inspected
# before anything executes it. A candidate that is real but below the floor
# does not end the search: the next candidate may satisfy it.
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

# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_check_contract_clause_coverage.py" -v
