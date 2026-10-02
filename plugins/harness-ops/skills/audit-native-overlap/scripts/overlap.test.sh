#!/usr/bin/env bash
# Cross-platform wrapper for overlap.py's unittest suite, so the repo's
# `run-plugin-tests.sh` discovery (plugins/**/*.test.sh) actually runs it.
# The engine is Python and the runner step is bash-only, which is what this
# file bridges; the floor parse and the floor check come from the plugin's own
# lib/python-probe.sh, and the candidate walk below stays here because this
# wrapper reports an unusable host as an error rather than a skip.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
#
# Assertion helpers are deliberately NOT shared across plugins
# (docs/conventions/shell-test-helpers/README.md); this wrapper needs none,
# since unittest reports its own results.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/python-probe.sh
source "$SCRIPT_DIR/../../../lib/python-probe.sh"
ENGINE="$SCRIPT_DIR/overlap.py"
SUITE="$SCRIPT_DIR/test_overlap.py"

FLOOR=""
python_probe::floor_to FLOOR "$ENGINE"
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
FLOOR_MET=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  python_probe::floor_met_to FLOOR_MET "$candidate" "$FLOOR" 2>/dev/null
  if [[ -n "$FLOOR_MET" ]]; then
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
