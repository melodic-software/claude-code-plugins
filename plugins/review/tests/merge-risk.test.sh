#!/usr/bin/env bash
# test-scope: plugins/review/skills/merge-risk/SKILL.md
# test-scope: plugins/review/skills/merge-risk/reference/rubric.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/merge-risk.test.mjs"
