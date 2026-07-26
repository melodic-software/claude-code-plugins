#!/usr/bin/env bash
# Cross-platform contract wrapper for the manifest duplicate-key detector's
# test suite. object_pairs_hook has no meaningful Python-version floor (it has
# existed since Python 2.7), so unlike the disk-hygiene probes this needs no
# MIN_PYTHON check -- only a real interpreter, not the Windows Store's App
# Execution Alias stub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A zero-length candidate under a WindowsApps path component is the Store's
# App Execution Alias stub -- executing it opens the Microsoft Store (or
# hangs) instead of running an interpreter, so each candidate is inspected
# before anything executes it.
PYTHON=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
    continue
  fi
  PYTHON="$candidate"
  break
done
if [[ -z "$PYTHON" ]]; then
  echo "SKIP: no usable Python interpreter found" >&2
  exit 0
fi

# Execute the test file directly (its unittest.main() guard) rather than via
# `-m unittest <abs path>`, which resolves the path as a module name relative
# to the caller's cwd and breaks when invoked from outside the checkout.
"$PYTHON" "$SCRIPT_DIR/test_check_manifest_duplicate_keys.py" -v
