#!/usr/bin/env bash
# Exit: 0 all tests passed; 1 a test failed; 2 no usable interpreter.
set -uo pipefail

SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_render_review.py"

for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" == *windowsapps* && ! -s "$resolved" ]] && continue
  "$candidate" "$SUITE"
  exit $?
done
echo "error: no Python interpreter found (tried python3, python); test_render_review.py cannot run" >&2
exit 2
