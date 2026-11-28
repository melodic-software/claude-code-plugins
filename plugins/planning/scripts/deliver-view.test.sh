#!/usr/bin/env bash
# test-scope: plugins/planning/.claude-plugin/plugin.json plugins/planning/lib/plugin-options.mjs plugins/planning/lib/html-branding.mjs plugins/planning/reference/html-tokens.css
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/deliver-view.test.mjs"
