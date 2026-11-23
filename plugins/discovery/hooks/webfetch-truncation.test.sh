#!/usr/bin/env bash
# test-scope: plugins/discovery/hooks/fixtures/* plugins/discovery/hooks/hooks.json
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/webfetch-truncation.test.mjs"
