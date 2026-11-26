#!/usr/bin/env bash
# test-scope: plugins/review/skills/reviewer-media/SKILL.md
# test-scope: plugins/review/schemas/reviewer-media.schema.json
# test-scope: docs/conventions/reviewer-media.yaml
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/reviewer-media.test.mjs"
