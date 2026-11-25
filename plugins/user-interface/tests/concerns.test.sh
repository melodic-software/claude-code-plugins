#!/usr/bin/env bash
# test-scope: plugins/user-interface/reference/types/* plugins/user-interface/reference/animation/* plugins/user-interface/reference/routing.json plugins/user-interface/skills/audit/reference/* plugins/user-interface/reference/concerns*.json plugins/user-interface/scripts/lib/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/concerns.test.mjs"
