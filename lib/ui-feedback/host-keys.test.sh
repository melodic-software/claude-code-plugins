#!/usr/bin/env bash
# test-scope: lib/ui-feedback/host.html
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/host-keys.test.mjs"
