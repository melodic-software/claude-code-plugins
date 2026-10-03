#!/usr/bin/env bash
# Discovery wrapper: scripts/run-plugin-tests.sh finds plugins/**/*.test.sh, so
# this hands off to the Node suite. SKIPs (exit 0) when Node is unavailable.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node "$SCRIPT_DIR/check-security-binding.fixtures.test.mjs"
