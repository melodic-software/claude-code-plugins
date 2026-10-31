#!/usr/bin/env bash
# test-scope: plugins/user-interface/reference/types/* plugins/user-interface/reference/animation/* plugins/user-interface/reference/routing.json plugins/user-interface/skills/audit/reference/* plugins/user-interface/reference/concerns*.json plugins/user-interface/scripts/lib/*
# Discovery wrapper: scripts/run-plugin-tests.sh finds plugins/**/*.test.sh, so
# this hands off to the Node suite. SKIPs (exit 0) when Node is unavailable.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/concerns.test.mjs"
