#!/usr/bin/env bash
# test-scope: lib/ui-feedback/dev-origin.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/dev-origin.test.mjs"
