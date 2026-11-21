#!/usr/bin/env bash
# test-scope: plugins/plugin-profiles/.claude-plugin/plugin.json plugins/plugin-profiles/profiles/*.yaml plugins/plugin-profiles/evals/fixtures/fixture-market.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/install-real-claude.test.mjs"
