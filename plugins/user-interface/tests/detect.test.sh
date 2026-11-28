#!/usr/bin/env bash
# test-scope: plugins/user-interface/tests/fixtures/*/package.json plugins/user-interface/tests/fixtures/*/conventions/*.yaml plugins/user-interface/tests/fixtures/*/src/*.svelte plugins/user-interface/tests/fixtures/*/src/*.vue
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/detect.test.mjs"
