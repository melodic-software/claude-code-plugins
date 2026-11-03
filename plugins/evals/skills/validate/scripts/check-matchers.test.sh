#!/usr/bin/env bash
# Wrapper for check-matchers.py's unittest suite, so run-plugin-tests.sh
# discovery (plugins/**/*.test.sh) runs it. The suite's LiveRepository test runs
# the harness over the shared fragments and every plugin eval suite, so a change
# to a case grader, its samples or its matchers.json selects this file through
# the scope below. The interpreter discovery follows validate-cases.test.sh.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter.
# test-scope: plugins/*/evals/*/case.yaml plugins/*/evals/*/matchers.json
# test-scope: plugins/*/evals/*/samples/* plugins/evals/matchers/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/validate-cases.py"
SUITE="$SCRIPT_DIR/test_check_matchers.py"

FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 2
fi

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
  echo "error: Python ${FLOOR}+ not found (tried python3, python) -- check-matchers.py's suite cannot run" >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found -- check-matchers.py grades every sample under JavaScript too" >&2
  exit 2
fi

"$PYTHON" "$SUITE"
