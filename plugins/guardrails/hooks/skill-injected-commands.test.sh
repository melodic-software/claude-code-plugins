#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/session-attended.env
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/skill-injected-commands.test.mjs"
