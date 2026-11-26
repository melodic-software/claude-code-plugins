#!/usr/bin/env bash
# test-scope: plugins/engineering-concepts/* docs/contracts/standards/examples/worked-index.md
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/adopt.test.mjs"
