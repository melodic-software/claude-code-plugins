#!/usr/bin/env bash
# test-scope: plugins/plugin-diagnostics/.claude-plugin/plugin.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/prerequisites-fleet.test.mjs"
