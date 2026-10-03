#!/usr/bin/env bash
# Discovery wrapper: scripts/run-plugin-tests.sh finds plugins/**/*.test.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node "$SCRIPT_DIR/resolve-prerequisites.fixtures.test.mjs"
