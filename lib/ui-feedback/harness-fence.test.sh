#!/usr/bin/env bash
# test-scope: lib/ui-feedback/harness-fence.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/harness-fence.test.mjs"
