#!/usr/bin/env bash
# test-scope: plugins/discovery/agents/docs-fetcher.md plugins/discovery/hooks/hooks.json plugins/multi-agent/agents/docs-fetcher.md plugins/multi-agent/hooks/hooks.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/docs-fetcher-gate.test.mjs"
