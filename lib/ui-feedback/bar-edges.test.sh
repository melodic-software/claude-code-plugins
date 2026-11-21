#!/usr/bin/env bash
# test-scope: lib/ui-feedback/bar-edges.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/bar-edges.test.mjs"
