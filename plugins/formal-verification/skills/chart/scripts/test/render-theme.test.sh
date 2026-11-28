#!/usr/bin/env bash
# test-scope: plugins/formal-verification/.claude-plugin/plugin.json plugins/formal-verification/skills/chart/reference/render-theme.css plugins/formal-verification/reference/html-tokens.css plugins/formal-verification/skills/chart/scripts/render-theme.mjs plugins/formal-verification/lib/view-settings.mjs plugins/formal-verification/lib/plugin-options.mjs
set -euo pipefail
exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/render-theme.test.mjs"
