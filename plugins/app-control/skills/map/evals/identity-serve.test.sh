#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if out="$(python3 -I "$SCRIPT_DIR/fixtures/identity/serve.py" --self-test 2>&1)"; then
  printf 'PASS: %s\n' "$out"
else
  printf 'FAIL: serve.py --self-test\n  detail: %s\n' "$out" >&2
  exit 1
fi
