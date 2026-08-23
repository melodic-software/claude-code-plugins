#!/usr/bin/env bash
# Cross-platform wrapper for overlap.py's unittest suite, so the repo's
# `run-plugin-tests.sh` discovery (plugins/**/*.test.sh) actually runs it.
# The engine is Python and the runner step is bash-only, which is what this
# file bridges; the interpreter discovery below follows the repo's candidate
# loop (scripts/check-contract-clause-coverage.test.sh).
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
#
# Assertion helpers are deliberately NOT shared across plugins
# (docs/conventions/shell-test-helpers/README.md); this wrapper needs none,
# since unittest reports its own results.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/overlap.py"
SUITE="$SCRIPT_DIR/test_overlap.py"

# The Python floor has one origin: MIN_PYTHON in the engine. Parse it rather
# than restating the number here, so a floor bump cannot desync the two.
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 2
fi

# A zero-length candidate under a WindowsApps path component is the Store's App
# Execution Alias stub -- executing it opens the Microsoft Store (or hangs)
# instead of running an interpreter, so each candidate is inspected before
# anything executes it. A candidate that is real but below the floor does not
# end the search: the next candidate may satisfy it.
PYTHON=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$FLOOR'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "error: Python ${FLOOR}+ not found (tried python3, python) -- overlap.py's suite cannot run" >&2
  exit 2
fi

# Execute the suite file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SUITE"
