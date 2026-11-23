#!/usr/bin/env bash
# test-scope: plugins/formal-verification/defaults.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/check.test.mjs"
