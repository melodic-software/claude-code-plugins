#!/usr/bin/env bash
# Runs the identity fixture's self-test: both processes start, the sign-in chain completes, and a
# redirect_uri that escapes loopback or carries a line break is refused.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if out="$(python3 -I "$SCRIPT_DIR/serve.py" --self-test 2>&1)"; then
  printf 'PASS: %s\n' "$out"
else
  printf 'FAIL: serve.py --self-test\n  detail: %s\n' "$out" >&2
  exit 1
fi
