#!/usr/bin/env bash
# Owns session-telemetry-state.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/session-telemetry-state.test.mjs"
