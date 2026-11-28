#!/usr/bin/env bash
# test-scope: plugins/architecture/.claude-plugin/plugin.json plugins/architecture/templates/map-view.html plugins/architecture/scripts/build-view.mjs plugins/architecture/scripts/deepening-report.mjs plugins/architecture/scripts/testdata/deepening-candidates.json plugins/architecture/reference/html-tokens.css plugins/architecture/lib/html-branding.mjs plugins/architecture/lib/plugin-options.mjs plugins/architecture/lib/view-settings.mjs plugins/architecture/scripts/branding.test.mjs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
if ! command -v node >/dev/null 2>&1; then
  echo "branding.test.sh: node not found on PATH" >&2
  exit 2
fi

node --test --test-concurrency=4 "$SCRIPT_DIR/branding.test.mjs"
