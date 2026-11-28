#!/usr/bin/env bash
# test-scope: plugins/planning/.claude-plugin/plugin.json plugins/planning/scripts/build-view.mjs plugins/planning/scripts/testdata/plan-record.md plugins/planning/lib/plugin-options.mjs plugins/planning/lib/html-branding.mjs plugins/planning/lib/view-settings.mjs plugins/planning/reference/html-tokens.css plugins/planning/skills/plan/templates/plan-view.html plugins/planning/skills/brainstorm/templates/brainstorm-view.html plugins/planning/skills/design/templates/design-view.html plugins/planning/tests/branding.test.mjs
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "branding.test: node not found on PATH" >&2
  exit 2
fi

node --test --test-concurrency=4 "$SCRIPT_DIR/branding.test.mjs"
