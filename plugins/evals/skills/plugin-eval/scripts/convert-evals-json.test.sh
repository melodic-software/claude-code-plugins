# shellcheck shell=bash
# Cross-platform wrapper for convert-evals-json.py's unittest suite, so the
# repo's run-plugin-tests.sh discovery (plugins/**/*.test.sh) runs it. The
# interpreter discovery follows validate-cases.test.sh beside the validator.
#
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter (a named
# environment error, never a silent skip).
# test-scope: plugins/evals/skills/validate/scripts/validate-cases.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/convert-evals-json.py"
SUITE="$SCRIPT_DIR/test_convert_evals_json.py"

# The Python floor has one origin: MIN_PYTHON in the engine.
FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$ENGINE")"
if [[ -z "$FLOOR" ]]; then
  echo "error: could not parse MIN_PYTHON from $ENGINE" >&2
  exit 2
fi

# A zero-length candidate under a WindowsApps path component is the Store's App
# Execution Alias stub, which opens the Store instead of running Python, so each
# candidate is inspected before anything executes it.
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
  echo "error: Python ${FLOOR}+ not found (tried python3, python) -- convert-evals-json.py's suite cannot run" >&2
  exit 2
fi

"$PYTHON" "$SUITE"
