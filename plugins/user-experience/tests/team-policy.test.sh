#!/usr/bin/env bash
# Discovery wrapper for the user-experience team-row admission rules: scripts/run-plugin-tests.sh
# finds plugins/**/*.test.sh, so this runs team-policy.test.mjs. SKIPs (exit 0) without Node.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/team-policy.test.mjs"
