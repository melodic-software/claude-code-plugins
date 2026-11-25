#!/usr/bin/env bash
# test-scope: plugins/review/skills/council/adapters/claude.yaml plugins/review/skills/council/adapters/codex.yaml plugins/review/skills/council/adapters/antigravity.yaml
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SELF_DIR/council-plan.test.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

if [[ ! -f "$SUITE" ]]; then
  echo "FAIL: missing suite $SUITE" >&2
  exit 1
fi

node --test "$SUITE"
