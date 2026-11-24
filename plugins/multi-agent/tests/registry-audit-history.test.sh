#!/usr/bin/env bash
# test-scope: plugins/multi-agent/workflows/registry-audit.js plugins/multi-agent/agents/registry-judge.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/registry-audit-history.test.mjs"
