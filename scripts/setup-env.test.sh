#!/usr/bin/env bash
# Discovery wrapper: scripts/run-plugin-tests.sh finds scripts/**/*.test.sh, so this
# hands off to the Node suite.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/setup-env.test.mjs"
