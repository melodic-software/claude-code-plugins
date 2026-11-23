#!/usr/bin/env bash
# test-scope: plugins/autonomy/skills/setup/scripts/fixtures/prerequisite-resolution/* plugins/autonomy/generated/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node "$SCRIPT_DIR/resolve-prerequisites.fixtures.test.mjs"
