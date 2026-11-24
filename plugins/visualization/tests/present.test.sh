#!/usr/bin/env bash
# test-scope: plugins/visualization/skills/*.md plugins/visualization/evals/*.md
# test-scope: plugins/visualization/skills/present/SKILL.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/present.test.mjs"
