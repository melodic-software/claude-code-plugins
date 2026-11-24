#!/usr/bin/env bash
# test-scope: plugins/*/.claude-plugin/plugin.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/view-settings.test.mjs"
