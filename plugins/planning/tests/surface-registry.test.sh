#!/usr/bin/env bash
# test-scope: plugins/planning/.claude-plugin/plugin.json
# test-scope: plugins/planning/skills/interview/SKILL.md
# test-scope: plugins/planning/surfaces/entries/*.mjs
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/surface-registry.test.mjs"
