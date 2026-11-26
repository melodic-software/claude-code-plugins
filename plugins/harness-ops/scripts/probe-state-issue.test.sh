#!/usr/bin/env bash
# test-scope: plugins/harness-ops/.claude-plugin/plugin.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/probe-state-issue.test.mjs"
